import AppKit
import DMGInstallCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct MacDragInstallHelperApp: App {
    var body: some Scene {
        WindowGroup {
            InstallerView()
                .frame(minWidth: 1120, minHeight: 680)
        }
        .windowStyle(.titleBar)
    }
}

@MainActor
final class InstallerViewModel: ObservableObject {
    @Published var phase = "待命"
    @Published var log: [String] = ["从工具栏选择 DMG，或把 .dmg 文件拖入窗口。"]
    @Published var selectedDMG: URL?
    @Published var recentDMGs: [URL] = []
    @Published var isInstalling = false
    @Published var isDropTargeted = false

    private let installer = DMGInstaller()
    private var didOfferSelfInstall = false

    var subtitle: String {
        if isInstalling { return "正在处理安装包" }
        if selectedDMG == nil { return "未选择文件" }
        return selectedDMG?.lastPathComponent ?? "已选择文件"
    }

    func chooseDMG() {
        let panel = NSOpenPanel()
        panel.title = "选择 DMG 安装包"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "dmg") ?? .diskImage]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        selectDMG(url)
    }

    func offerSelfInstallIfNeeded() {
        guard !didOfferSelfInstall else { return }
        didOfferSelfInstall = true

        let appURL = Bundle.main.bundleURL
        guard appURL.path.hasPrefix("/Volumes/") else { return }

        let alert = NSAlert()
        alert.messageText = "要安装 DMG安装器 吗？"
        alert.informativeText = "当前正在从磁盘映像中运行。推出 DMG 后，这个 App 会从访达中消失。建议先复制到“应用程序”文件夹。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "安装到应用程序")
        alert.addButton(withTitle: "稍后")

        guard alert.runModal() == .alertFirstButtonReturn else {
            log.append("当前仍在 DMG 中运行。推出磁盘映像前，请先复制到 /Applications。")
            return
        }

        installSelfToApplications(from: appURL)
    }

    func selectDMG(_ url: URL) {
        guard url.pathExtension.lowercased() == "dmg" else {
            phase = "不支持"
            log.append("当前版本只支持 .dmg 文件：\(url.lastPathComponent)")
            return
        }

        selectedDMG = url
        recentDMGs.removeAll { $0.standardizedFileURL.path == url.standardizedFileURL.path }
        recentDMGs.insert(url, at: 0)
        recentDMGs = Array(recentDMGs.prefix(8))
        phase = "待安装"
        log = ["已选择 \(url.lastPathComponent)", "点击右上角“安装”开始处理。"]
    }

    func clearSelection() {
        selectedDMG = nil
        phase = "待命"
        log = ["从工具栏选择 DMG，或把 .dmg 文件拖入窗口。"]
    }

    func installSelected() {
        guard let selectedDMG else {
            log.append("请先选择一个 .dmg 文件。")
            return
        }

        Task {
            await install(dmgURL: selectedDMG)
        }
    }

    func install(from providers: [NSItemProvider]) -> Bool {
        guard !isInstalling else { return false }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                let droppedURL = Self.url(from: item)
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.phase = "失败"
                        self.log.append("无法读取拖入的文件：\(error.localizedDescription)")
                        return
                    }

                    guard let url = droppedURL else {
                        self.phase = "失败"
                        self.log.append("拖入内容不是本地文件。")
                        return
                    }

                    self.selectDMG(url)
                }
            }
            return true
        }

        log.append("当前版本只支持本地 .dmg 文件。")
        return false
    }

    func install(dmgURL: URL) async {
        isInstalling = true
        phase = "安装中"
        log = ["开始处理 \(dmgURL.lastPathComponent)"]

        let result = await installer.install(dmgURL: dmgURL) { destination in
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "要替换已有应用吗？"
                alert.informativeText = "\(destination.path) 已存在。是否用这个 DMG 里的应用替换它？"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "替换")
                alert.addButton(withTitle: "取消")
                return alert.runModal() == .alertFirstButtonReturn
            }
        }

        log = result.log
        phase = label(for: result.status)
        isInstalling = false
    }

    private func installSelfToApplications(from sourceURL: URL) {
        let destinationURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
            .appending(path: sourceURL.lastPathComponent, directoryHint: .isDirectory)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            removeQuarantine(at: destinationURL)
            log.append("已安装到 \(destinationURL.path)。正在打开已安装版本。")
            openInstalledCopyAndQuit(destinationURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法复制到应用程序"
            alert.informativeText = "请手动把 DMG 中的 DMG安装器.app 拖到“应用程序”文件夹。\n\n错误：\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            log.append("复制到 /Applications 失败：\(error.localizedDescription)")
        }
    }

    private func removeQuarantine(at appURL: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", appURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func openInstalledCopyAndQuit(_ appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "已复制，但无法自动打开"
                    alert.informativeText = "请从“应用程序”文件夹手动打开 DMG安装器。\n\n错误：\(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "知道了")
                    alert.runModal()
                }
                return
            }

            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    private func label(for status: InstallStatus) -> String {
        switch status {
        case .idle: "待命"
        case .validating: "正在检查"
        case .mounting: "正在挂载"
        case .installing: "安装中"
        case .cleanup: "正在清理"
        case .success: "安装完成"
        case .failed: "失败"
        case .unsupported: "不支持"
        case .mountFailed: "挂载失败"
        case .noPayloadFound: "未找到应用"
        case .copyFailed: "复制失败"
        case .pkgInstallFailed: "安装包失败"
        case .cancelled: "已取消"
        }
    }

    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }
}

