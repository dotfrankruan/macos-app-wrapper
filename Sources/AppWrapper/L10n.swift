import Foundation
import SwiftUI

/// 应用语言设置：跟随系统 / 中文 / English
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case english

    var id: String { rawValue }

    /// 解析后的实际语言（system 时按系统语言判断）
    static var resolved: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        let setting = AppLanguage(rawValue: raw) ?? .system
        guard setting == .system else { return setting }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .zhHans : .english
    }

    static var isChinese: Bool { resolved == .zhHans }
}

/// 全部 UI / 日志文案。视图内使用方式：
///   @AppStorage("appLanguage") var language: AppLanguage = .system
///   Text(L.choose)
/// @AppStorage 变化会驱动 body 重新求值，从而切换语言。
enum L {
    /// 按当前语言二选一
    private static func pick(_ zh: String, _ en: String) -> String {
        AppLanguage.isChinese ? zh : en
    }

    // MARK: - 窗口与通用

    static var windowTitle: String { pick("AppWrapper — 可执行文件打包工具", "AppWrapper — Executable Packager") }
    static var language: String { pick("语言", "Language") }
    static var followSystem: String { pick("跟随系统", "System") }
    static var choose: String { pick("选择…", "Choose…") }
    static var cancel: String { pick("取消", "Cancel") }
    static var overwrite: String { pick("覆盖", "Overwrite") }

    static func languageName(_ lang: AppLanguage) -> String {
        switch lang {
        case .system: return followSystem
        case .zhHans: return "中文"
        case .english: return "English"
        }
    }

    // MARK: - 1. 可执行文件

    static var sectionExecutable: String { pick("1. 可执行文件", "1. Executable") }
    static var executablePlaceholder: String { pick("选择要打包的可执行文件或脚本", "Choose the executable or script to package") }
    static var machOHint: String { pick("Mach-O 二进制 — 将自动扫描动态库依赖", "Mach-O binary — dynamic library dependencies will be scanned automatically") }
    static var scriptHint: String { pick("脚本/其他类型 — 跳过依赖扫描（请自行用“附加文件”带上依赖）", "Script/other — dependency scanning skipped (use “Additional Files” to bundle what it needs)") }

    // MARK: - 2. 附加文件

    static var sectionAdditional: String { pick("2. 附加文件 / 文件夹（随包拷贝到 Resources/payload）", "2. Additional Files / Folders (copied to Resources/payload)") }
    static var noAdditional: String { pick("无（如程序运行还需要数据文件、配置、JRE 等，请添加到这里）", "None (add data files, configs, a JRE, etc. here if the program needs them at runtime)") }
    static var addFiles: String { pick("添加文件…", "Add Files…") }
    static var addFolder: String { pick("添加文件夹…", "Add Folder…") }
    static var pickFilesTitle: String { pick("选择文件", "Choose Files") }
    static var pickFolderTitle: String { pick("选择文件夹", "Choose Folder") }
    static var pickExecutableTitle: String { pick("选择要打包的可执行文件", "Choose the executable to package") }

    // MARK: - 3. App 信息

    static var sectionAppInfo: String { pick("3. App 信息", "3. App Info") }
    static var fieldName: String { pick("名称", "Name") }
    static var fieldBundleID: String { pick("Bundle ID", "Bundle ID") }
    static var fieldVersion: String { pick("版本", "Version") }
    static var fieldIcon: String { pick("图标（可选）", "Icon (optional)") }
    static var pickIconTitle: String { pick("选择图标（.icns 或 .png）", "Choose an icon (.icns or .png)") }

    // MARK: - 4. 启动脚本

    static var sectionScript: String { pick("4. 启动脚本（将成为 Contents/MacOS/ 下的启动器，可自由编写）", "4. Launch Script (becomes the launcher in Contents/MacOS/, fully editable)") }
    static var placeholderNote: String {
        pick("\(ScriptTemplate.tokenQuotedExecutable) 替换为安全引用的文件名；\(ScriptTemplate.tokenExecutable) 保留原始替换",
             "\(ScriptTemplate.tokenQuotedExecutable) becomes a safely shell-quoted file name; \(ScriptTemplate.tokenExecutable) is replaced verbatim")
    }
    static var resetTemplate: String { pick("重置为模板", "Reset to Template") }
    static var logTemplateReset: String { pick("已重置启动脚本为默认模板", "Launch script reset to the default template") }

    // MARK: - 5. 选项与输出

