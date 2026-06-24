# Mac DMG Drag Install Helper

A small unsigned macOS utility for installing apps from `.dmg` files by drag and drop.

## What v1 Supports

- Drag a local `.dmg` file onto the app window.
- Automatically mount the DMG with `hdiutil`.
- Install the first supported payload in the mounted volume:
  - Prefer `.app` bundles and copy them to `/Applications`.
  - Otherwise install `.pkg` packages with macOS administrator authorization.
- Remove `com.apple.quarantine` from copied `.app` bundles where macOS permits it.
- Ask before replacing an existing app in `/Applications`.
- Detach the mounted volume after the install attempt.

This version intentionally does not support `.zip`, direct `.app` drops, or arbitrary command execution.

## Build

This project uses Swift Package Manager and does not require a full Xcode project.

```sh
swift test
swift build -c release
./scripts/build-app.sh
```

The packaged app is written to:

```text
dist/MacDragInstallHelper.app
```

## First Run

The app bundle is unsigned. macOS may block the first launch.

If that happens, open **System Settings > Privacy & Security** and allow the app, or control-click the app and choose **Open**.

The helper automates install steps that macOS allows, but system prompts such as administrator authorization for `.pkg` installers still require your approval.