struct InstallerView: View {
    @StateObject private var viewModel = InstallerViewModel()

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(viewModel: viewModel)
                .frame(width: 220)

            Divider()

            VStack(spacing: 0) {
                Toolbar(viewModel: viewModel)

                Divider()

                HStack(spacing: 0) {
                    DMGListPane(viewModel: viewModel)
                        .frame(width: 360)

                    Divider()

                    DetailPane(viewModel: viewModel)
                }
            }
        }
        .background(AppStyle.windowBackground)
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $viewModel.isDropTargeted,
            perform: viewModel.install(from:)
        )
        .onAppear {
            viewModel.offerSelfInstallIfNeeded()
        }
    }
}

private struct Sidebar: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
                .frame(height: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("DMG安装器")
                    .font(.system(size: 20, weight: .semibold))
                Text("本地安装工具")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)

            SidebarSection(title: "安装") {
                SidebarItem(icon: "opticaldiscdrive.fill", title: "DMG 文件", isSelected: true)
                SidebarItem(icon: "clock.arrow.circlepath", title: "最近选择", isSelected: false)
            }

            SidebarSection(title: "工具") {
                SidebarItem(icon: "terminal", title: "安装日志", isSelected: false)
                SidebarItem(icon: "lock.shield", title: "安全说明", isSelected: false)
            }

            SidebarSection(title: "系统") {
                SidebarItem(icon: "externaldrive", title: "挂载流程", isSelected: false)
            }

            Spacer()

            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: statusIcon).foregroundStyle(.white).font(.system(size: 15, weight: .semibold)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.phase)
                        .font(.system(size: 14, weight: .semibold))
                    Text(viewModel.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.58))
            .overlay(Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1), alignment: .top)
        }
        .background(AppStyle.sidebarBackground)
    }

    private var statusColor: Color {
        if viewModel.isInstalling { return AppStyle.accent }
        if viewModel.phase == "安装完成" { return AppStyle.success }
        if viewModel.phase.contains("失败") || viewModel.phase == "不支持" { return AppStyle.warning }
        return AppStyle.neutral
    }

    private var statusIcon: String {
        if viewModel.isInstalling { return "arrow.triangle.2.circlepath" }
        if viewModel.phase == "安装完成" { return "checkmark" }
        if viewModel.phase.contains("失败") || viewModel.phase == "不支持" { return "exclamationmark" }
        return "clock"
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)

            VStack(spacing: 4) {
                content
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct SidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.78))
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.black.opacity(0.10) : Color.clear))
    }
}

private struct Toolbar: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DMG 文件")
                    .font(.system(size: 21, weight: .semibold))
                Text(viewModel.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ToolbarButton(icon: "folder", title: "选择 DMG") {
                viewModel.chooseDMG()
            }

            ToolbarButton(icon: "play.fill", title: "安装", isProminent: true, isDisabled: viewModel.selectedDMG == nil || viewModel.isInstalling) {
                viewModel.installSelected()
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 72)
        .background(AppStyle.toolbarBackground)
    }
}

private struct ToolbarButton: View {
    let icon: String
    let title: String
    var isProminent = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(isProminent ? AppStyle.accent : Color.white.opacity(0.84)))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

private struct DMGListPane: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("待安装")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.recentDMGs.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .frame(height: 46)

            Divider()

            if viewModel.recentDMGs.isEmpty {
                EmptyListDropTarget(viewModel: viewModel)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.recentDMGs, id: \.standardizedFileURL.path) { url in
                            DMGRow(url: url, isSelected: isSelected(url), isInstalling: viewModel.isInstalling)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectDMG(url)
                                }
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            }
        }
        .background(Color.white.opacity(0.62))
    }

    private func isSelected(_ url: URL) -> Bool {
        viewModel.selectedDMG?.standardizedFileURL.path == url.standardizedFileURL.path
    }
}

