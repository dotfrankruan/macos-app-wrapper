import SwiftUI

/// 程序入口：支持 GUI 模式与 CLI 模式。
/// 用法:
///   AppWrapper                → 打开图形界面
///   AppWrapper --cli config.json [--lang zh|en] → 按 JSON 配置无界面打包（便于自动化/测试）
@main
enum AppWrapperMain {
    static func main() async {
        let args = CommandLine.arguments
        if args.contains("--cli") {
            let code = await CLIRunner.run(arguments: args)
            exit(code)
        }
        AppWrapperApp.main()
    }
}

struct AppWrapperApp: App {
    /// 让窗口标题随语言切换即时更新
    @AppStorage("appLanguage") private var language: AppLanguage = .system

    var body: some Scene {
        WindowGroup(L.windowTitle) {
            ContentView()
                .frame(minWidth: 880, minHeight: 700)
        }
        .defaultSize(width: 1000, height: 820)
        .windowResizability(.contentMinSize)
    }
}
