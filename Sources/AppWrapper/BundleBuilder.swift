import Foundation

/// 负责把可执行文件 + 依赖 + 启动脚本组装成 .app bundle
enum BundleBuilder {

    /// 执行打包。成功返回生成的 .app 路径。
    /// - Parameter log: 进度日志回调（可能在后台线程被调用）
    static func build(config: BuildConfig,
                      log: @escaping @Sendable (String) -> Void) throws -> URL {
        let fm = FileManager.default

        // ---------- 0. 校验输入 ----------
        let execURL = config.executableURL
        guard fm.fileExists(atPath: execURL.path) else {
            throw BuildError("可执行文件不存在: \(execURL.path)")
        }
        let appName = config.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else { throw BuildError("App 名称不能为空") }
        guard !config.bundleID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw BuildError("Bundle Identifier 不能为空")
        }
        for item in config.additionalItems {
            guard fm.fileExists(atPath: item.path) else {
                throw BuildError("附加文件不存在: \(item.path)")
            }
            if item.lastPathComponent == execURL.lastPathComponent {
                throw BuildError("附加文件「\(item.lastPathComponent)」与主可执行文件重名，请先改名")
            }
        }

        let execName = execURL.lastPathComponent
        let isMachO = DependencyScanner.isMachO(execURL)
        log("主文件: \(execURL.path)（\(isMachO ? "Mach-O 二进制" : "脚本/其他")）")