    static var sectionOptions: String { pick("5. 打包选项与输出", "5. Options & Output") }
    static var toggleDeps: String { pick("自动收集并打包动态库依赖（otool 递归扫描）", "Collect and bundle dynamic library dependencies (recursive otool scan)") }
    static var toggleRewrite: String { pick("改写 install name / rpath 指向包内 Frameworks", "Rewrite install names / rpaths to point at the bundled Frameworks") }
    static var toggleSign: String { pick("完成后进行 ad-hoc 签名（Apple Silicon 建议开启）", "Ad-hoc codesign after packaging (recommended on Apple Silicon)") }
    static var outputDir: String { pick("输出目录", "Output Folder") }
    static var pickOutputTitle: String { pick("选择输出目录", "Choose Output Folder") }

    // MARK: - 打包按钮与弹窗

    static var buildButton: String { pick("开始打包 .app", "Build .app") }
    static var building: String { pick("正在打包…", "Packaging…") }
    static var alertExistsTitle: String { pick("目标已存在", "Target Already Exists") }
    static func alertExistsMessage(_ path: String) -> String {
        pick("\(path)\n将被删除并重新生成，是否继续？", "\(path)\nwill be deleted and regenerated. Continue?")
    }
    static var logNeedExecutable: String { pick("❌ 请先选择可执行文件", "❌ Please choose an executable first") }
    static func logStart(_ name: String) -> String { pick("——— 开始打包 \(name) ———", "——— Packaging \(name) ———") }
    static func logDone(_ path: String) -> String { pick("✅ 打包完成: \(path)", "✅ Done: \(path)") }
    static func logFailed(_ message: String) -> String { pick("❌ 打包失败: \(message)", "❌ Failed: \(message)") }

    // MARK: - 日志区

    static var logTitle: String { pick("日志", "Log") }
    static var logPlaceholder: String { pick("（打包过程输出会显示在这里）", "(build output appears here)") }

    // MARK: - BundleBuilder 日志

    static func logMainFile(_ path: String, isMachO: Bool) -> String {
        let kind = isMachO ? pick("Mach-O 二进制", "Mach-O binary") : pick("脚本/其他", "script/other")
        return pick("主文件: \(path)（\(kind)）", "Main file: \(path) (\(kind))")
    }
    static func logCopiedMain(_ name: String) -> String { pick("已拷贝主文件 → Resources/payload/\(name)", "Copied main file → Resources/payload/\(name)") }
    static func logSymlinkResolved(_ path: String) -> String { pick("主文件是符号链接，已解析为 \(path)", "Main file is a symlink; resolved to \(path)") }
    static func logCopiedAdditional(_ name: String) -> String { pick("已拷贝附加项 → Resources/payload/\(name)", "Copied additional item → Resources/payload/\(name)") }
    static var logScanning: String { pick("正在扫描动态库依赖…", "Scanning dynamic library dependencies…") }
    static var logNoDeps: String { pick("未发现需要打包的非系统依赖", "No non-system dependencies to bundle") }
    static func logCopiedDep(_ installName: String, _ bundled: String) -> String {
        pick("已打包依赖: \(installName) → Frameworks/\(bundled)", "Bundled dependency: \(installName) → Frameworks/\(bundled)")
    }
    static func logMissingDeps(_ count: Int) -> String {
        pick("⚠️ 有 \(count) 个依赖未能解析，运行时可能需要系统自行提供", "⚠️ \(count) dependencies could not be resolved; the system may need to provide them at runtime")
    }
    static var logNotMachOSkip: String { pick("主文件不是 Mach-O 二进制，跳过依赖扫描", "Main file is not a Mach-O binary; skipping dependency scan") }
    static var logRewriting: String { pick("正在改写动态库加载路径…", "Rewriting dynamic library load paths…") }
    static func logScriptWritten(_ name: String) -> String { pick("启动脚本 → MacOS/\(name)", "Launch script → MacOS/\(name)") }
    static var logIconCopied: String { pick("已拷贝图标 AppIcon.icns", "Copied icon AppIcon.icns") }
    static var logIconConverting: String { pick("正在把 PNG 转换为 icns…", "Converting PNG to icns…") }
    static var logIconDone: String { pick("已生成图标 AppIcon.icns", "Generated icon AppIcon.icns") }
    static var logIconUnsupported: String { pick("⚠️ 不支持的图标格式（仅支持 .icns / .png），已忽略", "⚠️ Unsupported icon format (only .icns / .png); ignored") }
    static var logPlistWritten: String { pick("已写入 Info.plist", "Wrote Info.plist") }
    static var logSigning: String { pick("正在进行 ad-hoc 签名…", "Ad-hoc signing…") }
    static var logSignDone: String { pick("签名完成", "Signing complete") }
    static func logSignFailed(_ output: String) -> String {
        pick("⚠️ 签名失败（不影响 bundle 结构，但可能无法直接运行）: \(output)", "⚠️ Signing failed (bundle structure is fine, but it may not run directly): \(output)")
    }
    static func logHeaderpadRetry(_ name: String) -> String {
        pick("⚠️ \(name) 空间不足无法添加 rpath，已仅改写 install name（由启动脚本兜底加载路径）", "⚠️ \(name) has no room for a new rpath; only install names were rewritten (the launch script provides the fallback path)")
    }
    static func logHeaderpadFallback(_ name: String) -> String {
        pick("ℹ️ \(name) 装载命令空间不足，rpath 未添加；将依赖启动脚本的 DYLD_FALLBACK_LIBRARY_PATH 加载包内依赖库", "ℹ️ \(name) has no room for a new rpath; bundled libraries will be found via DYLD_FALLBACK_LIBRARY_PATH from the launch script")
    }
    static func logInstallNameToolWarning(_ name: String, _ output: String) -> String {
        pick("⚠️ install_name_tool 处理 \(name) 时出现警告: \(output)", "⚠️ install_name_tool warning for \(name): \(output)")
    }
    static func logSipsWarning(_ name: String, _ output: String) -> String {
        pick("⚠️ sips 生成 \(name) 失败: \(output)", "⚠️ sips failed to generate \(name): \(output)")
    }
    static func logUnresolvedDep(_ name: String, _ referrer: String) -> String {
        pick("⚠️ 无法解析依赖: \(name)（被 \(referrer) 引用）", "⚠️ Unresolved dependency: \(name) (referenced by \(referrer))")
    }

