import AppKit
import ServiceManagement

/// The menu bar item, its menu, and the wiring between the client and notifications.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = PushbulletClient()
    private let notifier = Notifier()
    private var statusItem: NSStatusItem?
    private var accessToken: String?
    private var e2eePassword: String?
    private var errorMessage: String?
    private let normalIcon = trayImage(named: "TrayIcon")
    private let errorIcon = trayImage(named: "TrayError")

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        client.onShow = { [unowned self] in notifier.show($0) }
        client.onDismiss = { [unowned self] in notifier.dismiss($0) }
        client.onError = { [unowned self] in setError($0) }
        client.onActivity = { [unowned self] in setError(nil) }
        notifier.onError = { [unowned self] in setError($0) }
        notifier.onUserDismiss = { [unowned self] push in
            // Only mirrored notifications exist on the phone; other pushes just go away locally.
            if push.type == "mirror" {
                client.sendDismissal(push)
            } else {
                notifier.dismiss(push)
            }
        }

        accessToken = Keychain.get(.accessToken)
        e2eePassword = Keychain.get(.e2eePassword)
        client.e2eePassword = e2eePassword

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        rebuildMenu()

        registerLoginItem()
        notifier.requestAuthorization()
        if let accessToken {
            client.start(token: accessToken)
        }
    }

    // MARK: Tray

    private static func trayImage(named name: String) -> NSImage? {
        guard let image = Bundle.main.image(forResource: name) else { return nil }
        image.size = NSSize(width: 24, height: 24)
        image.isTemplate = true
        return image
    }

    private func setError(_ message: String?) {
        guard message != errorMessage else { return }
        errorMessage = message
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let image = errorMessage == nil ? normalIcon : errorIcon
        button.image = image
        button.title = image == nil ? "PB" : ""
        button.toolTip = errorMessage ?? "Pushbullet Tray"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        if accessToken != nil {
            menu.addItem(item("Clear Access Token", #selector(clearAccessToken)))
            menu.addItem(.separator())
            menu.addItem(item(
                e2eePassword != nil ? "✓ End-to-End Encryption Enabled" : "Enable End-to-End Encryption...",
                #selector(toggleE2EE)
            ))
            menu.addItem(.separator())
            menu.addItem(item("Delete Push History", #selector(deletePushHistory)))
        } else {
            menu.addItem(item("Set Access Token...", #selector(setAccessToken)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit)))
        statusItem?.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func setAccessToken() {
        guard let token = prompt(title: "Enter Access Token", label: "Access Token:") else { return }
        guard Keychain.set(token, for: .accessToken) else {
            setError("Error saving access token to Keychain")
            return
        }
        accessToken = token
        setError(nil)
        rebuildMenu()
        client.start(token: token)
    }

    @objc private func clearAccessToken() {
        Keychain.delete(.accessToken)
        accessToken = nil
        client.stop()
        setError(nil)
        rebuildMenu()
    }

    @objc private func toggleE2EE() {
        if e2eePassword != nil {
            Keychain.delete(.e2eePassword)
            e2eePassword = nil
        } else {
            guard let password = prompt(title: "Enter E2EE Password", label: "Encryption Password:") else { return }
            guard Keychain.set(password, for: .e2eePassword) else {
                setError("Error saving E2EE password to Keychain")
                return
            }
            e2eePassword = password
        }
        client.e2eePassword = e2eePassword
        setError(nil)
        rebuildMenu()
    }

    @objc private func deletePushHistory() {
        client.deleteAllPushes()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    /// Asks for a secret. Returns nil when cancelled or left empty.
    private func prompt(title: String, label: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = label
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// A menu bar app has no visible main menu, but text fields need one for ⌘V and friends.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Start at login, like the Electron version. Skipped in debug builds so
    /// development copies never register themselves.
    private func registerLoginItem() {
        #if !DEBUG
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        #endif
    }
}
