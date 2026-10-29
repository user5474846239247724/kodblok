import SwiftUI
import AppKit

enum BuildMode { case build, rebuild, clean, compileFile }

extension Workspace {
    static let compilerName = "GNU GCC Compiler"

    private static func mtime(_ u: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
    }

    private static func quote(_ s: String) -> String {
        if s.range(of: "[^A-Za-z0-9_./+=:,@%-]", options: .regularExpression) == nil { return s }
        return "\"" + s + "\""
    }

    private static func duration(_ start: Date) -> String {
        let secs = Int(Date().timeIntervalSince(start))
        return "(\(secs / 60) minute(s), \(secs % 60) second(s))"
    }

    private static let diagRe = try! NSRegularExpression(
        pattern: #"^(.+?):(\d+):(?:(\d+):)? (fatal error|error|warning|note): (.*)$"#)

    private func runTool(_ tool: String, _ args: [String], cwd: URL) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/" + tool)
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return (-1, "Execution of '\(tool)' failed: \(error.localizedDescription)\nIs Xcode (or the Command Line Tools) installed?\n")
        }
        processLock.lock(); buildProcess = p; processLock.unlock()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        processLock.lock(); buildProcess = nil; processLock.unlock()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func stdFlag(isC: Bool, existing: [String]) -> String? {
        if existing.contains(where: { $0.hasPrefix("-std=") }) { return nil }
        let key = isC ? "cStd" : "cxxStd"
        let v = UserDefaults.standard.string(forKey: key) ?? "default"
        return v == "default" ? nil : "-std=" + v
    }

    // MARK: Build

