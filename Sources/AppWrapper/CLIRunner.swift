import Foundation

/// 无界面打包：`AppWrapper --cli config.json [--lang zh|en]`
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
        // 先处理 --lang，让后续日志/错误使用该语言
        if let langIndex = arguments.firstIndex(of: "--lang"),
           langIndex + 1 < arguments.count {
            let value = arguments[langIndex + 1].lowercased()
            let language: AppLanguage? = switch value {
            case "zh", "zh-hans", "cn": .zhHans
            case "en", "english": .english
            default: nil
            }
            if let language {
                UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            }
        }

        guard let index = arguments.firstIndex(of: "--cli"),
              index + 1 < arguments.count else {
            FileHandle.standardError.write(Data((L.cliUsage + "\n").utf8))
            return 2
        }

        let configURL = URL(fileURLWithPath: arguments[index + 1])
        let cliConfig: CLIConfig
        do {
            let data = try Data(contentsOf: configURL)
            cliConfig = try JSONDecoder().decode(CLIConfig.self, from: data)
        } catch {
            FileHandle.standardError.write(Data((L.cliConfigFailed(error.localizedDescription) + "\n").utf8))
            return 2
        }

        var script = cliConfig.script ?? ScriptTemplate.make()
        if let scriptFile = cliConfig.scriptFile {
            do {
                script = try String(contentsOf: URL(fileURLWithPath: scriptFile), encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data((L.cliScriptFailed(error.localizedDescription) + "\n").utf8))
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
            print(L.logDone(appURL.path))
            return 0
        } catch {
            FileHandle.standardError.write(Data((L.logFailed(error.localizedDescription) + "\n").utf8))
            return 1
        }
    }
}
