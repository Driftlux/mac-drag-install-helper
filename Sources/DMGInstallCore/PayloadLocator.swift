import Foundation

public enum InstallPayload: Equatable {
    case app(URL)
    case pkg(URL)

    public static func == (lhs: InstallPayload, rhs: InstallPayload) -> Bool {
        switch (lhs, rhs) {
        case (.app(let lhsURL), .app(let rhsURL)),
             (.pkg(let lhsURL), .pkg(let rhsURL)):
            return lhsURL.standardizedFileURL.path == rhsURL.standardizedFileURL.path
        default:
            return false
        }
    }
}

public struct PayloadLocator {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func locatePayload(in mountedVolume: URL) throws -> InstallPayload? {
        let children = try fileManager.contentsOfDirectory(
            at: mountedVolume,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        )

        let sorted = children.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        if let app = sorted.first(where: { $0.pathExtension.lowercased() == "app" }) {
            return .app(app)
        }

        if let pkg = sorted.first(where: { $0.pathExtension.lowercased() == "pkg" }) {
            return .pkg(pkg)
        }

        return nil
    }
}