    func build(_ mode: BuildMode = .build, file onlyFile: URL? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !isBuilding else { return }
        saveAll()
        guard let p0 = activeProjectObj else {
            alert("No active project", "Create a new project (File > New > Project...) or open an existing one.")
            completion?(false)
            return
        }
        reloadProject(p0.file)
        let p = projects.first { $0.file == p0.file } ?? p0
        let target = p.targets.contains(self.target) ? self.target : (p.targets.first ?? "Debug")
        let info = CBPFile.targetInfo(p, target)
        let extraWarn = UserDefaults.standard.bool(forKey: "extraWarnings")

        isBuilding = true
        abortRequested = false
        showLogs = true
        logTab = .buildLog
        buildLog = []
        messages = []

        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let fm = FileManager.default
            var errors = 0, warnings = 0
            var failed = false
            var compiled = 0
            var upToDate = false
            func L(_ s: String, _ k: LogKind = .normal) {
                DispatchQueue.main.async { self.buildLog.append(LogLine(text: s, kind: k)) }
            }
            func M(_ m: BuildMessage) {
                DispatchQueue.main.async { self.messages.append(m) }
            }
            func handleOutput(_ out: String) {
                for line in out.components(separatedBy: "\n") where !line.isEmpty {
                    let ns = line as NSString
                    if let m = Self.diagRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                        let path = ns.substring(with: m.range(at: 1))
                        let lineNo = Int(ns.substring(with: m.range(at: 2)))
                        var kind = ns.substring(with: m.range(at: 4))
                        if kind == "fatal error" { kind = "error" }
                        let msg = ns.substring(with: m.range(at: 5))
                        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : p.dir.appendingPathComponent(path).standardizedFileURL
                        let display = p.rel(url)
                        switch kind {
                        case "error":
                            errors += 1
                            L(line, .error)
                            M(BuildMessage(file: display, fileURL: url, line: lineNo, text: "error: " + msg, kind: .error))
                        case "warning":
                            warnings += 1
                            L(line, .warning)
                            M(BuildMessage(file: display, fileURL: url, line: lineNo, text: "warning: " + msg, kind: .warning))
                        default:
                            L(line, .normal)
                            M(BuildMessage(file: display, fileURL: url, line: lineNo, text: "note: " + msg, kind: .note))
                        }
                    } else if line.hasPrefix("ld: ") || line.hasPrefix("clang: error") || line.hasPrefix("Undefined symbols") {
                        let isErr = !line.contains("warning")
                        if isErr { errors += 1 } else { warnings += 1 }
                        L(line, isErr ? .error : .warning)
                        M(BuildMessage(file: "", fileURL: nil, line: nil, text: line, kind: isErr ? .error : .warning))
                    } else if line.range(of: #"^\s*\d*\s*\|"#, options: .regularExpression) != nil
                                || line.trimmingCharacters(in: .whitespaces).hasPrefix("^")
                                || line.hasSuffix("generated.") {
                        // isečak koda sa ^ ispod greške i zbirni red — samo u Build log
                        L(line, .normal)
                    } else if line.hasPrefix("  \"") || line.hasPrefix("      ") {
                        L(line, .normal)
                        M(BuildMessage(file: "", fileURL: nil, line: nil, text: line.trimmingCharacters(in: .whitespaces), kind: .note))
                    } else {
                        L(line, .normal)
                    }
                }
            }

            // Clean
            if mode == .clean || mode == .rebuild {
                L("-------------- Clean: \(target) in \(p.title) (compiler: \(Self.compilerName))---------------", .header)
                L("")
                try? fm.removeItem(at: p.dir.appendingPathComponent(info.objDir))
                try? fm.removeItem(at: p.dir.appendingPathComponent(info.output))
                L("Cleaned \"\(p.title) - \(target)\"")
                L("")
                if mode == .clean {
                    L("Done.", .success)
                    L("")
                    DispatchQueue.main.async {
                        self.isBuilding = false
                        completion?(true)
                    }
                    return
                }
            }

            L("-------------- Build: \(target) in \(p.title) (compiler: \(Self.compilerName))---------------", .header)
            L("")
            M(BuildMessage(file: "", fileURL: nil, line: nil, text: "=== Build: \(target) in \(p.title) (compiler: \(Self.compilerName)) ===", kind: .header))

            let allSources = p.sources
            if allSources.isEmpty {
                L("No source files in project \"\(p.title)\". Nothing to be done.", .warning)
            }
            let useCxx = allSources.contains { $0.pathExtension.lowercased() != "c" }
            let newestHeader = p.headers.compactMap { Self.mtime($0) }.max() ?? .distantPast
            let cbpTime = Self.mtime(p.file) ?? .distantPast
            func objRel(_ src: URL) -> String {
                let r = p.rel(src)
                let base = r.hasPrefix("/") ? src.lastPathComponent : r
                return info.objDir + (base as NSString).deletingPathExtension + ".o"
            }

            let toCompile = onlyFile.map { [$0.standardizedFileURL] } ?? allSources
            for src in toCompile {
                if self.abortRequested { failed = true; break }
                let o = objRel(src)
                let objURL = p.dir.appendingPathComponent(o)
                let objTime = Self.mtime(objURL)
                let srcTime = Self.mtime(src) ?? .distantFuture
                let needs = mode == .compileFile || mode == .rebuild || objTime == nil
                    || srcTime > objTime! || newestHeader > objTime! || cbpTime > objTime!
                if !needs { continue }
                try? fm.createDirectory(at: objURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let isC = src.pathExtension.lowercased() == "c"
                let tool = isC ? "gcc" : "g++"
                var args = info.cflags
                if extraWarn { args.append("-Wextra") }
                if let s = self.stdFlag(isC: isC, existing: args) { args.append(s) }
                args += ["-c", src.path, "-o", o]
                L(([tool] + args).map(Self.quote).joined(separator: " "), .command)
                let (status, out) = self.runTool(tool, args, cwd: p.dir)
                handleOutput(out)
                compiled += 1
                if status != 0 { failed = true; break }
            }

            if !failed && onlyFile == nil && !allSources.isEmpty {
                let outURL = p.dir.appendingPathComponent(info.output)
                let objs = allSources.map { objRel($0) }
                let newestObj = objs.compactMap { Self.mtime(p.dir.appendingPathComponent($0)) }.max() ?? .distantFuture
                let outTime = Self.mtime(outURL)
                if compiled > 0 || outTime == nil || newestObj > outTime! {
                    try? fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let tool = useCxx ? "g++" : "gcc"
                    let args = ["-o", info.output] + objs + info.ldflags
                    L(([tool] + args).map(Self.quote).joined(separator: " "), .command)
                    let (status, out) = self.runTool(tool, args, cwd: p.dir)
                    handleOutput(out)
                    if status != 0 {
                        failed = true
                    } else {
                        let size = ((try? fm.attributesOfItem(atPath: outURL.path))?[.size] as? NSNumber)?.doubleValue ?? 0
                        L(String(format: "Output file is %@ with size %.2f KB", info.output, size / 1024))
                    }
                } else {
                    upToDate = true
                    L("Target is up to date.")
                    L("Nothing to be done (all items are up-to-date).")
                }
            }

            if failed && errors == 0 && !self.abortRequested { errors = 1 }
            let dur = Self.duration(start)
            if self.abortRequested {
                L("Build aborted by user.", .failure)
            }
            if !upToDate || failed {
                L("Process terminated with status \(failed ? 1 : 0) \(dur)", failed ? .failure : .success)
                L("\(errors) error(s), \(warnings) warning(s) \(dur)", failed ? .failure : .success)
            }
            L("")
            L("")
            M(BuildMessage(file: "", fileURL: nil, line: nil,
                           text: failed ? "=== Build failed: \(errors) error(s), \(warnings) warning(s) \(dur) ==="
                                        : "=== Build finished: \(errors) error(s), \(warnings) warning(s) \(dur) ===",
                           kind: failed ? .footerFail : .footerOK))
            DispatchQueue.main.async {
                self.isBuilding = false
                if failed && errors > 0 { self.logTab = .messages }
                completion?(!failed)
            }
        }
    }

