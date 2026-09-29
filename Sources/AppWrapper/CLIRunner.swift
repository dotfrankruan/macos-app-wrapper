import Foundation

/// 无界面打包：`AppWrapper --cli config.json`
/// 方便自动化测试与脚本调用。config.json 示例见 README。
enum CLIRunner {

    private struct CLIConfig: Decodable {
        var executable: String
        var additionalItems: [String]?
        var appName: String
        var bundleID: String?
        var version: String?
        var icon: String?
        var script: String?
        var scriptFile: String?
        var copyDependencies: Bool?
        var fixInstallNames: Bool?
        var adhocSign: Bool?
        var outputDirectory: String?
    }

    static func run(arguments: [String]) async -> Int32 {
        guard let index = arguments.firstIndex(of: "--cli"),
              index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("用法: AppWrapper --cli <config.json>\n".utf8))
            return 2
        }

        let configURL = URL(fileURLWithPath: arguments[index + 1])
        let cliConfig: CLIConfig
        do {
            let data = try Data(contentsOf: configURL)
            cliConfig = try JSONDecoder().decode(CLIConfig.self, from: data)
        } catch {
            FileHandle.standardError.write(Data("❌ 读取配置失败: \(error.localizedDescription)\n".utf8))
            return 2
        }

        var script = cliConfig.script ?? ScriptTemplate.make()
        if let scriptFile = cliConfig.scriptFile {
            do {
                script = try String(contentsOf: URL(fileURLWithPath: scriptFile), encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("❌ 读取脚本文件失败: \(error.localizedDescription)\n".utf8))
                return 2
            }
        }

        let config = BuildConfig(
            executableURL: URL(fileURLWithPath: cliConfig.executable),
            additionalItems: (cliConfig.additionalItems ?? []).map { URL(fileURLWithPath: $0) },
            appName: cliConfig.appName,
            bundleID: cliConfig.bundleID ?? "com.example.\(cliConfig.appName.lowercased())",
            version: cliConfig.version ?? "1.0",
            iconURL: cliConfig.icon.map { URL(fileURLWithPath: $0) },
            script: script,
            copyDependencies: cliConfig.copyDependencies ?? true,
            fixInstallNames: cliConfig.fixInstallNames ?? true,
            adhocSign: cliConfig.adhocSign ?? true,
            outputDirectory: URL(fileURLWithPath: cliConfig.outputDirectory ?? FileManager.default.currentDirectoryPath)
        )

        do {
            let appURL = try BundleBuilder.build(config: config) { print($0) }
            print("✅ 打包完成: \(appURL.path)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("❌ 打包失败: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
