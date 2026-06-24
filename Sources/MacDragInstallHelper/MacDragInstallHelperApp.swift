import DMGInstallCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct MacDragInstallHelperApp: App {
    var body: some Scene {
        WindowGroup {
            InstallerView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowStyle(.titleBar)
    }
}

@MainActor
final class InstallerViewModel: ObservableObject {
    @Published var phase: String = "Idle"
    @Published var log: [String] = ["Drop a .dmg file to begin."]
    @Published var isInstalling = false
    @Published var isDropTargeted = false

    private let installer = DMGInstaller()

    func install(from providers: [NSItemProvider]) -> Bool {
        guard !isInstalling else { return false }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                let droppedURL = Self.url(from: item)
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.phase = "Failed"
                        self.log.append("Could not read dropped file: \(error.localizedDescription)")
                        return
                    }

                    guard let url = droppedURL else {
                        self.phase = "Failed"
                        self.log.append("Drop item was not a local file URL.")
                        return
                    }

                    await self.install(dmgURL: url)
                }
            }
            return true
        }

        log.append("Only local .dmg files are supported.")
        return false
    }

    func install(dmgURL: URL) async {
        isInstalling = true
        phase = "Installing"
        log = ["Starting \(dmgURL.lastPathComponent)"]

        let result = await installer.install(dmgURL: dmgURL) { destination in
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Replace existing app?"
                alert.informativeText = "\(destination.path) already exists. Replace it with the app from this DMG?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Cancel")
                return alert.runModal() == .alertFirstButtonReturn
            }
        }

        log = result.log
        phase = label(for: result.status)
        isInstalling = false
    }

    private func label(for status: InstallStatus) -> String {
        switch status {
        case .idle: "Idle"
        case .validating: "Validating"
        case .mounting: "Mounting"
        case .installing: "Installing"
        case .cleanup: "Cleaning Up"
        case .success: "Success"
        case .failed: "Failed"
        case .unsupported: "Unsupported"
        case .mountFailed: "Mount Failed"
        case .noPayloadFound: "No Payload Found"
        case .copyFailed: "Copy Failed"
        case .pkgInstallFailed: "Package Install Failed"
        case .cancelled: "Cancelled"
        }
    }

    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }
}

struct InstallerView: View {
    @StateObject private var viewModel = InstallerViewModel()

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                DropPanel(viewModel: viewModel)
                    .frame(minWidth: 440, maxWidth: .infinity, minHeight: 320)

                VStack(spacing: 14) {
                    StatusPill(phase: viewModel.phase, isInstalling: viewModel.isInstalling)
                    StageRail(phase: viewModel.phase, isInstalling: viewModel.isInstalling)
                }
                .frame(width: 250)
            }

            LogPanel(lines: viewModel.log)
                .frame(minHeight: 170)
        }
        .padding(20)
        .background(AppStyle.windowBackground)
    }
}

private struct DropPanel: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac Drag Install Helper")
                        .font(.system(size: 26, weight: .semibold))
                    Text("DMG Installer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(AppStyle.accent.opacity(0.12)))
            }

            Spacer(minLength: 6)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(viewModel.isDropTargeted ? AppStyle.accent.opacity(0.18) : Color.white.opacity(0.65))
                        .frame(width: 128, height: 128)
                    Circle()
                        .stroke(viewModel.isDropTargeted ? AppStyle.accent : Color.black.opacity(0.12), lineWidth: 2)
                        .frame(width: 128, height: 128)
                    Image(systemName: viewModel.isInstalling ? "externaldrive.fill.badge.checkmark" : "arrow.down.doc.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(viewModel.isDropTargeted ? AppStyle.accent : AppStyle.ink.opacity(0.78))
                }

                Text(viewModel.isInstalling ? "Installing" : "Drop DMG")
                    .font(.system(size: 32, weight: .bold))
                Text(viewModel.isInstalling ? "Keep this window open while macOS completes the install." : "Release a .dmg file anywhere in this panel.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 6)

            HStack(spacing: 10) {
                CapabilityBadge(icon: "doc.badge.gearshape", title: ".app")
                CapabilityBadge(icon: "shippingbox", title: ".pkg")
                CapabilityBadge(icon: "lock.shield", title: "quarantine")
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppStyle.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(viewModel.isDropTargeted ? AppStyle.accent : Color.black.opacity(0.10), lineWidth: viewModel.isDropTargeted ? 3 : 1)
        )
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $viewModel.isDropTargeted,
            perform: viewModel.install(from:)
        )
    }
}

private struct CapabilityBadge: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(AppStyle.ink.opacity(0.76))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.72)))
    }
}

private struct StatusPill: View {
    let phase: String
    let isInstalling: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Status")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 14, height: 14)
                Text(phase)
                    .font(.system(size: 23, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppStyle.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10), lineWidth: 1))
    }

    private var statusColor: Color {
        if isInstalling { return AppStyle.accent }
        if phase == "Success" { return AppStyle.success }
        if phase.contains("Failed") || phase == "Unsupported" { return AppStyle.warning }
        return Color.secondary
    }
}

private struct StageRail: View {
    let phase: String
    let isInstalling: Bool

    private let stages = [
        ("checkmark.shield", "Validate"),
        ("externaldrive.badge.plus", "Mount"),
        ("arrow.down.app", "Install"),
        ("eject", "Clean Up")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Flow")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                HStack(spacing: 12) {
                    Image(systemName: stage.0)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color(for: index))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(color(for: index).opacity(0.13)))

                    Text(stage.1)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppStyle.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10), lineWidth: 1))
    }

    private func color(for index: Int) -> Color {
        if phase == "Success" { return AppStyle.success }
        if phase.contains("Failed") || phase == "Unsupported" { return index == activeIndex ? AppStyle.warning : Color.secondary }
        if isInstalling && index <= activeIndex { return AppStyle.accent }
        return Color.secondary.opacity(0.75)
    }

    private var activeIndex: Int {
        if phase == "Mounting" || phase == "Mount Failed" { return 1 }
        if phase == "Installing" || phase.contains("Install") || phase == "Copy Failed" { return 2 }
        if phase == "Cleaning Up" { return 3 }
        return 0
    }
}

private struct LogPanel: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Install Log", systemImage: "terminal")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(lines.count) lines")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(format: "%02d", index + 1))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(line)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 12, design: .monospaced))
                    }
                }
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.84)))
            .foregroundStyle(Color.white.opacity(0.90))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppStyle.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10), lineWidth: 1))
    }
}

private enum AppStyle {
    static let accent = Color(red: 0.10, green: 0.35, blue: 0.92)
    static let success = Color(red: 0.04, green: 0.55, blue: 0.30)
    static let warning = Color(red: 0.84, green: 0.28, blue: 0.16)
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let windowBackground = Color(red: 0.92, green: 0.93, blue: 0.94)
    static let panelBackground = Color(red: 0.985, green: 0.985, blue: 0.97)
}