    // MARK: - BundleBuilder 错误

    static func errExecutableMissing(_ path: String) -> String { pick("可执行文件不存在: \(path)", "Executable not found: \(path)") }
    static var errAppNameEmpty: String { pick("App 名称不能为空", "App name must not be empty") }
    static var errBundleIDEmpty: String { pick("Bundle Identifier 不能为空", "Bundle Identifier must not be empty") }
    static var errAppNameInvalid: String { pick("App 名称不能包含路径分隔符或控制字符", "App name must not contain path separators or control characters") }
    static var errExecutableNotRegularFile: String { pick("主可执行文件必须是普通文件", "The main executable must be a regular file") }
    static func errRestoreFailed(_ backupPath: String, _ message: String) -> String {
        pick("恢复旧产物失败，备份位于 \(backupPath): \(message)", "Failed to restore the previous bundle; backup at \(backupPath): \(message)")
    }
    static func logBackupCleanupFailed(_ path: String) -> String {
        pick("⚠️ 旧产物备份未能删除: \(path)", "⚠️ Could not remove the old backup: \(path)")
    }
    static func errAdditionalMissing(_ path: String) -> String { pick("附加文件不存在: \(path)", "Additional file not found: \(path)") }
    static func errNameConflict(_ name: String) -> String {
        pick("附加文件「\(name)」与主可执行文件重名，请先改名", "Additional item “\(name)” has the same name as the main executable; please rename it first")
    }
    static func errDestConflict(_ name: String) -> String {
        pick("目标已存在同名文件: payload/\(name)，打包中止", "A file named payload/\(name) already exists; aborting")
    }
    static func errIconutil(_ output: String) -> String { pick("iconutil 转换失败: \(output)", "iconutil conversion failed: \(output)") }

    // MARK: - CLI

    static var cliUsage: String { pick("用法: AppWrapper --cli <config.json> [--lang zh|en]", "Usage: AppWrapper --cli <config.json> [--lang zh|en]") }
    static func cliConfigFailed(_ message: String) -> String { pick("❌ 读取配置失败: \(message)", "❌ Failed to read config: \(message)") }
    static func cliScriptFailed(_ message: String) -> String { pick("❌ 读取脚本文件失败: \(message)", "❌ Failed to read script file: \(message)") }

    // MARK: - 启动脚本模板（注释部分）

    static var templateHeader: String {
        pick("""
            # ============================================================
            #  启动脚本 —— 由 AppWrapper 生成，可自由修改
            #  可用变量:
            #    APP_ROOT       指向 .app 的 Contents 目录
            #    PAYLOAD_DIR    可执行文件与附加资源所在目录
            #    FRAMEWORKS_DIR 自动收集的动态库依赖所在目录
            # ============================================================
            """, """
            # ============================================================
            #  Launch script — generated by AppWrapper, edit freely
            #  Available variables:
            #    APP_ROOT       the .app's Contents directory
            #    PAYLOAD_DIR    the executable and bundled resources
            #    FRAMEWORKS_DIR auto-collected dynamic libraries
            # ============================================================
            """)
    }
    static var templateDyldComment: String {
        pick("# 让动态链接器优先找到打包进来的依赖库",
             "# Let dyld find the bundled libraries first")
    }
    static var templateEnvComment: String {
        pick("# 如有需要，可在此导出其他环境变量，例如:",
             "# Export any other environment variables you need, e.g.:")
    }
}