        // ---------- 1. 创建 bundle 目录结构 ----------
        let appURL = config.outputDirectory.appendingPathComponent("\(appName).app")
        if fm.fileExists(atPath: appURL.path) {
            log("删除已存在的 \(appURL.lastPathComponent)")
            try fm.removeItem(at: appURL)
        }
        let contentsURL = appURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        let payloadURL = resourcesURL.appendingPathComponent("payload")
        let frameworksURL = contentsURL.appendingPathComponent("Frameworks")
        try fm.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: payloadURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: frameworksURL, withIntermediateDirectories: true)

        // ---------- 2. 拷贝主可执行文件与附加文件 ----------
        // 注意：主文件可能是符号链接（如 /opt/homebrew/bin/*），必须解析后拷贝真实文件
        let resolvedExecURL = execURL.resolvingSymlinksInPath()
        let payloadExecURL = payloadURL.appendingPathComponent(execName)
        try fm.copyItem(at: resolvedExecURL, to: payloadExecURL)
        makeExecutable(payloadExecURL)
        if resolvedExecURL != execURL {
            log("主文件是符号链接，已解析为 \(resolvedExecURL.path)")
        }
        log("已拷贝主文件 → Resources/payload/\(execName)")

        for item in config.additionalItems {
            let dest = payloadURL.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                throw BuildError("目标已存在同名文件: payload/\(item.lastPathComponent)，打包中止")
            }
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDirectory)
            let source = isDirectory.boolValue ? item : item.resolvingSymlinksInPath()
            try fm.copyItem(at: source, to: dest)
            log("已拷贝附加项 → Resources/payload/\(item.lastPathComponent)")
        }

        // ---------- 3. 扫描并拷贝动态库依赖 ----------
        var bundledDeps: [ScannedDependency] = []
        if config.copyDependencies {
            if isMachO {
                log("正在扫描动态库依赖…")
                // 注意：必须扫描原始位置的文件，这样 @rpath/@executable_path 才能解析到依赖的真实位置
                let (deps, missing) = DependencyScanner.scan(root: execURL, log: log)
                bundledDeps = deps
                if deps.isEmpty {
                    log("未发现需要打包的非系统依赖")
                }
                for dep in deps {
                    let dest = frameworksURL.appendingPathComponent(dep.bundledName)
                    let source = dep.resolvedURL.resolvingSymlinksInPath()
                    try fm.copyItem(at: source, to: dest)
                    makeExecutable(dest)
                    log("已打包依赖: \(dep.installName) → Frameworks/\(dep.bundledName)")
                }
                if !missing.isEmpty {
                    log("⚠️ 有 \(missing.count) 个依赖未能解析，运行时可能需要系统自行提供")
                }
            } else {
                log("主文件不是 Mach-O 二进制，跳过依赖扫描")
            }
        }

        // ---------- 4. 改写 install name / rpath ----------
        if config.fixInstallNames, !bundledDeps.isEmpty {
            log("正在改写动态库加载路径…")
            let changes = bundledDeps.map {
                (old: $0.installName, new: "@rpath/\($0.bundledName)")
            }
            // payload 位于 Contents/Resources/payload，Frameworks 位于 Contents/Frameworks
            let payloadRpaths = ["@executable_path/../../Frameworks",
                                 "@loader_path/../../Frameworks"]
            rewrite(binary: payloadExecURL, id: nil,
                    changes: changes, addRpaths: payloadRpaths, log: log)
            for dep in bundledDeps {
                let dylibURL = frameworksURL.appendingPathComponent(dep.bundledName)
                rewrite(binary: dylibURL, id: "@rpath/\(dep.bundledName)",
                        changes: changes, addRpaths: ["@loader_path"], log: log)
            }
        }

        // ---------- 5. 生成启动脚本 ----------
        let launcherName = sanitizedLauncherName(from: appName)
        var script = config.script
        if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            script = ScriptTemplate.make(executableName: execName)
        }
        script = script
            .replacingOccurrences(of: ScriptTemplate.tokenExecutable, with: execName)
            .replacingOccurrences(of: ScriptTemplate.tokenAppName, with: appName)
        if !script.hasPrefix("#!") {
            script = "#!/bin/zsh\n" + script
        }
        let launcherURL = macosURL.appendingPathComponent(launcherName)
        try script.write(to: launcherURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
        log("启动脚本 → MacOS/\(launcherName)")

        // ---------- 6. 图标（可选） ----------
        var iconFileName: String? = nil
        if let iconURL = config.iconURL {
            let iconDest = resourcesURL.appendingPathComponent("AppIcon.icns")
            if iconURL.pathExtension.lowercased() == "icns" {
                try fm.copyItem(at: iconURL, to: iconDest)
                iconFileName = "AppIcon"
                log("已拷贝图标 AppIcon.icns")
            } else if ["png"].contains(iconURL.pathExtension.lowercased()) {
                log("正在把 PNG 转换为 icns…")
                try convertPNGToICNS(png: iconURL, icns: iconDest, log: log)
                iconFileName = "AppIcon"
                log("已生成图标 AppIcon.icns")
            } else {
                log("⚠️ 不支持的图标格式（仅支持 .icns / .png），已忽略")
            }
        }

        // ---------- 7. Info.plist ----------
        var plist: [String: Any] = [
            "CFBundleName": appName,
            "CFBundleDisplayName": appName,
            "CFBundleIdentifier": config.bundleID,
            "CFBundleVersion": config.version,
            "CFBundleShortVersionString": config.version,
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": launcherName,
            "NSHighResolutionCapable": true,
            "LSMinimumSystemVersion": "12.0",
        ]
        if let iconFileName { plist["CFBundleIconFile"] = iconFileName }
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        log("已写入 Info.plist")

        // ---------- 8. 签名 ----------
        // 改过 install name 的 Mach-O 在 Apple Silicon 上必须重新（至少 ad-hoc）签名
        if config.adhocSign {
            log("正在进行 ad-hoc 签名…")
            for dep in bundledDeps {
                let dylibURL = frameworksURL.appendingPathComponent(dep.bundledName)
                _ = DependencyScanner.runTool("/usr/bin/codesign",
                                              ["--force", "--sign", "-", dylibURL.path])
            }
            if isMachO {
                _ = DependencyScanner.runTool("/usr/bin/codesign",
                                              ["--force", "--sign", "-", payloadExecURL.path])
            }
            let (status, out) = DependencyScanner.runTool(
                "/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appURL.path])
            if status == 0 {
                log("签名完成")
            } else {
                log("⚠️ 签名失败（不影响 bundle 结构，但可能无法直接运行）: \(out)")
            }
        }

        return appURL
    }

    // MARK: - 辅助

    private static func makeExecutable(_ url: URL) {
        let fm = FileManager.default
        let path = url.path
        let current = (try? fm.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        try? fm.setAttributes([.posixPermissions: NSNumber(value: current | 0o111)],
                              ofItemAtPath: path)
    }

    /// CFBundleExecutable 只允许 ASCII 安全字符；不满足时回退为 "launcher"
    static func sanitizedLauncherName(from appName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = String(appName.unicodeScalars.filter { allowed.contains($0) })
        return filtered.isEmpty ? "launcher" : filtered
    }

    private static func rewrite(binary: URL,
                                id: String?,
                                changes: [(old: String, new: String)],
                                addRpaths: [String],
                                log: @escaping @Sendable (String) -> Void) {
        var args: [String] = []
        if let id { args += ["-id", id] }
        for change in changes { args += ["-change", change.old, change.new] }
        let existing = DependencyScanner.rpaths(of: binary)
        for rpath in addRpaths where !existing.contains(rpath) {
            args += ["-add_rpath", rpath]
        }
        guard !args.isEmpty else { return }
        args.append(binary.path)
        var (status, out) = DependencyScanner.runTool("/usr/bin/install_name_tool", args)
        if status != 0, addRpaths.count > 0 {
            // 常见于未使用 -headerpad 链接的二进制：装载命令空间不足。
            // 退化为只改写 -change/-id，rpath 由启动脚本里的
            // DYLD_FALLBACK_LIBRARY_PATH 兜底。
            var retryArgs: [String] = []
            if let id { retryArgs += ["-id", id] }
            for change in changes where change.old != change.new {
                retryArgs += ["-change", change.old, change.new]
            }
            if !retryArgs.isEmpty {
                retryArgs.append(binary.path)
                (status, out) = DependencyScanner.runTool("/usr/bin/install_name_tool", retryArgs)
                if status == 0 {
                    log("⚠️ \(binary.lastPathComponent) 空间不足无法添加 rpath，已仅改写 install name（由启动脚本兜底加载路径）")
                    return
                }
            } else {
                log("ℹ️ \(binary.lastPathComponent) 装载命令空间不足，rpath 未添加；将依赖启动脚本的 DYLD_FALLBACK_LIBRARY_PATH 加载包内依赖库")
                return
            }
        }
        if status != 0 {
            log("⚠️ install_name_tool 处理 \(binary.lastPathComponent) 时出现警告: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// 用 sips + iconutil 把 PNG 转成 icns
    private static func convertPNGToICNS(png: URL, icns: URL,
                                         log: @escaping @Sendable (String) -> Void) throws {
        let fm = FileManager.default
        let iconsetURL = fm.temporaryDirectory
            .appendingPathComponent("AppWrapper-\(UUID().uuidString).iconset")
        try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconsetURL) }

        // (文件名, 像素尺寸)
        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ]
        for (name, pixels) in sizes {
            let dest = iconsetURL.appendingPathComponent(name)
            let (status, out) = DependencyScanner.runTool(
                "/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", png.path, "--out", dest.path])
            if status != 0 {
                log("⚠️ sips 生成 \(name) 失败: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        let (status, out) = DependencyScanner.runTool(
            "/usr/bin/iconutil", ["-c", "icns", iconsetURL.path, "-o", icns.path])
        guard status == 0 else {
            throw BuildError("iconutil 转换失败: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
