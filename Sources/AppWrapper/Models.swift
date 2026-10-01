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
    static let tokenQuotedExecutable = "{{SHELL_EXECUTABLE_NAME}}"

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static let tokenAppName = "{{APP_NAME}}"

    static func make(executableName: String = ScriptTemplate.tokenExecutable) -> String {
        let name = executableName == tokenExecutable ? tokenQuotedExecutable : shellQuote(executableName)
        return """
        #!/bin/zsh
        \(L.templateHeader)
        set -e

        APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
        PAYLOAD_DIR="$APP_ROOT/Resources/payload"
        FRAMEWORKS_DIR="$APP_ROOT/Frameworks"

        \(L.templateDyldComment)
        export DYLD_FALLBACK_LIBRARY_PATH="$FRAMEWORKS_DIR${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

        \(L.templateEnvComment)
        # export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"

        cd "$PAYLOAD_DIR"
        exec "$PAYLOAD_DIR/"\(name) "$@"
        """
    }
}

/// 构建过程中可能出现的错误（中文描述）
struct BuildError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
