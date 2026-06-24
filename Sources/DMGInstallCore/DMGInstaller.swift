import Foundation

public enum InstallStatus: Equatable {
    case idle
    case validating
    case mounting
    case installing
    case cleanup
    case success
    case failed
    case unsupported
    case mountFailed
    case noPayloadFound
    case copyFailed
    case pkgInstallFailed
    case cancelled
}

public struct InstallResult: Equatable {
    public let status: InstallStatus
    public let log: [String]

    public init(status: InstallStatus, log: [String]) {
        self.status = status
        self.log = log
    }
}

public struct DMGInstaller: @unchecked Sendable {
    private let commandRunner: CommandRunning
    private let fileSystem: FileSystemManaging
    private let payloadLocator: PayloadLocator
    private let applicationsDirectory: URL

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        fileSystem: FileSystemManaging = LocalFileSystemManager(),
        payloadLocator: PayloadLocator = PayloadLocator(),
        applicationsDirectory: URL = URL(filePath: "/Applications", directoryHint: .isDirectory)
    ) {
        self.commandRunner = commandRunner
        self.fileSystem = fileSystem
        self.payloadLocator = payloadLocator
        self.applicationsDirectory = applicationsDirectory
    }

    public func install(
        dmgURL: URL,
        confirmReplace: @Sendable (URL) async -> Bool
    ) async -> InstallResult {
        var log: [String] = []
        log.append("正在检查 \(dmgURL.path)")

        guard dmgURL.pathExtension.lowercased() == "dmg" else {
            log.append("当前版本只支持 .dmg 文件。")
            return .init(status: .unsupported, log: log)
        }

        log.append("正在挂载 DMG...")
        let attach = await commandRunner.run(.init(
            executable: URL(filePath: "/usr/bin/hdiutil"),
            arguments: ["attach", "-nobrowse", "-plist", dmgURL.path]
        ))

        guard attach.exitCode == 0, let mountPoint = parseMountPoint(from: attach.stdout) else {
            appendCommandFailure(attach, to: &log)
            return .init(status: .mountFailed, log: log)
        }

        log.append("已挂载到 \(mountPoint.path)")
        let installResult: InstallResult
        do {
            guard let payload = try payloadLocator.locatePayload(in: mountPoint) else {
                log.append("挂载卷中没有找到 .app 或 .pkg。")
                installResult = .init(status: .noPayloadFound, log: log)
                return await detachedResult(installResult, mountPoint: mountPoint)
            }

            switch payload {
            case .app(let appURL):
                installResult = await installApp(appURL, log: log, confirmReplace: confirmReplace)
            case .pkg(let pkgURL):
                installResult = await installPkg(pkgURL, log: log)
            }
        } catch {
            log.append("检查挂载卷失败：\(error.localizedDescription)")
            installResult = .init(status: .failed, log: log)
        }

        return await detachedResult(installResult, mountPoint: mountPoint)
    }

    private func installApp(
        _ appURL: URL,
        log initialLog: [String],
        confirmReplace: @Sendable (URL) async -> Bool
    ) async -> InstallResult {
        var log = initialLog
        let destination = applicationsDirectory.appending(path: appURL.lastPathComponent, directoryHint: .isDirectory)
        log.append("正在安装 \(appURL.lastPathComponent) 到 \(destination.path)")

        if fileSystem.itemExists(at: destination) {
            log.append("\(destination.path) 已存在，等待确认是否替换。")
            guard await confirmReplace(destination) else {
                log.append("用户已取消安装。")
                return .init(status: .cancelled, log: log)
            }

            do {
                try fileSystem.removeItem(at: destination)
                log.append("已移除旧版本应用。")
            } catch {
                log.append("无法移除旧版本应用：\(error.localizedDescription)")
                log.append("请先关闭正在运行的应用后重试；也可能需要 /Applications 的写入权限。")
                return .init(status: .copyFailed, log: log)
            }
        }

        do {
            try fileSystem.copyDirectory(from: appURL, to: destination)
            log.append("已复制应用到 /Applications。")
        } catch {
            log.append("复制失败：\(error.localizedDescription)")
            log.append("请先关闭正在运行的应用后重试；也可能需要 /Applications 的写入权限。")
            return .init(status: .copyFailed, log: log)
        }

        let xattr = await commandRunner.run(.init(
            executable: URL(filePath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", destination.path]
        ))

        if xattr.exitCode == 0 {
            log.append("已尝试移除 quarantine 隔离属性。")
        } else {
            log.append("移除 quarantine 隔离属性失败，但应用已经复制完成。")
            appendCommandFailure(xattr, to: &log)
        }

        return .init(status: .success, log: log)
    }

    private func installPkg(_ pkgURL: URL, log initialLog: [String]) async -> InstallResult {
        var log = initialLog
        log.append("正在安装 PKG：\(pkgURL.lastPathComponent)")
        let installerCommand = "/usr/sbin/installer -pkg \(ShellQuote.singleQuoted(pkgURL.path)) -target /"
        let script = "do shell script \(String(reflecting: installerCommand)) with administrator privileges"
        let result = await commandRunner.run(.init(
            executable: URL(filePath: "/usr/bin/osascript"),
            arguments: ["-e", script]
        ))

        guard result.exitCode == 0 else {
            appendCommandFailure(result, to: &log)
            return .init(status: .pkgInstallFailed, log: log)
        }

        log.append("PKG 安装完成。")
        return .init(status: .success, log: log)
    }

    private func detachedResult(_ result: InstallResult, mountPoint: URL) async -> InstallResult {
        var log = result.log
        log.append("正在卸载 \(mountPoint.path)")
        let detach = await commandRunner.run(.init(
            executable: URL(filePath: "/usr/bin/hdiutil"),
            arguments: ["detach", mountPoint.path]
        ))

        if detach.exitCode != 0 {
            log.append("卸载失败，可能需要手动推出挂载卷。")
            appendCommandFailure(detach, to: &log)
        }

        return .init(status: result.status, log: log)
    }

    private func parseMountPoint(from plistText: String) -> URL? {
        guard let data = plistText.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            return nil
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                return URL(filePath: mountPoint, directoryHint: .isDirectory)
            }
        }

        return nil
    }

    private func appendCommandFailure(_ result: CommandResult, to log: inout [String]) {
        if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log.append(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log.append(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        log.append("命令退出码：\(result.exitCode)。")
    }
}
