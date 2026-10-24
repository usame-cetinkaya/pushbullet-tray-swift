import CryptoKit
import Foundation

/// Talks to the Pushbullet stream and REST API: https://docs.pushbullet.com/
@MainActor
final class PushbulletClient: NSObject, URLSessionWebSocketDelegate {
    private static let streamURL = "wss://stream.pushbullet.com/websocket/"
    private static let apiURL = URL(string: "https://api.pushbullet.com/v2/")!
    /// The stream sends a `nop` this often.
    private static let nopInterval: TimeInterval = 30

    var onShow: @MainActor (Push) -> Void = { _ in }
    var onDismiss: @MainActor (Push) -> Void = { _ in }
    var onError: @MainActor (String) -> Void = { _ in }
    /// Called whenever the stream proves to be alive.
    var onActivity: @MainActor () -> Void = {}

    var e2eePassword: String? {
        didSet { if e2eePassword != oldValue { encryptionKey = nil } }
    }

    private var session: URLSession!
    private var token: String?
    private var socket: URLSessionWebSocketTask?
    /// Bumped on every (re)connect and stop so late callbacks from an old connection are ignored.
    private var generation = 0
    private var reconnectTask: Task<Void, Never>?
    private var watchdog: Timer?
    private var latestNop = Date()
    private var latestModified: Double?
    private var fetchInFlight = false
    private var fetchQueued = false
    private var userIden: String?
    private var encryptionKey: SymmetricKey?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    override init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
    }

    // MARK: Connection

    func start(token: String) {
        stop()
        self.token = token
        connect()

        let timer = Timer(timeInterval: Self.nopInterval / 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.checkHeartbeat() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    func stop() {
        token = nil
        generation += 1
        watchdog?.invalidate()
        watchdog = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        latestModified = nil
        fetchQueued = false
        userIden = nil
        encryptionKey = nil
    }

    private func connect() {
        guard let token else { return }
        generation += 1
        let current = generation
        reconnectTask?.cancel()
        reconnectTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        latestNop = Date()

        Task {
            // The user's iden salts the E2EE key, so load it before any push can arrive.
            let iden = try? decoder.decode(User.self, from: await request("users/me")).iden
            guard current == generation else { return }
            if let iden {
                if iden != userIden { encryptionKey = nil }
                userIden = iden
            } else {
                onError("Error fetching user data")
            }
            openSocket(token: token)
        }
    }

    private func openSocket(token: String) {
        let path = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        guard let url = URL(string: Self.streamURL + path) else {
            onError("Invalid access token")
            return
        }
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024
        socket = task
        task.resume()
        listen(to: task)
    }

    private func listen(to task: URLSessionWebSocketTask) {
        Task { [weak self] in
            do {
                while true {
                    let message = try await task.receive()
                    guard let self, self.socket === task else { return }
                    self.handle(message)
                }
            } catch {
                guard let self, self.socket === task else { return }
                self.socket = nil
                if task.closeCode != .invalid {
                    self.onError("WebSocket closed, reconnecting...")
                } else {
                    self.onError("WebSocket error: \(error.localizedDescription)")
                }
                self.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.nopInterval))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func checkHeartbeat() {
        if Date().timeIntervalSince(latestNop) > 2 * Self.nopInterval {
            connect()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        MainActor.assumeIsolated {
            guard webSocketTask === socket else { return }
            onActivity()
            // Keeps the watermark from before the disconnect, so pushes sent while
            // offline are shown now.
            fetchLatestPushes()
        }
    }

    // MARK: Stream

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        onActivity()

        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return
        }
        guard let event = try? decoder.decode(StreamEvent.self, from: data) else { return }

        switch event.type {
        case "nop":
            latestNop = Date()
        case "push":
            guard let encrypted = event.push else { return }
            let push = decrypt(encrypted)
            if push.type == "mirror" {
                onShow(push)
            } else if push.type == "dismissal" {
                onDismiss(push)
            }
        case "tickle" where event.subtype == "push":
            fetchLatestPushes()
        default:
            break
        }
    }

    // MARK: REST

    /// The first call after `start` only records the newest `modified`; later
    /// calls, including those after a reconnect, show or dismiss everything
    /// changed since then.
    ///
    /// Fetches run one at a time. A request made while one is running is queued and
    /// runs afterwards from the updated `latestModified`, so a tickle that arrives
    /// during the baseline fetch is not lost and no push is processed twice.
    private func fetchLatestPushes() {
        guard !fetchInFlight else {
            fetchQueued = true
            return
        }
        fetchInFlight = true
        fetchQueued = false
        let since = latestModified
        let current = generation
        Task {
            do {
                let path = since.map { "pushes?modified_after=\($0)" } ?? "pushes?limit=1"
                let pushes = try decoder.decode(PushList.self, from: await request(path)).pushes
                if current == generation {
                    apply(pushes, incremental: since != nil)
                }
            } catch {
                if current == generation {
                    onError("Error fetching pushes: \(error.localizedDescription)")
                }
            }
            fetchInFlight = false
            if fetchQueued {
                fetchLatestPushes()
            }
        }
    }

    private func apply(_ pushes: [Push], incremental: Bool) {
        if incremental {
            for push in pushes where push.type != nil {
                let push = decrypt(push)
                if push.dismissed == true {
                    onDismiss(push)
                } else {
                    onShow(push)
                }
            }
        }
        if let modified = pushes.first?.modified {
            latestModified = max(latestModified ?? 0, modified)
        }
    }

    /// Dismisses a mirrored notification on the Android device.
    func sendDismissal(_ push: Push) {
        let body = try? encoder.encode(DismissalEphemeral(dismissing: push))
        Task {
            do {
                _ = try await request("ephemerals", method: "POST", body: body)
                onDismiss(push)
            } catch {
                onError("Error sending dismissal: \(error.localizedDescription)")
            }
        }
    }

    func deleteAllPushes() {
        Task {
            do {
                _ = try await request("pushes", method: "DELETE")
            } catch {
                onError("Error clearing push history: \(error.localizedDescription)")
            }
        }
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let token, let url = URL(string: path, relativeTo: Self.apiURL) else {
            throw URLError(.userAuthenticationRequired)
        }
        var request = URLRequest(url: url.absoluteURL)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Access-Token")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            struct ErrorBody: Decodable {
                struct Detail: Decodable { let message: String? }
                let error: Detail?
            }
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.error?.message
            throw APIError(errorDescription: message ?? "HTTP \(status)")
        }
        return data
    }

    // MARK: E2EE

    private func decrypt(_ push: Push) -> Push {
        guard push.encrypted == true else { return push }
        guard let password = e2eePassword else {
            onError("E2EE is not enabled, cannot decrypt push")
            return push
        }
        do {
            let key = try key(for: password)
            let plaintext = try E2EE.decrypt(push.ciphertext ?? "", key: key)
            var merged = push.merging(try decoder.decode(Push.self, from: plaintext))
            merged.encrypted = false
            return merged
        } catch {
            onError("Failed to decrypt push message")
            return push
        }
    }

    /// PBKDF2 is deliberately slow, so the key is derived once and cached.
    private func key(for password: String) throws -> SymmetricKey {
        if let encryptionKey { return encryptionKey }
        guard let userIden else { throw E2EE.Failure.missingUser }
        let key = try E2EE.deriveKey(password: password, salt: userIden)
        encryptionKey = key
        return key
    }
}
