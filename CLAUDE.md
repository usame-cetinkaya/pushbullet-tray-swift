# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

- `scripts/build.sh` - Release build: `dist/Pushbullet Tray.app` + `.dmg` (Apple Silicon only)
- `CONFIGURATION=debug scripts/build.sh && open "dist/Pushbullet Tray.app"` - Debug build to run locally (does not register as a login item)
- `swift test` - Unit tests (Swift Testing; needs full Xcode, not just the Command Line Tools)

The app must run from a bundle: `UNUserNotificationCenter` and the bundled tray icons do not work with `swift run`.

## Goals

A native port of the Electron app [pushbullet-tray](https://github.com/usame-cetinkaya/pushbullet-tray) with feature parity. Keep memory, CPU and release size minimal: AppKit only (no SwiftUI), Apple frameworks only, no third-party packages.

## Architecture

- `App.swift` - Entry point; runs `NSApplication` as an accessory (menu bar only) app.
- `AppDelegate.swift` - `NSStatusItem` + menu, access token / E2EE password prompts, login item (`SMAppService`), and wiring between the client and the notifier. The tray shows `TrayError` with the message as tooltip after an error until the stream shows activity again.
- `PushbulletClient.swift` - WebSocket stream (`wss://stream.pushbullet.com/websocket/<token>`) and REST API.
  - On connect: fetch `users/me` (its iden salts the E2EE key), open the socket; on open, fetch `pushes?limit=1` to record the latest `modified`.
  - Stream: `nop` → heartbeat; `push` mirror → show, dismissal → dismiss; `tickle` push → fetch `pushes?modified_after=` and show/dismiss each.
  - Reconnects 30 s after a failure; a watchdog reconnects if no `nop` arrived for 60 s. A `generation` counter discards callbacks from stale connections.
- `Notifier.swift` - `UNUserNotificationCenter`. Notifications are keyed by `Push.notificationKey` (iden, or the ephemeral fields). Clicks and dismissals (via `.customDismissAction`) are reported back so mirrors are dismissed on the phone through `POST /v2/ephemerals`.
- `E2EE.swift` - PBKDF2-SHA256 (CommonCrypto) + AES-256-GCM (CryptoKit). The derived key is cached in the client.
- `Keychain.swift` - Generic passwords under service "Pushbullet Tray", accounts `accessToken` / `e2eePassword` (same as the Electron app's keytar items).
- `Models.swift` - `Push` (lenient decoding), stream/REST payloads.

## Packaging

`scripts/build.sh` assembles the bundle by hand from `Resources/` (Info.plist, AppIcon.icns, Tray*.png), strips and ad-hoc signs it (`CODESIGN_IDENTITY` overrides), and creates an LZMA-compressed DMG. `.github/workflows/build.yml` runs tests and builds on every push; pushing a tag like `1.2.3` publishes a GitHub release.
