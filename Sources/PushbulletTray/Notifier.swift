import Foundation
import UserNotifications

/// Shows pushes as macOS notifications and reports when the user clicks or dismisses one.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let disabledMessage = "Please enable notifications in System Settings > Notifications > Pushbullet Tray"
    private static let category = "push"
    private nonisolated static let pushKey = "push"

    /// Called when the user clicks or dismisses a notification.
    var onUserDismiss: @MainActor (Push) -> Void = { _ in }
    var onError: @MainActor (String) -> Void = { _ in }

    /// nil when running outside an app bundle (e.g. `swift run`), where the framework is unavailable.
    private let center: UNUserNotificationCenter?
    private var active: [String: Push] = [:]

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
        // `.customDismissAction` makes the system report dismissals, not just clicks.
        center?.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [], intentIdentifiers: [], options: .customDismissAction)
        ])
    }

    func requestAuthorization() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard !granted else { return }
            Task { @MainActor in self?.onError(Self.disabledMessage) }
        }
    }

    func show(_ push: Push) {
        let key = push.notificationKey
        // The same push can arrive more than once. An Android notification updated in
        // place (a new chat message) keeps its key but changes content; reposting it
        // under the same identifier replaces the banner.
        if let shown = active[key], shown.hasSameContent(as: push) { return }
        active[key] = push
        guard let center else { return }

        let content = UNMutableNotificationContent()
        let appName = push.applicationName.flatMap { $0.isEmpty ? nil : $0 } ?? "Pushbullet"
        if let title = push.title, !title.isEmpty {
            content.title = "\(appName): \(title)"
        } else {
            content.title = appName
        }
        content.body = push.body ?? ""
        content.sound = .default
        content.categoryIdentifier = Self.category
        if let icon = Self.iconAttachment(push.icon) {
            content.attachments = [icon]
        }
        // Enough of the push to dismiss it on the phone, even after a relaunch.
        var reference = push
        reference.title = nil
        reference.body = nil
        reference.icon = nil
        reference.ciphertext = nil
        if let data = try? JSONEncoder().encode(reference) {
            content.userInfo = [Self.pushKey: data]
        }

        center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.addFailed(key) }
        }
    }

    /// Forget a notification that never appeared so a later copy can still show.
    private func addFailed(_ key: String) {
        active.removeValue(forKey: key)
        onError(Self.disabledMessage)
    }

    func dismiss(_ push: Push) {
        let key = push.notificationKey
        active.removeValue(forKey: key)
        // Not guarded by `active`: banners shown before a relaunch must go too.
        center?.removeDeliveredNotifications(withIdentifiers: [key])
        center?.removePendingNotificationRequests(withIdentifiers: [key])
    }

    /// Attachments must be files; the system moves the file into its own store.
    private static func iconAttachment(_ base64: String?) -> UNNotificationAttachment? {
        guard let base64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), !data.isEmpty else {
            return nil
        }
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(isPNG ? "png" : "jpg")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "icon", url: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// `active` is empty after a relaunch, so fall back to the push stored in the notification.
    private func userResponded(to key: String, stored: Data?) {
        guard let push = active[key] ?? stored.flatMap({ try? JSONDecoder().decode(Push.self, from: $0) }) else {
            return
        }
        onUserDismiss(push)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        await userResponded(to: request.identifier, stored: request.content.userInfo[Self.pushKey] as? Data)
    }
}
