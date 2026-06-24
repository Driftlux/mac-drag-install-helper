import Foundation

public protocol FileSystemManaging {
    func itemExists(at url: URL) -> Bool
    func removeItem(at url: URL) throws
    func copyDirectory(from source: URL, to destination: URL) throws
}

public struct LocalFileSystemManager: FileSystemManaging {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    public func copyDirectory(from source: URL, to destination: URL) throws {
        try fileManager.copyItem(at: source, to: destination)
    }
}
