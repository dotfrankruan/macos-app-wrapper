import Foundation

/// 一个被解析出来的动态库依赖
struct ScannedDependency {
    /// 二进制里记录的原始 install name（可能是 @rpath/... 等形式）
    let installName: String
    /// 在磁盘上解析到的真实路径
    let resolvedURL: URL
    /// 拷贝进 Frameworks 目录后使用的文件名
    let bundledName: String
}

/// 基于 otool 的 Mach-O 动态库依赖扫描器（递归）
enum DependencyScanner {

    /// 判断一个 install name 是否属于系统库（系统库不打包）
    static func isSystemPath(_ name: String) -> Bool {
        name.hasPrefix("/usr/lib/") || name.hasPrefix("/System/")
    }

    /// 运行外部工具并捕获输出
    @discardableResult
    static func runTool(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(data: data, encoding: .utf8) ?? "")
    }

    /// 判断文件是否为 Mach-O（含 fat binary）
    static func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        return [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE,
                0xCAFEBABE, 0xCAFEBABF, 0xBEBAFECA, 0xBFBAFECA].contains(magic)
    }

    /// `otool -L`：列出该文件引用的所有动态库 install name
    static func installNames(of file: URL) -> [String] {
        let (status, out) = runTool("/usr/bin/otool", ["-L", file.path])
        guard status == 0 else { return [] }
        var names: [String] = []
        var seen = Set<String>()
        for (index, line) in out.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if index == 0 || trimmed.isEmpty { continue } // 第一行是 "文件路径:" 头
            guard let range = trimmed.range(of: " (") else { continue }
            let name = String(trimmed[trimmed.startIndex..<range.lowerBound])
            if seen.insert(name).inserted { names.append(name) }
        }
        return names
    }

    /// `otool -D`：取动态库自身的 install id
    static func installID(of file: URL) -> String? {
        let (status, out) = runTool("/usr/bin/otool", ["-D", file.path])
        guard status == 0 else { return nil }
        let lines = out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.count > 1 ? lines[1] : nil
    }

    /// `otool -l`：解析 LC_RPATH，得到 rpath 列表
    static func rpaths(of file: URL) -> [String] {
        let (status, out) = runTool("/usr/bin/otool", ["-l", file.path])
        guard status == 0 else { return [] }
        var result: [String] = []
        let lines = out.components(separatedBy: "\n")
        var expectRpath = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "cmd LC_RPATH" {
                expectRpath = true
            } else if expectRpath, trimmed.hasPrefix("path ") {
                var path = String(trimmed.dropFirst("path ".count))
                if let range = path.range(of: " (offset") {
                    path = String(path[path.startIndex..<range.lowerBound])
                }
                result.append(path)
                expectRpath = false
            }
        }
        return result
    }

    /// 把 @rpath / @loader_path / @executable_path 解析成磁盘上的真实路径
    static func resolve(name: String,
                        referencing: URL,
                        executableDir: URL,
                        rpaths: [String]) -> URL? {
        let loaderDir = referencing.deletingLastPathComponent()
        func expand(_ s: String) -> String {
            s.replacingOccurrences(of: "@loader_path", with: loaderDir.path)
             .replacingOccurrences(of: "@executable_path", with: executableDir.path)
        }
        let fm = FileManager.default
        if name.hasPrefix("@rpath/") {
            let relative = String(name.dropFirst("@rpath/".count))
            for rpath in rpaths {
                let candidate = URL(fileURLWithPath: expand(rpath))
                    .appendingPathComponent(relative).standardizedFileURL
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
            return nil
        }
        let expanded = expand(name)
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    /// 从主可执行文件出发递归扫描全部非系统依赖。
    /// 返回 (找到的依赖列表, 无法解析的 install name 列表)
    static func scan(root: URL,
                     log: (String) -> Void) -> (deps: [ScannedDependency], missing: [String]) {
        let executableDir = root.deletingLastPathComponent()
        let rootRpaths = rpaths(of: root)
        var visited: Set<String> = [root.standardizedFileURL.path]
        var deps: [ScannedDependency] = []
        var missing: [String] = []
        var usedNames: Set<String> = []
        var queue: [URL] = [root]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let names = installNames(of: current)
            let selfID = installID(of: current)
            let combinedRpaths = rpaths(of: current) + rootRpaths

            for name in names {
                if name == selfID { continue }
                if isSystemPath(name) { continue }
                if let resolved = resolve(name: name,
                                          referencing: current,
                                          executableDir: executableDir,
                                          rpaths: combinedRpaths) {
                    let canonical = resolved.resolvingSymlinksInPath().standardizedFileURL.path
                    guard !visited.contains(canonical) else { continue }
                    visited.insert(canonical)

                    // 目标文件名取 install name 的最后一段；重名时加父目录名避免冲突
                    var bundledName = (name as NSString).lastPathComponent
                    if usedNames.contains(bundledName) {
                        let parent = resolved.deletingLastPathComponent().lastPathComponent
                        bundledName = "\(parent)_\(bundledName)"
                    }
                    usedNames.insert(bundledName)

                    deps.append(ScannedDependency(installName: name,
                                                  resolvedURL: resolved,
                                                  bundledName: bundledName))
                    queue.append(resolved)
                } else {
                    let marker = "MISSING:" + name
                    if visited.insert(marker).inserted {
                        missing.append(name)
                        log(L.logUnresolvedDep(name, current.lastPathComponent))
                    }
                }
            }
        }
        return (deps, missing)
    }
}
