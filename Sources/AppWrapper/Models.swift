import Foundation

/// 打包配置（GUI 与 CLI 共用）
struct BuildConfig {
    var executableURL: URL
    var additionalItems: [URL]
    var appName: String
    var bundleID: String
    var version: String
    var iconURL: URL?
    var script: String
    var copyDependencies: Bool
    var fixInstallNames: Bool
    var adhocSign: Bool
    var outputDirectory: URL
}

/// 启动脚本模板。构建时会把 {{EXECUTABLE_NAME}} / {{APP_NAME}} 替换为真实值。
enum ScriptTemplate {
    static let tokenExecutable = "{{EXECUTABLE_NAME}}"
    static let tokenAppName = "{{APP_NAME}}"

    static func make(executableName: String = ScriptTemplate.tokenExecutable) -> String {
        """
        #!/bin/zsh
        # ============================================================
        #  启动脚本 —— 由 AppWrapper 生成，可自由修改
        #  可用变量:
        #    APP_ROOT       指向 .app 的 Contents 目录
        #    PAYLOAD_DIR    可执行文件与附加资源所在目录
        #    FRAMEWORKS_DIR 自动收集的动态库依赖所在目录
        # ============================================================
        set -e

        APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
        PAYLOAD_DIR="$APP_ROOT/Resources/payload"
        FRAMEWORKS_DIR="$APP_ROOT/Frameworks"

        # 让动态链接器优先找到打包进来的依赖库
        export DYLD_FALLBACK_LIBRARY_PATH="$FRAMEWORKS_DIR${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

        # 如有需要，可在此导出其他环境变量，例如:
        # export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"

        cd "$PAYLOAD_DIR"
        exec "$PAYLOAD_DIR/\(executableName)" "$@"
        """
    }
}

/// 构建过程中可能出现的错误（中文描述）
struct BuildError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
