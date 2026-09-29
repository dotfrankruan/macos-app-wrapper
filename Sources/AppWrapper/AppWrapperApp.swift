import SwiftUI

/// 程序入口：支持 GUI 模式与 CLI 模式。
/// 用法:
///   AppWrapper                → 打开图形界面
///   AppWrapper --cli config.json → 按 JSON 配置无界面打包（便于自动化/测试）
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
    var body: some Scene {
        WindowGroup("AppWrapper — 可执行文件打包工具") {
            ContentView()
                .frame(minWidth: 880, minHeight: 660)
        }
        .defaultSize(width: 1000, height: 780)
        .windowResizability(.contentMinSize)
    }
}