    func compileCurrentFile() {
        guard let d = currentDocument, Ext.isSource(d.url) else { return }
        if let p = project(containing: d.url) { activeProject = p.file }
        build(.compileFile, file: d.url)
    }

    // MARK: Run

    func executable(for p: CBProject) -> URL {
        let target = p.targets.contains(self.target) ? self.target : (p.targets.first ?? "Debug")
        return p.dir.appendingPathComponent(CBPFile.targetInfo(p, target).output)
    }

    private func isOutOfDate(_ p: CBProject, _ exe: URL) -> Bool {
        guard let exeTime = Self.mtime(exe) else { return true }
        let newest = (p.units.compactMap { Self.mtime($0) } + [Self.mtime(p.file)].compactMap { $0 }).max() ?? .distantPast
        if newest > exeTime { return true }
        return openDocs.contains { $0.dirty && p.contains($0.url) }
    }

    func run() {
        guard !isBuilding else { return }
        guard let p = activeProjectObj else {
            alert("No active project", "Create a new project (File > New > Project...) or open an existing one.")
            return
        }
        let exe = executable(for: p)
        if !FileManager.default.isExecutableFile(atPath: exe.path) {
            let a = NSAlert()
            a.messageText = "It seems that this project has not been built yet.\nDo you want to build it now?"
            a.addButton(withTitle: "Yes")
            a.addButton(withTitle: "No")
            a.addButton(withTitle: "Cancel")
            if a.runModal() == .alertFirstButtonReturn { buildAndRun() }
            return
        }
        if isOutOfDate(p, exe) {
            let a = NSAlert()
            a.messageText = "It seems that this project has been modified since it was last built.\nDo you want to build it now?"
            a.addButton(withTitle: "Yes")
            a.addButton(withTitle: "No")
            a.addButton(withTitle: "Cancel")
            let r = a.runModal()
            if r == .alertFirstButtonReturn { buildAndRun(); return }
            if r == .alertThirdButtonReturn { return }
        }
        launch(p, exe)
    }

    func buildAndRun() {
        build { ok in
            guard ok, let p = self.activeProjectObj else { return }
            self.launch(p, self.executable(for: p))
        }
    }

    func launch(_ p: CBProject, _ exe: URL) {
        let target = p.targets.contains(self.target) ? self.target : (p.targets.first ?? "Debug")
        buildLog.append(LogLine(text: "-------------- Run: \(target) in \(p.title) (compiler: \(Self.compilerName))---------------", kind: .header))
        buildLog.append(LogLine(text: "", kind: .normal))
        buildLog.append(LogLine(text: "Checking for existence: \(exe.path)", kind: .normal))
        buildLog.append(LogLine(text: "Executing: '\(exe.path)'  (in '\(p.dir.path)/.')", kind: .normal))

        let c = ConsoleWindowController(executable: exe, cwd: p.dir)
        c.onExit = { [weak self] code, secs in
            guard let self else { return }
            let s = Int(secs)
            self.buildLog.append(LogLine(text: "Process terminated with status \(code) (\(s / 60) minute(s), \(s % 60) second(s))", kind: .success))
            self.buildLog.append(LogLine(text: "", kind: .normal))
            self.updateRunning()
        }
        c.onClose = { [weak self, weak c] in
            guard let self else { return }
            self.consoles.removeAll { $0 === c }
            self.updateRunning()
        }
        consoles.append(c)
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        c.start()
        updateRunning()
    }

    func updateRunning() {
        runningCount = consoles.filter { $0.isRunning }.count
    }

    func abort() {
        if isBuilding {
            abortRequested = true
            processLock.lock()
            buildProcess?.terminate()
            processLock.unlock()
        }
        for c in consoles where c.isRunning { c.kill() }
    }

    func killAll() {
        for c in consoles { c.kill() }
    }
}
