import SwiftUI
import AppKit

@MainActor
final class WrapperViewModel: ObservableObject {
    @Published var executablePath: String = ""
    @Published var executableIsMachO: Bool = false
    @Published var additionalItems: [URL] = []
    @Published var appName: String = "MyApp"
    @Published var bundleID: String = "com.example.myapp"
    @Published var version: String = "1.0"
    @Published var iconPath: String = ""
    @Published var script: String = ScriptTemplate.make()
    @Published var copyDependencies: Bool = true
    @Published var fixInstallNames: Bool = true
    @Published var adhocSign: Bool = true
    @Published var outputDirectory: String = NSHomeDirectory() + "/Desktop"
    @Published var log: String = ""
    @Published var isBuilding: Bool = false

    private var appNameCustomized = false

    func appendLog(_ message: String) {
        if !log.isEmpty { log += "\n" }
        log += message
    }

    // MARK: 选择文件

    func pickExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择要打包的可执行文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        executablePath = url.path
        executableIsMachO = DependencyScanner.isMachO(url)
        let baseName = url.deletingPathExtension().lastPathComponent
        if !appNameCustomized || appName == "MyApp" {
            appName = baseName
            bundleID = "com.example.\(baseName.lowercased().filter { $0.isLetter || $0.isNumber })"
            if bundleID == "com.example." { bundleID = "com.example.myapp" }
        }
        if script.contains(ScriptTemplate.tokenQuotedExecutable)
            || script.contains(ScriptTemplate.tokenExecutable)
            || script.contains("your-executable")
            || script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            script = ScriptTemplate.make(executableName: ScriptTemplate.tokenExecutable)
        }
    }

    func pickAdditionalItems(chooseDirectories: Bool) {
        let panel = NSOpenPanel()
        panel.title = chooseDirectories ? "选择文件夹" : "选择文件"
        panel.canChooseFiles = !chooseDirectories
        panel.canChooseDirectories = chooseDirectories
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !additionalItems.contains(url) {
            additionalItems.append(url)
        }
    }

    func removeAdditionalItems(at offsets: IndexSet) {
        additionalItems.remove(atOffsets: offsets)
    }

    func pickIcon() {
        let panel = NSOpenPanel()
        panel.title = "选择图标（.icns 或 .png）"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        iconPath = url.path
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择输出目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectory = url.path
    }

    func noteAppNameEdited() { appNameCustomized = true }

    func resetScript() {
        script = ScriptTemplate.make(executableName: ScriptTemplate.tokenExecutable)
        appendLog("已重置启动脚本为默认模板")
    }

    // MARK: 打包

    func build() {
        guard !isBuilding else { return }
        guard !executablePath.isEmpty else {
            appendLog("❌ 请先选择可执行文件")
            return
        }
        let execURL = URL(fileURLWithPath: executablePath)
        let outDir = URL(fileURLWithPath: outputDirectory)
        let appURL = outDir.appendingPathComponent("\(appName).app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            let alert = NSAlert()
            alert.messageText = "目标已存在"
            alert.informativeText = "\(appURL.path)\n将被删除并重新生成，是否继续？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        isBuilding = true
        appendLog("——— 开始打包 \(appName) ———")

        let config = BuildConfig(
            executableURL: execURL,
            additionalItems: additionalItems,
            appName: appName,
            bundleID: bundleID,
            version: version,
            iconURL: iconPath.isEmpty ? nil : URL(fileURLWithPath: iconPath),
            script: script,
            copyDependencies: copyDependencies,
            fixInstallNames: fixInstallNames,
            adhocSign: adhocSign,
            outputDirectory: outDir
        )

        Task.detached { [weak self] in
            do {
                let appURL = try BundleBuilder.build(config: config) { message in
                    Task { @MainActor in self?.appendLog(message) }
                }
                await MainActor.run {
                    self?.isBuilding = false
                    self?.appendLog("✅ 打包完成: \(appURL.path)")
                    NSWorkspace.shared.activateFileViewerSelecting([appURL])
                }
            } catch {
                await MainActor.run {
                    self?.isBuilding = false
                    self?.appendLog("❌ 打包失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = WrapperViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                executableSection
                additionalFilesSection
                appInfoSection
                scriptSection
                optionsSection
                buildSection
                logSection
            }
            .padding(16)
        }
    }

    // MARK: 可执行文件

    private var executableSection: some View {
        GroupBox("1. 可执行文件") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("选择要打包的可执行文件或脚本", text: $vm.executablePath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { vm.pickExecutable() }
                }
                if !vm.executablePath.isEmpty {
                    Label(vm.executableIsMachO
                          ? "Mach-O 二进制 — 将自动扫描动态库依赖"
                          : "脚本/其他类型 — 跳过依赖扫描（请自行用“附加文件”带上依赖）",
                          systemImage: vm.executableIsMachO ? "checkmark.seal" : "doc.plaintext")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
    }

    // MARK: 附加文件

    private var additionalFilesSection: some View {
        GroupBox("2. 附加文件 / 文件夹（随包拷贝到 Resources/payload）") {
            VStack(alignment: .leading, spacing: 8) {
                if vm.additionalItems.isEmpty {
                    Text("无（如程序运行还需要数据文件、配置、JRE 等，请添加到这里）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(Array(vm.additionalItems.enumerated()), id: \.element) { index, url in
                            HStack {
                                Image(systemName: url.hasDirectoryPath ? "folder" : "doc")
                                Text(url.path).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button(role: .destructive) {
                                    vm.additionalItems.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(minHeight: 60, maxHeight: 120)
                }
                HStack {
                    Button("添加文件…") { vm.pickAdditionalItems(chooseDirectories: false) }
                    Button("添加文件夹…") { vm.pickAdditionalItems(chooseDirectories: true) }
                }
            }
            .padding(6)
        }
    }

    // MARK: App 信息

    private var appInfoSection: some View {
        GroupBox("3. App 信息") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("名称").frame(width: 110, alignment: .trailing)
                    TextField("MyApp", text: $vm.appName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: vm.appName) { vm.noteAppNameEdited() }
                }
                GridRow {
                    Text("Bundle ID").frame(width: 110, alignment: .trailing)
                    TextField("com.example.myapp", text: $vm.bundleID)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("版本").frame(width: 110, alignment: .trailing)
                    TextField("1.0", text: $vm.version)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                }
                GridRow {
                    Text("图标（可选）").frame(width: 110, alignment: .trailing)
                    HStack {
                        TextField(".icns 或 .png", text: $vm.iconPath)
                            .textFieldStyle(.roundedBorder)
                        Button("选择…") { vm.pickIcon() }
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: 启动脚本

    private var scriptSection: some View {
        GroupBox("4. 启动脚本（将成为 Contents/MacOS/ 下的启动器，可自由编写）") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $vm.script)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .border(Color.secondary.opacity(0.3))
                HStack {
                    Text("\(ScriptTemplate.tokenQuotedExecutable) 替换为安全引用的文件名；\(ScriptTemplate.tokenExecutable) 保留原始替换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("重置为模板") { vm.resetScript() }
                }
            }
            .padding(6)
        }
    }

    // MARK: 选项

    private var optionsSection: some View {
        GroupBox("5. 打包选项与输出") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("自动收集并打包动态库依赖（otool 递归扫描）", isOn: $vm.copyDependencies)
                Toggle("改写 install name / rpath 指向包内 Frameworks", isOn: $vm.fixInstallNames)
                    .disabled(!vm.copyDependencies)
                Toggle("完成后进行 ad-hoc 签名（Apple Silicon 建议开启）", isOn: $vm.adhocSign)
                HStack {
                    Text("输出目录").frame(width: 110, alignment: .trailing)
                    TextField("", text: $vm.outputDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { vm.pickOutputDirectory() }
                }
            }
            .padding(6)
        }
    }

    // MARK: 打包按钮

    private var buildSection: some View {
        HStack {
            Spacer()
            if vm.isBuilding { ProgressView().scaleEffect(0.8) }
            Button(vm.isBuilding ? "正在打包…" : "开始打包 .app") { vm.build() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.isBuilding || vm.executablePath.isEmpty)
            Spacer()
        }
    }

    // MARK: 日志

    private var logSection: some View {
        GroupBox("日志") {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(vm.log.isEmpty ? "（打包过程输出会显示在这里）" : vm.log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(vm.log.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .frame(minHeight: 120, maxHeight: 200)
                .onChange(of: vm.log) {
                    withAnimation { proxy.scrollTo("logBottom", anchor: .bottom) }
                }
            }
            .padding(6)
        }
    }
}
