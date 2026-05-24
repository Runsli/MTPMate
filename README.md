# MTPMate

**English** | [简体中文](README.zh-Hans.md)

MTPMate is a macOS file transfer tool for Android/MTP devices. It uses SwiftUI for the interface and bridges to `libmtp` via Objective-C to access device file systems.

## Features

- Scan and connect to Android/MTP devices
- Browse device directories and files
- Upload, download, delete, and rename files
- Transfer queue with progress display
- Local file pane, dual-pane layout, and drag-and-drop transfers
- Quick Look preview for supported file types
- Localized UI (English and Simplified Chinese) with native macOS menus

## Requirements

- macOS 15.0 or later
- Xcode 16 or later
- Homebrew
- `libmtp`

Install dependencies:

```sh
brew install libmtp
```

## Build

1. Clone the repository:

```sh
git clone https://github.com/runsli/MTPMate.git
cd MTPMate
```

2. Open the Xcode project:

```sh
open mtp.xcodeproj
```

3. Select the `mtp` scheme, then run or build the project.

You can also build from the command line:

```sh
xcodebuild -project mtp.xcodeproj -scheme mtp -configuration Debug build
```

## Usage

1. Connect your Android device to your Mac via USB.
2. On the phone, select **File Transfer** or **MTP** mode.
3. If prompted, allow this computer to access the device.
4. Launch the app, select your device, and browse files.

## Download & Releases

The latest release is available on [GitHub Releases](https://github.com/runsli/MTPMate/releases).

To publish a new release, push a Git tag in the `v*` format to trigger the GitHub Actions workflow:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow will:

- Install `libmtp` and `libusb`
- Build a Release `MTPMate.app`
- Package it as `MTPMate-<version>-macOS-<arch>.zip`
- Create a GitHub Release
- Generate release notes from commits
- Add download links to the release description

## Known Limitations

- MTP device access depends on USB permissions, device unlock state, and the transfer mode selected on the phone.
- MTP implementations may vary across Android manufacturers.
- Some transfer, drag-and-drop, and directory operations are still being improved.
- If the device is not accessible, make sure the phone is unlocked, MTP mode is selected, and try reconnecting the USB cable.
- Release builds use ad-hoc signing and are not Apple-notarized. macOS may show a security prompt on first launch.

## Tech Stack

- SwiftUI
- AppKit
- XCTest
- Objective-C bridge
- libmtp

## License

This project is open source under the MIT License. See [LICENSE](LICENSE) for details.
