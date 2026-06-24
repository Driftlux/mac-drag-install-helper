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
        log.append("Validating \(dmgURL.path)")

        guard dmgURL.pathExtension.lowercased() == "dmg" else {
            log.append("Only .dmg files are supported in v1.")
            return .init(status: .unsupported, log: log)
        }

        log.append("Mounting DMG...")
        let attach = await commandRunner.run(.init(
            executable: URL(filePath: "/usr/bin/hdiutil"),
            arguments: ["attach", "-nobrowse", "-plist", dmgURL.path]
        ))

        guard attach.exitCode == 0, let mountPoint = parseMountPoint(from: attach.stdout) else {
            appendCommandFailure(attach, to: &log)
            return .init(status: .mountFailed, log: log)
        }

        log.append("Mounted at \(mountPoint.path)")
        let installResult: InstallResult
        do {
            guard let payload = try payloadLocator.locatePayload(in: mountPoint) else {
                log.append("No .app or .pkg payload found in mounted volume.")
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
            log.append("Failed to inspect mounted volume: \(error.localizedDescription)")
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
        log.append("Installing \(appURL.lastPathComponent) to \(destination.path)")

        if fileSystem.itemExists(at: destination) {
            log.append("\(destination.path) already exists; asking before replacement.")
            guard await confirmReplace(destination) else {
                log.append("Installation cancelled by user.")
                return .init(status: .cancelled, log: log)
            }

            do {
                try fileSystem.removeItem(at: destination)
                log.append("Removed existing app.")
            } catch {
                log.append("Could not remove existing app: \(error.localizedDescription)")
                log.append("Close the app if it is running, then retry. You may also need permission to write to /Applications.")
                return .init(status: .copyFailed, log: log)
            }
        }

        do {
            try fileSystem.copyDirectory(from: appURL, to: destination)
            log.append("Copied app to /Applications.")
        } catch {
            log.append("Copy failed: \(error.localizedDescription)")
            log.append("Close the app if it is running, then retry. You may also need permission to write to /Applications.")
            return .init(status: .copyFailed, log: log)
        }

        let xattr = await commandRunner.run(.init(
            executable: URL(filePath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", destination.path]
        ))

        if xattr.exitCode == 0 {
            log.append("Removed quarantine attribute where present.")
        } else {
            log.append("Quarantine removal failed, but the app was copied.")
            appendCommandFailure(xattr, to: &log)
        }

        return .init(status: .success, log: log)
    }

    private func installPkg(_ pkgURL: URL, log initialLog: [String]) async -> InstallResult {
        var log = initialLog
        log.append("Installing package \(pkgURL.lastPathComponent)")
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

        log.append("Package installed.")
        return .init(status: .success, log: log)
    }

    private func detachedResult(_ result: InstallResult, mountPoint: URL) async -> InstallResult {
        var log = result.log
        log.append("Detaching \(mountPoint.path)")
        let detach = await commandRunner.run(.init(
            executable: URL(filePath: "/usr/bin/hdiutil"),
            arguments: ["detach", mountPoint.path]
        ))

        if detach.exitCode != 0 {
            log.append("Detach failed; you may need to eject the mounted volume manually.")
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
        log.append("Command exited with code \(result.exitCode).")
    }
}
