# MTP 文件管理器

MTP 文件管理器是一款 macOS 上的 Android/MTP 设备文件传输工具，使用 SwiftUI 构建界面，并通过 Objective-C 桥接 `libmtp` 访问设备文件系统。

## 功能

- 扫描并连接 Android/MTP 设备
- 浏览设备目录和文件
- 上传、下载、删除和重命名文件
- 支持传输队列和进度展示
- 支持本地文件面板、双栏模式和拖拽传输
- 支持 Quick Look 预览部分文件类型
- 提供中文界面和 macOS 原生菜单本地化

## 系统要求

- macOS 15.0 或更高版本
- Xcode 16 或更高版本
- Homebrew
- `libmtp`

安装依赖：

```sh
brew install libmtp
```

## 构建

1. 克隆仓库：

```sh
git clone https://github.com/runsli/mtp.git
cd mtp
```

2. 打开 Xcode 工程：

```sh
open mtp.xcodeproj
```

3. 选择 `mtp` scheme，然后运行或构建项目。

也可以使用命令行构建：

```sh
xcodebuild -project mtp.xcodeproj -scheme mtp -configuration Debug build
```

## 使用说明

1. 将 Android 设备通过 USB 连接到 Mac。
2. 在手机上选择“文件传输”或“MTP”模式。
3. 如手机弹出信任提示，请允许当前电脑访问设备。
4. 启动应用后选择设备并浏览文件。

## 已知限制

- MTP 设备访问依赖系统 USB 权限、设备解锁状态和手机端传输模式。
- 不同 Android 厂商的 MTP 实现可能存在差异。
- 部分传输、拖拽和目录操作仍在完善中。
- 如果无法访问设备，请先确认手机已解锁、已选择 MTP 模式，并重新插拔 USB。

## 技术栈

- SwiftUI
- AppKit
- XCTest
- Objective-C bridge
- libmtp

## 许可证

本项目基于 MIT License 开源，详见 [LICENSE](LICENSE)。