private struct EmptyListDropTarget: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(viewModel.isDropTargeted ? AppStyle.accent : Color.secondary)
            Text("拖入 DMG 文件")
                .font(.system(size: 18, weight: .semibold))
            Text("也可以点击右上角“选择 DMG”从文件夹中选取。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .background(viewModel.isDropTargeted ? AppStyle.accent.opacity(0.07) : Color.clear)
    }
}

private struct DMGRow: View {
    let url: URL
    let isSelected: Bool
    let isInstalling: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "opticaldiscdrive")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isSelected ? AppStyle.accent : Color.secondary)
                .frame(width: 42, height: 42)
                .background(Circle().fill((isSelected ? AppStyle.accent : Color.secondary).opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(url.deletingLastPathComponent().path)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected && isInstalling {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(isSelected ? AppStyle.accent.opacity(0.07) : Color.clear)
    }
}

private struct DetailPane: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let selectedDMG = viewModel.selectedDMG {
                SelectedDetail(viewModel: viewModel, url: selectedDMG)
            } else {
                NoSelectionView(viewModel: viewModel)
            }

            Divider()

            LogPanel(lines: viewModel.log)
                .frame(height: 230)
        }
        .background(Color.white)
    }
}

private struct NoSelectionView: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.7))
            Text("未选择 DMG")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.secondary)
            Text("从顶部工具栏选择文件，或直接拖入一个 .dmg 安装包。")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button {
                viewModel.chooseDMG()
            } label: {
                Label("从文件夹选择", systemImage: "folder")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppStyle.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(viewModel.isDropTargeted ? AppStyle.accent.opacity(0.06) : Color.white)
    }
}

private struct SelectedDetail: View {
    @ObservedObject var viewModel: InstallerViewModel
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(2)
                    Text(url.path)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                StatusBadge(phase: viewModel.phase, isInstalling: viewModel.isInstalling)
            }

            StageRail(phase: viewModel.phase, isInstalling: viewModel.isInstalling)

            HStack(spacing: 12) {
                Button {
                    viewModel.installSelected()
                } label: {
                    Label(viewModel.isInstalling ? "安装中" : "开始安装", systemImage: viewModel.isInstalling ? "arrow.triangle.2.circlepath" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(AppStyle.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isInstalling)

                Button {
                    viewModel.clearSelection()
                } label: {
                    Label("清除选择", systemImage: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isInstalling)
            }

            Spacer()
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct StatusBadge: View {
    let phase: String
    let isInstalling: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(phase)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(statusColor.opacity(0.13)))
        .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        if isInstalling { return AppStyle.accent }
        if phase == "安装完成" { return AppStyle.success }
        if phase.contains("失败") || phase == "不支持" { return AppStyle.warning }
        return AppStyle.neutral
    }
}

private struct StageRail: View {
    let phase: String
    let isInstalling: Bool

    private let stages = [
        ("checkmark.shield", "检查"),
        ("externaldrive.badge.plus", "挂载"),
        ("arrow.down.app", "安装"),
        ("eject", "清理")
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                HStack(spacing: 9) {
                    Image(systemName: stage.0)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color(for: index))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(color(for: index).opacity(0.13)))

                    Text(stage.1)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color(for: index))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.035)))
            }
        }
    }

    private func color(for index: Int) -> Color {
        if phase == "安装完成" { return AppStyle.success }
        if phase.contains("失败") || phase == "不支持" { return index == activeIndex ? AppStyle.warning : Color.secondary }
        if isInstalling && index <= activeIndex { return AppStyle.accent }
        return Color.secondary
    }

    private var activeIndex: Int {
        if phase == "正在挂载" || phase == "挂载失败" { return 1 }
        if phase == "安装中" || phase.contains("安装") || phase == "复制失败" { return 2 }
        if phase == "正在清理" { return 3 }
        return 0
    }
}

private struct LogPanel: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("安装日志", systemImage: "terminal")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(lines.count) 行")
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
        .padding(18)
    }
}

private enum AppStyle {
    static let accent = Color(red: 0.08, green: 0.33, blue: 0.92)
    static let success = Color(red: 0.04, green: 0.55, blue: 0.30)
    static let warning = Color(red: 0.84, green: 0.28, blue: 0.16)
    static let neutral = Color(red: 0.48, green: 0.50, blue: 0.54)
    static let windowBackground = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let sidebarBackground = Color(red: 0.93, green: 0.93, blue: 0.92)
    static let toolbarBackground = Color(red: 0.985, green: 0.985, blue: 0.975)
}
