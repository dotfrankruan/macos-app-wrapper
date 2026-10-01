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

    // MARK: File pickers

    func pickExecutable() {
        let panel = NSOpenPanel()
        panel.title = L.pickExecutableTitle
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
        panel.title = chooseDirectories ? L.pickFolderTitle : L.pickFilesTitle
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
        panel.title = L.pickIconTitle
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        iconPath = url.path
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = L.pickOutputTitle
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
        appendLog(L.logTemplateReset)
    }

    // MARK: Build

    func build() {
        guard !isBuilding else { return }
        guard !executablePath.isEmpty else {
            appendLog(L.logNeedExecutable)
            return
        }
        let execURL = URL(fileURLWithPath: executablePath)
        let outDir = URL(fileURLWithPath: outputDirectory)
        let appURL = outDir.appendingPathComponent("\(appName).app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            let alert = NSAlert()
            alert.messageText = L.alertExistsTitle
            alert.informativeText = L.alertExistsMessage(appURL.path)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L.overwrite)
            alert.addButton(withTitle: L.cancel)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        isBuilding = true
        appendLog(L.logStart(appName))

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
                    self?.appendLog(L.logDone(appURL.path))
                    NSWorkspace.shared.activateFileViewerSelecting([appURL])
                }
            } catch {
                await MainActor.run {
                    self?.isBuilding = false
                    self?.appendLog(L.logFailed(error.localizedDescription))
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = WrapperViewModel()
    /// 驱动界面语言切换；改变后 body 重新求值，所有 L.* 文案即时更新
    @AppStorage("appLanguage") private var language: AppLanguage = .system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                languageBar
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

    // MARK: Language

    private var languageBar: some View {
        HStack {
            Spacer()
            Picker(L.language, selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(L.languageName(lang)).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
    }

    // MARK: Executable

    private var executableSection: some View {
        GroupBox(L.sectionExecutable) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(L.executablePlaceholder, text: $vm.executablePath)
                        .textFieldStyle(.roundedBorder)
                    Button(L.choose) { vm.pickExecutable() }
                }
                if !vm.executablePath.isEmpty {
                    Label(vm.executableIsMachO ? L.machOHint : L.scriptHint,
                          systemImage: vm.executableIsMachO ? "checkmark.seal" : "doc.plaintext")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
    }

    // MARK: Additional files

    private var additionalFilesSection: some View {
        GroupBox(L.sectionAdditional) {
            VStack(alignment: .leading, spacing: 8) {
                if vm.additionalItems.isEmpty {
                    Text(L.noAdditional)
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
                    Button(L.addFiles) { vm.pickAdditionalItems(chooseDirectories: false) }
                    Button(L.addFolder) { vm.pickAdditionalItems(chooseDirectories: true) }
                }
            }
            .padding(6)
        }
    }

    // MARK: App info

    private var appInfoSection: some View {
        GroupBox(L.sectionAppInfo) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(L.fieldName).frame(width: 110, alignment: .trailing)
                    TextField("MyApp", text: $vm.appName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: vm.appName) { vm.noteAppNameEdited() }
                }
                GridRow {
                    Text(L.fieldBundleID).frame(width: 110, alignment: .trailing)
                    TextField("com.example.myapp", text: $vm.bundleID)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L.fieldVersion).frame(width: 110, alignment: .trailing)
                    TextField("1.0", text: $vm.version)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                }
                GridRow {
                    Text(L.fieldIcon).frame(width: 110, alignment: .trailing)
                    HStack {
                        TextField(".icns / .png", text: $vm.iconPath)
                            .textFieldStyle(.roundedBorder)
                        Button(L.choose) { vm.pickIcon() }
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: Launch script

    private var scriptSection: some View {
        GroupBox(L.sectionScript) {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $vm.script)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .border(Color.secondary.opacity(0.3))
                HStack {
                    Text(L.placeholderNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L.resetTemplate) { vm.resetScript() }
                }
            }
            .padding(6)
        }
    }

    // MARK: Options

    private var optionsSection: some View {
        GroupBox(L.sectionOptions) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(L.toggleDeps, isOn: $vm.copyDependencies)
                Toggle(L.toggleRewrite, isOn: $vm.fixInstallNames)
                    .disabled(!vm.copyDependencies)
                Toggle(L.toggleSign, isOn: $vm.adhocSign)
                HStack {
                    Text(L.outputDir).frame(width: 110, alignment: .trailing)
                    TextField("", text: $vm.outputDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button(L.choose) { vm.pickOutputDirectory() }
                }
            }
            .padding(6)
        }
    }

    // MARK: Build button

    private var buildSection: some View {
        HStack {
            Spacer()
            if vm.isBuilding { ProgressView().scaleEffect(0.8) }
            Button(vm.isBuilding ? L.building : L.buildButton) { vm.build() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.isBuilding || vm.executablePath.isEmpty)
            Spacer()
        }
    }

    // MARK: Log

    private var logSection: some View {
        GroupBox(L.logTitle) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(vm.log.isEmpty ? L.logPlaceholder : vm.log)
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
