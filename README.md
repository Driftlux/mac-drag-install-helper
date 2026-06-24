# DMG安装器，mac软件一键安装

一个未签名的 macOS 可视化小工具，用来简化 `.dmg` 安装包的安装流程：把 DMG 拖进窗口，应用会自动挂载、识别安装内容，并尽量完成后续安装步骤。

## 功能

- 支持把本地 `.dmg` 文件拖入应用窗口。
- 自动使用 `hdiutil` 挂载 DMG。
- 自动识别挂载卷里的安装内容：
  - 优先安装 `.app`，复制到 `/Applications`。
  - 如果没有 `.app`，则尝试安装 `.pkg`。
- 复制 `.app` 后，尝试移除 `com.apple.quarantine` 隔离属性。
- 如果 `/Applications` 里已经有同名应用，会先弹窗确认再替换。
- 安装结束后自动卸载挂载卷。
- 在界面中显示安装状态、流程进度和详细日志。

第一版只支持 `.dmg`。暂不支持 `.zip`、直接拖入 `.app`，也不会执行任意自定义命令。

## 构建

项目使用 Swift Package Manager，不需要完整的 Xcode 工程。

```sh
swift run DMGInstallCoreTests
swift build -c release --product MacDragInstallHelper
./scripts/build-app.sh
```

打包后的应用会生成在：

```text
dist/DMG安装器.app
```

## 使用

1. 运行 `./scripts/build-app.sh`。
2. 打开 `dist/DMG安装器.app`。
3. 点击工具栏里的 **选择 DMG** 从文件夹中选择安装包，或直接把 `.dmg` 文件拖入窗口。
4. 点击 **安装**，根据界面提示确认替换已有应用，或输入 macOS 管理员密码完成 `.pkg` 安装。

## 首次运行提示

这个应用默认是未签名的，macOS 第一次打开时可能会拦截。

如果被拦截，可以进入 **系统设置 > 隐私与安全性** 允许打开，或者按住 Control 点击应用并选择 **打开**。

如果 macOS 提示“应用已损坏，无法打开”，一般是下载隔离属性导致的。可以在终端执行：

```sh
xattr -dr com.apple.quarantine /Applications/DMG安装器.app
```

然后再打开应用。

要彻底避免这类提示，需要使用 Apple Developer ID 对应用签名并公证；当前 release 是自用/测试用途的未公证版本。

## 安全边界

这个工具会自动执行 macOS 允许的安装步骤，例如挂载 DMG、复制 `.app`、移除 quarantine 属性和调用系统安装器。

但它不会绕过 macOS 必须由用户确认的安全机制。遇到 `.pkg` 管理员授权、系统隐私权限或 Gatekeeper 拦截时，仍然需要用户手动确认。
