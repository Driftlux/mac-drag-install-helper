import Foundation
import DMGInstallCore

struct TestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String = "Expectation failed",
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    if !condition() {
        throw TestFailure(message: "\(file):\(line): \(message)")
    }
}

struct TemporaryVolume {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createDirectory(_ name: String) throws {
        try FileManager.default.createDirectory(at: url.appending(path: name), withIntermediateDirectories: true)
    }

    func createFile(_ name: String) throws {
        FileManager.default.createFile(atPath: url.appending(path: name).path, contents: Data())
    }
}

final class MockCommandRunner: CommandRunning {
    var results: [CommandResult] = []
    private(set) var commands: [Command] = []

    func run(_ command: Command) async -> CommandResult {
        commands.append(command)
        guard !results.isEmpty else {
            return .init(exitCode: 0, stdout: "", stderr: "")
        }
        return results.removeFirst()
    }
}

final class MockFileSystem: FileSystemManaging {
    struct Copy: Equatable {
        let source: URL
        let destination: URL

        static func == (lhs: Copy, rhs: Copy) -> Bool {
            lhs.source.standardizedFileURL.path == rhs.source.standardizedFileURL.path
                && lhs.destination.standardizedFileURL.path == rhs.destination.standardizedFileURL.path
        }
    }

    var existingPaths: Set<String>
    private(set) var copiedApps: [Copy] = []
    var copyError: Error?

    init(existingURLs: Set<URL> = []) {
        existingPaths = Set(existingURLs.map { $0.standardizedFileURL.path })
    }

    func itemExists(at url: URL) -> Bool {
        existingPaths.contains(url.standardizedFileURL.path)
    }

    func removeItem(at url: URL) throws {
        existingPaths.remove(url.standardizedFileURL.path)
    }

    func copyDirectory(from source: URL, to destination: URL) throws {
        if let copyError {
            throw copyError
        }
        copiedApps.append(.init(source: source, destination: destination))
        existingPaths.insert(destination.standardizedFileURL.path)
    }
}

func mountPlist(for mountPoint: URL) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>system-entities</key>
      <array>
        <dict>
          <key>mount-point</key>
          <string>\(mountPoint.path)</string>
        </dict>
      </array>
    </dict>
    </plist>
    """
}
