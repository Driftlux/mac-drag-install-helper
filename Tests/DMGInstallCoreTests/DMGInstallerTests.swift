import Foundation
import DMGInstallCore

struct DMGInstallerTests {
    func rejectsNonDMGFiles() async throws {
        let runner = MockCommandRunner()
        let installer = DMGInstaller(commandRunner: runner, fileSystem: MockFileSystem())

        let result = await installer.install(dmgURL: URL(filePath: "/tmp/Example.zip"), confirmReplace: { _ in true })

        try expect(result.status == .unsupported)
        try expect(runner.commands.isEmpty)
    }

    func reportsMountFailure() async throws {
        let runner = MockCommandRunner()
        runner.results = [
            .init(exitCode: 1, stdout: "", stderr: "attach failed")
        ]
        let installer = DMGInstaller(commandRunner: runner, fileSystem: MockFileSystem())

        let result = await installer.install(dmgURL: URL(filePath: "/tmp/Example.dmg"), confirmReplace: { _ in true })

        try expect(result.status == .mountFailed)
        try expect(result.log.joined(separator: "\n").contains("attach failed"))
    }

    func copiesAppPayloadAndRunsQuarantineRemoval() async throws {
        let volume = try TemporaryVolume()
        try volume.createDirectory("Example.app")
        let runner = MockCommandRunner()
        runner.results = [
            .init(exitCode: 0, stdout: mountPlist(for: volume.url), stderr: ""),
            .init(exitCode: 0, stdout: "", stderr: ""),
            .init(exitCode: 0, stdout: "", stderr: "")
        ]
        let fileSystem = MockFileSystem()
        let installer = DMGInstaller(commandRunner: runner, fileSystem: fileSystem)

        let result = await installer.install(dmgURL: URL(filePath: "/tmp/Example.dmg"), confirmReplace: { _ in true })

        try expect(result.status == .success)
        try expect(fileSystem.copiedApps == [
            .init(source: volume.url.appending(path: "Example.app"), destination: URL(filePath: "/Applications/Example.app"))
        ])
        try expect(runner.commands.map(\.executable.lastPathComponent) == ["hdiutil", "xattr", "hdiutil"])
    }

    func asksBeforeReplacingExistingApp() async throws {
        let volume = try TemporaryVolume()
        try volume.createDirectory("Example.app")
        let runner = MockCommandRunner()
        runner.results = [
            .init(exitCode: 0, stdout: mountPlist(for: volume.url), stderr: ""),
            .init(exitCode: 0, stdout: "", stderr: "")
        ]
        let fileSystem = MockFileSystem(existingURLs: [URL(filePath: "/Applications/Example.app")])
        let installer = DMGInstaller(commandRunner: runner, fileSystem: fileSystem)

        let result = await installer.install(dmgURL: URL(filePath: "/tmp/Example.dmg"), confirmReplace: { _ in false })

        try expect(result.status == .cancelled)
        try expect(fileSystem.copiedApps.isEmpty)
        try expect(runner.commands.map(\.executable.lastPathComponent) == ["hdiutil", "hdiutil"])
    }

    func reportsPkgInstallFailure() async throws {
        let volume = try TemporaryVolume()
        try volume.createFile("Example.pkg")
        let runner = MockCommandRunner()
        runner.results = [
            .init(exitCode: 0, stdout: mountPlist(for: volume.url), stderr: ""),
            .init(exitCode: 1, stdout: "", stderr: "authorization denied"),
            .init(exitCode: 0, stdout: "", stderr: "")
        ]
        let installer = DMGInstaller(commandRunner: runner, fileSystem: MockFileSystem())

        let result = await installer.install(dmgURL: URL(filePath: "/tmp/Example.dmg"), confirmReplace: { _ in true })

        try expect(result.status == .pkgInstallFailed)
        try expect(result.log.joined(separator: "\n").contains("authorization denied"))
    }
}
