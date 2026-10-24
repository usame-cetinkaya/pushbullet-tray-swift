# pushbullet-tray-swift

A menu bar–only [Pushbullet](https://www.pushbullet.com/) client for macOS, written in Swift.

This is a native port of [pushbullet-tray](https://github.com/usame-cetinkaya/pushbullet-tray) (Electron) with the same features. It uses only Apple's built-in frameworks: no third-party dependencies, a single process, about 15 MB of memory, and a download of a few hundred KB.

Requires an Apple Silicon Mac running macOS 13 Ventura or later.

## Features

- Displays mirrored Android notifications from Pushbullet on macOS.
- Displays push notifications sent to your Pushbullet account via API.
- Supports Pushbullet end-to-end encryption.
- Runs on system startup. That way you don't have to remember to open it every time you restart your computer.

## Mirrored Notifications

- Dismiss notifications on macOS and they will be dismissed on your Android device.
- Dismiss notifications on your Android device and they will be dismissed on macOS.

macOS reports a dismissal when you click a notification or close it with its ✕ / "Clear" button. A banner that simply times out and slides into Notification Center is not reported, so it stays on your phone.

## Installation

1. Download the latest `.dmg` file from the [Releases](https://github.com/usame-cetinkaya/pushbullet-tray-swift/releases) page.
2. Double-click it when it is downloaded.
3. Drag the "Pushbullet Tray.app" icon on to the "Applications" icon.
4. Run it from the macOS Launchpad, or Spotlight (Cmd+Space).

When you run the app you might see a warning like this:

> macOS cannot verify the developer of "Pushbullet Tray". Are you sure you want to open it?

Here is how to fix it:

1. Click the **Done** (or **Cancel**) button of the warning message.
2. Go to **System Settings > Privacy & Security**.
3. Scroll down to the bottom.
4. Find the message **"Pushbullet Tray" was blocked...** and click the **Open Anyway** button.

You can also refer to this [Apple Support](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) page for more information.

Allow notifications when macOS asks. If you missed it, enable them in **System Settings > Notifications > Pushbullet Tray**.

## Connecting Your Pushbullet Account

1. Go to [Pushbullet](https://www.pushbullet.com/) and sign in.
2. On the left side of the screen, click **Settings**.
3. On the right side of the screen, click the **Create Access Token** button.
4. Copy the access token.
5. Click on the icon in the menu bar.
6. Click on the **Set Access Token...** option in the menu.
7. Paste your Pushbullet access token and click **OK**.

The token is stored in your macOS Keychain. If you used the Electron version before, its saved token and encryption password are picked up automatically. macOS asks once whether to allow access; click **Always Allow**.

## End-to-End Encryption

If you enabled end-to-end encryption in Pushbullet on your phone, choose **Enable End-to-End Encryption...** from the menu and enter the same password.

## A Note About `Delete Push History` Option

If you are using Pushbullet to get notifications from other services like me, you may want to delete the push history from time to time. This option will delete all push history from your Pushbullet account. It will not delete the notifications from your Android device.

## Building

Requires Xcode or the Xcode Command Line Tools (Swift 6).

```bash
scripts/build.sh
```

This produces `dist/Pushbullet Tray.app` and `dist/Pushbullet-Tray-<version>-arm64.dmg`. For a development build that does not register itself as a login item:

```bash
CONFIGURATION=debug scripts/build.sh && open "dist/Pushbullet Tray.app"
```

Pushing a tag such as `1.0.0` builds the app on GitHub Actions and publishes a release with the `.dmg`.
