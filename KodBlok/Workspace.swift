import SwiftUI
import AppKit

// MARK: - Modeli

enum Ext {
    static let sources: Set<String> = ["c", "cpp", "cc", "cxx", "c++"]
    static let headers: Set<String> = ["h", "hpp", "hh", "hxx", "h++"]
    static func isSource(_ u: URL) -> Bool { sources.contains(u.pathExtension.lowercased()) }
    static func isHeader(_ u: URL) -> Bool { headers.contains(u.pathExtension.lowercased()) }
}

struct CBProject: Identifiable, Equatable {
    var file: URL
    var title: String
    var units: [URL]
    var targets: [String]
    var id: URL { file }
    var dir: URL { file.deletingLastPathComponent() }
    var sources: [URL] { units.filter { Ext.isSource($0) } }
    var headers: [URL] { units.filter { Ext.isHeader($0) } }
    var others: [URL] { units.filter { !Ext.isSource($0) && !Ext.isHeader($0) } }

    func rel(_ u: URL) -> String {
        let d = dir.standardizedFileURL.path + "/"
        let p = u.standardizedFileURL.path
        return p.hasPrefix(d) ? String(p.dropFirst(d.count)) : p
    }

    func contains(_ u: URL) -> Bool {
        units.contains { $0.standardizedFileURL.path == u.standardizedFileURL.path }
    }
}

struct TargetInfo {
    var output: String
    var objDir: String
    var cflags: [String]
    var ldflags: [String]
}

final class OpenDocument: ObservableObject, Identifiable {
    let url: URL
    @Published var text: String
    @Published var dirty = false
    let eol: String
    var id: URL { url }
    var name: String { url.lastPathComponent }

    init(url: URL, text: String) {
        self.url = url
        self.eol = text.contains("\r\n") ? "Windows (CR+LF)" : "Unix (LF)"
        self.text = text.replacingOccurrences(of: "\r\n", with: "\n")
    }
}

enum LogKind { case normal, command, error, warning, success, header, failure }

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
    let kind: LogKind
}

struct BuildMessage: Identifiable {
    enum Kind { case header, error, warning, note, info, footerOK, footerFail }
    let id = UUID()
    let file: String
    let fileURL: URL?
    let line: Int?
    let text: String
    let kind: Kind
}

struct SearchResult: Identifiable {
    let id = UUID()
    let file: URL
    let display: String
    let line: Int
    let text: String
}

struct SymbolInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let signature: String
    let line: Int
}

struct JumpRequest: Equatable {
    let url: URL
    let line: Int
    let token = UUID()
}

struct CaretInfo: Equatable {
    var line = 1
    var col = 1
    var pos = 0
}

enum LogTab: String, CaseIterable, Identifiable {
    case app = "KodBlok"
    case search = "Search results"
    case buildLog = "Build log"
    case messages = "Build messages"
    case debugger = "Debugger"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .app: return "info.circle"
        case .search: return "magnifyingglass"
        case .buildLog: return "gearshape"
        case .messages: return "exclamationmark.bubble"
        case .debugger: return "ladybug"
        }
    }
}

enum MgmtTab: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case files = "Files"
    case symbols = "FSymbols"
    var id: String { rawValue }
}

enum EditorTab: Hashable {
    case start
    case file(URL)
}

// MARK: - .cbp fajlovi (Code::Blocks format projekta)

enum CBPFile {
    static func xmlEsc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func load(_ url: URL) -> CBProject? {
        guard let doc = try? XMLDocument(contentsOf: url, options: []) else { return nil }
        let dir = url.deletingLastPathComponent()
        var title = url.deletingPathExtension().lastPathComponent
        for case let e as XMLElement in (try? doc.nodes(forXPath: "/CodeBlocks_project_file/Project/Option")) ?? [] {
            if let t = e.attribute(forName: "title")?.stringValue { title = t }
        }
        let units: [URL] = ((try? doc.nodes(forXPath: "/CodeBlocks_project_file/Project/Unit")) ?? [])
            .compactMap { ($0 as? XMLElement)?.attribute(forName: "filename")?.stringValue }
            .map { f in
                let f2 = f.replacingOccurrences(of: "\\", with: "/")
                return f2.hasPrefix("/") ? URL(fileURLWithPath: f2) : dir.appendingPathComponent(f2).standardizedFileURL
            }
        let targets: [String] = ((try? doc.nodes(forXPath: "/CodeBlocks_project_file/Project/Build/Target")) ?? [])
            .compactMap { ($0 as? XMLElement)?.attribute(forName: "title")?.stringValue }
        return CBProject(file: url.standardizedFileURL, title: title, units: units,
                         targets: targets.isEmpty ? ["Debug", "Release"] : targets)
    }

    private static func attrs(_ doc: XMLDocument, _ xpath: String, _ name: String) -> [String] {
        ((try? doc.nodes(forXPath: xpath)) ?? []).compactMap { ($0 as? XMLElement)?.attribute(forName: name)?.stringValue }
    }

    static func targetInfo(_ p: CBProject, _ target: String) -> TargetInfo {
        var info = TargetInfo(output: "bin/\(target)/\(p.title)", objDir: "obj/\(target)/", cflags: [], ldflags: [])
        guard let doc = try? XMLDocument(contentsOf: p.file, options: []) else {
            info.cflags = ["-Wall", "-fexceptions", target == "Release" ? "-O2" : "-g"]
            return info
        }
        let base = "/CodeBlocks_project_file/Project"
        let t = "\(base)/Build/Target[@title='\(target)']"
        for case let e as XMLElement in (try? doc.nodes(forXPath: "\(t)/Option")) ?? [] {
            if let o = e.attribute(forName: "output")?.stringValue { info.output = o.replacingOccurrences(of: "\\", with: "/") }
            if let o = e.attribute(forName: "object_output")?.stringValue {
                var od = o.replacingOccurrences(of: "\\", with: "/")
                if !od.hasSuffix("/") { od += "/" }
                info.objDir = od
            }
        }
        if info.output.lowercased().hasSuffix(".exe") { info.output = String(info.output.dropLast(4)) }
        info.cflags = attrs(doc, "\(t)/Compiler/Add", "option") + attrs(doc, "\(base)/Compiler/Add", "option")
        info.cflags += (attrs(doc, "\(t)/Compiler/Add", "directory") + attrs(doc, "\(base)/Compiler/Add", "directory")).map { "-I\($0)" }
        info.ldflags = (attrs(doc, "\(t)/Linker/Add", "option") + attrs(doc, "\(base)/Linker/Add", "option")).filter { $0 != "-s" }
        info.ldflags += (attrs(doc, "\(t)/Linker/Add", "directory") + attrs(doc, "\(base)/Linker/Add", "directory")).map { "-L\($0)" }
        info.ldflags += (attrs(doc, "\(t)/Linker/Add", "library") + attrs(doc, "\(base)/Linker/Add", "library")).map { $0.hasPrefix("-") ? $0 : "-l\($0)" }
        // Windows-specifične opcije koje clang na Mac-u ne razume
        let unsupported: Set<String> = ["-mwindows", "-mconsole", "-static-libgcc", "-static-libstdc++", "-static"]
        info.cflags.removeAll { unsupported.contains($0) }
        info.ldflags.removeAll { unsupported.contains($0) }
        return info
    }

    private static func targetXML(_ name: String, _ title: String, _ c: [String], _ l: [String]) -> String {
        var s = "\t\t\t<Target title=\"\(name)\">\n"
        s += "\t\t\t\t<Option output=\"bin/\(name)/\(xmlEsc(title))\" prefix_auto=\"1\" extension_auto=\"1\" />\n"
        s += "\t\t\t\t<Option object_output=\"obj/\(name)/\" />\n"
        s += "\t\t\t\t<Option type=\"1\" />\n"
        s += "\t\t\t\t<Option compiler=\"gcc\" />\n"
        s += "\t\t\t\t<Compiler>\n" + c.map { "\t\t\t\t\t<Add option=\"\($0)\" />\n" }.joined() + "\t\t\t\t</Compiler>\n"
        if !l.isEmpty {
            s += "\t\t\t\t<Linker>\n" + l.map { "\t\t\t\t\t<Add option=\"\($0)\" />\n" }.joined() + "\t\t\t\t</Linker>\n"
        }
        s += "\t\t\t</Target>\n"
        return s
    }

    @discardableResult
    static func create(dir: URL, title: String, units: [String], debug: Bool, release: Bool) -> URL {
        var targets = ""
        if debug { targets += targetXML("Debug", title, ["-g"], []) }
        if release { targets += targetXML("Release", title, ["-O2"], ["-s"]) }
        let unitsXML = units.map { "\t\t<Unit filename=\"\(xmlEsc($0))\" />\n" }.joined()
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>\n"
        xml += "<CodeBlocks_project_file>\n"
        xml += "\t<FileVersion major=\"1\" minor=\"6\" />\n"
        xml += "\t<Project>\n"
        xml += "\t\t<Option title=\"\(xmlEsc(title))\" />\n"
        xml += "\t\t<Option pch_mode=\"2\" />\n"
        xml += "\t\t<Option compiler=\"gcc\" />\n"
        xml += "\t\t<Build>\n" + targets + "\t\t</Build>\n"
        xml += "\t\t<Compiler>\n\t\t\t<Add option=\"-Wall\" />\n\t\t\t<Add option=\"-fexceptions\" />\n\t\t</Compiler>\n"
        xml += unitsXML
        xml += "\t\t<Extensions />\n"
        xml += "\t</Project>\n"
        xml += "</CodeBlocks_project_file>\n"
        let url = dir.appendingPathComponent(title + ".cbp")
        try? xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func writeUnits(_ p: CBProject) {
        guard let doc = try? XMLDocument(contentsOf: p.file, options: [.nodePreserveAll]),
              let proj = (try? doc.nodes(forXPath: "/CodeBlocks_project_file/Project"))?.first as? XMLElement else { return }
        for n in (try? proj.nodes(forXPath: "Unit")) ?? [] { n.detach() }
        let ext = proj.elements(forName: "Extensions").first
        for u in p.units {
            let e = XMLElement(name: "Unit")
            if let a = XMLNode.attribute(withName: "filename", stringValue: p.rel(u)) as? XMLNode {
                e.addAttribute(a)
            }
            if let ext { proj.insertChild(e, at: ext.index) } else { proj.addChild(e) }
        }
        let data = doc.xmlData(options: [.nodePrettyPrint])
        try? data.write(to: p.file)
    }
}

enum Templates {
    static let mainCpp = """
    #include <iostream>

    using namespace std;

    int main()
    {
        cout << "Hello world!" << endl;
        return 0;
    }

    """

    static let mainC = """
    #include <stdio.h>
    #include <stdlib.h>

    int main()
    {
        printf("Hello world!\\n");
        return 0;
    }

    """

    static func header(_ name: String) -> String {
        let g = name.uppercased()
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        let guardName = g.hasSuffix("_H") || g.hasSuffix("_HPP") ? g + "_INCLUDED" : g + "_H_INCLUDED"
        return "#ifndef \(guardName)\n#define \(guardName)\n\n\n\n#endif // \(guardName)\n"
    }
}

// MARK: - Workspace

final class Workspace: ObservableObject {
    static let shared = Workspace()

    let root: URL
    @Published var projects: [CBProject] = []
    @Published var activeProject: URL?
    @Published var openDocs: [OpenDocument] = []
    @Published var startPageOpen = true
    @Published var currentTab: EditorTab = .start
    @Published var target = "Debug" { didSet { UserDefaults.standard.set(target, forKey: "target") } }
    @Published var buildLog: [LogLine] = []
    @Published var appLog: [String] = []
    @Published var messages: [BuildMessage] = []
    @Published var searchResults: [SearchResult] = []
    @Published var logTab: LogTab = .app
    @Published var mgmtTab: MgmtTab = .projects
    @Published var isBuilding = false
    @Published var runningCount = 0
    @Published var showManagement = true
    @Published var showLogs = true
    @Published var showToolbars = true
    @Published var showStatusBar = true
    @Published var showNewProject = false
    @Published var showNewFile = false
    @Published var showFindInFiles = false
    @Published var jump: JumpRequest?
    @Published var caret = CaretInfo()
    @Published var selectedTreeItem: URL?
    @Published var expanded: Set<String> = ["workspace"]
    @Published var recentProjects: [String] = [] { didSet { UserDefaults.standard.set(recentProjects, forKey: "recentProjects") } }
    @Published var recentFiles: [String] = [] { didSet { UserDefaults.standard.set(recentFiles, forKey: "recentFiles") } }

    weak var activeTextView: NSTextView?
    var consoles: [ConsoleWindowController] = []
    let processLock = NSLock()
    var buildProcess: Process?
    var abortRequested = false

    private init() {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("KodBlok Projekti", isDirectory: true)
        recentProjects = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []
        recentFiles = UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []
        target = UserDefaults.standard.string(forKey: "target") ?? "Debug"
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        log("KodBlok started up.")
        migrateLegacy()
        for path in UserDefaults.standard.stringArray(forKey: "openProjects") ?? [] {
            let u = URL(fileURLWithPath: path)
            if let p = CBPFile.load(u) {
                projects.append(p)
                expanded.insert(p.file.path)
                expanded.insert(p.file.path + "#Sources")
                expanded.insert(p.file.path + "#Headers")
                log("Opening \(u.path)")
                log("done")
            }
        }
        if let a = UserDefaults.standard.string(forKey: "activeProject") {
            activeProject = URL(fileURLWithPath: a).standardizedFileURL
        }
        if activeProject == nil || !projects.contains(where: { $0.file == activeProject }) {
            activeProject = projects.first?.file
        }
        for path in UserDefaults.standard.stringArray(forKey: "openFiles") ?? [] {
            let u = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: u.path) { open(u, select: false) }
        }
        if let first = openDocs.first { currentTab = .file(first.url) }
        if !(UserDefaults.standard.object(forKey: "startPageOpen") as? Bool ?? true), !openDocs.isEmpty {
            startPageOpen = false
        }
    }

    // Stari KodBlok projekti (folderi bez .cbp) dobijaju .cbp fajl
    private func migrateLegacy() {
        guard !UserDefaults.standard.bool(forKey: "migratedV2") else { return }
        UserDefaults.standard.set(true, forKey: "migratedV2")
        let fm = FileManager.default
        var opened: [String] = []
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for dir in dirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            if let cbp = files.first(where: { $0.pathExtension.lowercased() == "cbp" }) {
                opened.append(cbp.path)
                continue
            }
            let units = files.filter { Ext.isSource($0) || Ext.isHeader($0) }
                .map { $0.lastPathComponent }
                .sorted()
            guard !units.isEmpty else { continue }
            let url = CBPFile.create(dir: dir, title: dir.lastPathComponent, units: units, debug: true, release: true)
            opened.append(url.path)
        }
        UserDefaults.standard.set(opened, forKey: "openProjects")
        if let first = opened.first { UserDefaults.standard.set(first, forKey: "activeProject") }
    }

    func persist() {
        UserDefaults.standard.set(projects.map { $0.file.path }, forKey: "openProjects")
        UserDefaults.standard.set(activeProject?.path, forKey: "activeProject")
        UserDefaults.standard.set(openDocs.map { $0.url.path }, forKey: "openFiles")
        UserDefaults.standard.set(startPageOpen, forKey: "startPageOpen")
    }

    func log(_ s: String) {
        appLog.append(s)
    }

    // MARK: Izvedene vrednosti

    var activeProjectObj: CBProject? {
        projects.first { $0.file == activeProject } ?? projects.first
    }

    var currentDocument: OpenDocument? {
        if case .file(let u) = currentTab { return openDocs.first { $0.url == u } }
        return nil
    }

    var windowTitle: String {
        var parts: [String] = []
        if let d = currentDocument {
            var s = (d.dirty ? "*" : "") + d.name
            if let p = projects.first(where: { $0.contains(d.url) }) { s += " [\(p.title)]" }
            parts.append(s)
        } else if case .start = currentTab {
            parts.append("Start here")
        }
        parts.append("KodBlok")
        return parts.joined(separator: " - ")
    }

    var anyRunning: Bool { runningCount > 0 }

    func project(containing u: URL) -> CBProject? {
        projects.first { $0.contains(u) }
    }

    // MARK: Projekti

    func addRecentProject(_ path: String) {
        recentProjects.removeAll { $0 == path }
        recentProjects.insert(path, at: 0)
        if recentProjects.count > 10 { recentProjects = Array(recentProjects.prefix(10)) }
    }

    func addRecentFile(_ path: String) {
        recentFiles.removeAll { $0 == path }
        recentFiles.insert(path, at: 0)
        if recentFiles.count > 10 { recentFiles = Array(recentFiles.prefix(10)) }
    }

    func openProject(_ url: URL) {
        let u = url.standardizedFileURL
        if projects.contains(where: { $0.file == u }) {
            activeProject = u
            return
        }
        guard let p = CBPFile.load(u) else {
            alert("Cannot open project", "\(u.path) is not a valid Code::Blocks project file.")
            return
        }
        log("Opening \(u.path)")
        projects.append(p)
        activeProject = p.file
        expanded.insert("workspace")
        expanded.insert(p.file.path)
        expanded.insert(p.file.path + "#Sources")
        expanded.insert(p.file.path + "#Headers")
        log("done")
        addRecentProject(u.path)
        if let first = p.sources.first { open(first) }
        persist()
    }

    func reloadProject(_ file: URL) {
        guard let i = projects.firstIndex(where: { $0.file == file }), let p = CBPFile.load(file) else { return }
        projects[i] = p
    }

    func closeProject(_ file: URL) {
        guard let p = projects.first(where: { $0.file == file }) else { return }
        for d in openDocs where p.contains(d.url) {
            if d.dirty { save(d) }
        }
        openDocs.removeAll { p.contains($0.url) }
        projects.removeAll { $0.file == file }
        if activeProject == file { activeProject = projects.first?.file }
        fixCurrentTab()
        log("Closed project \(p.title)")
        persist()
    }

    func closeActiveProject() {
        if let a = activeProjectObj { closeProject(a.file) }
    }

    func closeWorkspace() {
        for p in projects { closeProject(p.file) }
    }

    func activate(_ file: URL) {
        activeProject = file
        persist()
    }

    func createProject(title rawTitle: String, folder: URL, language: String, empty: Bool, debug: Bool, release: Bool) -> Bool {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let dir = folder.appendingPathComponent(title, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent(title + ".cbp").path) {
            alert("Project already exists", "A project named \"\(title)\" already exists in\n\(dir.path)")
            return false
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var units: [String] = []
        if !empty {
            if language == "C" {
                try? Templates.mainC.write(to: dir.appendingPathComponent("main.c"), atomically: true, encoding: .utf8)
                units = ["main.c"]
            } else {
                try? Templates.mainCpp.write(to: dir.appendingPathComponent("main.cpp"), atomically: true, encoding: .utf8)
                units = ["main.cpp"]
            }
        }
        let cbp = CBPFile.create(dir: dir, title: title, units: units, debug: debug || !release, release: release)
        openProject(cbp)
        return true
    }

    func addUnits(_ urls: [URL], to file: URL) {
        guard var p = projects.first(where: { $0.file == file }) else { return }
        for u in urls where !p.contains(u) { p.units.append(u.standardizedFileURL) }
        CBPFile.writeUnits(p)
        reloadProject(file)
    }

    func removeUnit(_ u: URL, from file: URL) {
        guard var p = projects.first(where: { $0.file == file }) else { return }
        p.units.removeAll { $0.standardizedFileURL.path == u.standardizedFileURL.path }
        CBPFile.writeUnits(p)
        reloadProject(file)
    }

    func addFilesDialog() {
        guard let p = activeProjectObj else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = p.dir
        panel.message = "Add files to project \"\(p.title)\""
        if panel.runModal() == .OK {
            addUnits(panel.urls, to: p.file)
        }
    }

    func createFile(name rawName: String, kind: String, addToProject: Bool) -> Bool {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if (name as NSString).pathExtension.isEmpty {
            name += kind == "header" ? ".h" : (kind == "c" ? ".c" : (kind == "empty" ? ".txt" : ".cpp"))
        }
        let baseDir = activeProjectObj?.dir ?? root
        let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : baseDir.appendingPathComponent(name)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            alert("File exists", "The file \(url.path) already exists.")
            return false
        }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = Ext.isHeader(url) ? Templates.header(url.lastPathComponent) : ""
        try? content.write(to: url, atomically: true, encoding: .utf8)
        if addToProject, let p = activeProjectObj {
            addUnits([url], to: p.file)
        }
        open(url)
        return true
    }

    // MARK: Fajlovi

    func open(_ url: URL, select: Bool = true) {
        let u = url.standardizedFileURL
        if !openDocs.contains(where: { $0.url == u }) {
            guard let data = try? Data(contentsOf: u) else {
                alert("Cannot open file", u.path)
                return
            }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            openDocs.append(OpenDocument(url: u, text: text))
            addRecentFile(u.path)
        }
        if select { currentTab = .file(u) }
        if let p = project(containing: u), select { activeProject = p.file }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = activeProjectObj?.dir ?? root
        panel.message = "Open a project (.cbp) or a source file"
        if panel.runModal() == .OK {
            for u in panel.urls {
                if u.pathExtension.lowercased() == "cbp" { openProject(u) } else { open(u) }
            }
        }
    }

    func save(_ d: OpenDocument) {
        do {
            var t = d.text
            if d.eol.hasPrefix("Windows") { t = t.replacingOccurrences(of: "\n", with: "\r\n") }
            try t.write(to: d.url, atomically: true, encoding: .utf8)
            d.dirty = false
            objectWillChange.send()
        } catch {
            alert("Cannot save file", "\(d.url.path)\n\(error.localizedDescription)")
        }
    }

    func saveCurrent() { if let d = currentDocument { save(d) } }

    func saveAll() { for d in openDocs where d.dirty { save(d) } }

    func fixCurrentTab() {
        switch currentTab {
        case .start:
            if !startPageOpen { currentTab = openDocs.last.map { .file($0.url) } ?? .start }
        case .file(let u):
            if !openDocs.contains(where: { $0.url == u }) {
                if let last = openDocs.last { currentTab = .file(last.url) } else { currentTab = .start; startPageOpen = true }
            }
        }
    }

    func closeTab(_ tab: EditorTab) {
        switch tab {
        case .start:
            startPageOpen = false
        case .file(let u):
            if let d = openDocs.first(where: { $0.url == u }), d.dirty {
                let a = NSAlert()
                a.messageText = "Save file"
                a.informativeText = "The file \(d.name) is modified...\nDo you want to save the changes?"
                a.addButton(withTitle: "Yes")
                a.addButton(withTitle: "No")
                a.addButton(withTitle: "Cancel")
                let r = a.runModal()
                if r == .alertThirdButtonReturn { return }
                if r == .alertFirstButtonReturn { save(d) }
            }
            openDocs.removeAll { $0.url == u }
        }
        fixCurrentTab()
        persist()
    }

    func closeCurrentTab() { closeTab(currentTab) }

    func closeAllFiles() {
        for d in openDocs { closeTab(.file(d.url)) }
    }

    func showStartPage() {
        startPageOpen = true
        currentTab = .start
    }

    /// Pitanje pri izlasku
    func confirmSaveAll() -> Bool {
        let dirty = openDocs.filter { $0.dirty }
        guard !dirty.isEmpty else { persist(); return true }
        let a = NSAlert()
        a.messageText = "Save changes?"
        a.informativeText = "Some files are modified:\n" + dirty.map { $0.name }.joined(separator: "\n") + "\n\nDo you want to save them?"
        a.addButton(withTitle: "Yes")
        a.addButton(withTitle: "No")
        a.addButton(withTitle: "Cancel")
        let r = a.runModal()
        if r == .alertThirdButtonReturn { return false }
        if r == .alertFirstButtonReturn { saveAll() }
        persist()
        return true
    }

    func reveal(_ u: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([u])
    }

    func openTerminal(at dir: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([dir], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    func showShortcuts() {
        alert("KodBlok keyboard shortcuts", """
        F9  —  Build and run
        ⌘F9  —  Build
        ⇧⌘F9  —  Compile current file
        ⌘F10  —  Run
        ⌘F11  —  Rebuild
        ⌘.  —  Stop (Abort)

        ⇧⌘N  —  New project
        ⌘N  —  New file
        ⌘O  —  Open project or file
        ⌘S  —  Save file      ⇧⌘S  —  Save everything
        ⌘W  —  Close file

        ⌘F  —  Find      ⌘R  —  Replace      ⇧⌘F  —  Find in files
        ⌘L  —  Goto line
        ⌘/  —  Toggle comment

        F2  —  Show/hide Logs      ⇧F2  —  Show/hide Manager

        In the console window: Ctrl+C stops the program, Ctrl+D ends input.
        On a MacBook, F-keys may need the fn key.
        """)
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    // MARK: Editor komande

    func jump(to url: URL, line: Int) {
        open(url)
        jump = JumpRequest(url: url.standardizedFileURL, line: line)
    }

    func textFinder(_ action: NSTextFinder.Action) {
        guard let tv = activeTextView else { return }
        tv.window?.makeFirstResponder(tv)
        let item = NSMenuItem()
        item.tag = action.rawValue
        tv.performTextFinderAction(item)
    }

    func undo() { activeTextView?.undoManager?.undo() }
    func redo() { activeTextView?.undoManager?.redo() }
    func cut() { activeTextView?.cut(nil) }
    func copy() { activeTextView?.copy(nil) }
    func paste() { activeTextView?.paste(nil) }

    func gotoLineDialog() {
        guard let tv = activeTextView, let d = currentDocument else { return }
        let lines = d.text.components(separatedBy: "\n").count
        let a = NSAlert()
        a.messageText = "Goto line"
        a.informativeText = "Enter line number (1 - \(lines)):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "\(caret.line)"
        a.accessoryView = field
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        if a.runModal() == .alertFirstButtonReturn, let n = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) {
            jump = JumpRequest(url: d.url, line: max(1, min(n, lines)))
            tv.window?.makeFirstResponder(tv)
        }
    }

    /// Komentarisanje izabranih linija kao u Code::Blocks-u (// na početku linije)
    func commentSelection(_ add: Bool) {
        guard let tv = activeTextView else { return }
        let ns = tv.string as NSString
        let range = ns.lineRange(for: tv.selectedRange())
        let block = ns.substring(with: range)
        var lines = block.components(separatedBy: "\n")
        let trailing = block.hasSuffix("\n")
        if trailing { lines.removeLast() }
        let newLines = lines.map { line -> String in
            if add { return "//" + line }
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if trimmed.hasPrefix("//") {
                let indent = line.prefix(line.count - trimmed.count)
                return String(indent) + String(trimmed.dropFirst(2))
            }
            return line
        }
        let result = newLines.joined(separator: "\n") + (trailing ? "\n" : "")
        if tv.shouldChangeText(in: range, replacementString: result) {
            tv.replaceCharacters(in: range, with: result)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location, length: (result as NSString).length))
        }
    }

    func toggleComment() {
        guard let tv = activeTextView else { return }
        let ns = tv.string as NSString
        let block = ns.substring(with: ns.lineRange(for: tv.selectedRange()))
        let allCommented = block.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        commentSelection(!allCommented)
    }

    // MARK: Simboli (funkcije) u fajlu

    static let symbolRe = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:template\s*<[^>]*>\s*)?((?:[\w:<>,\*&~]+[ \t\*&]+)+)?([A-Za-z_~][\w:~]*)[ \t]*\(([^;{}()]*(?:\([^()]*\)[^;{}()]*)*)\)[ \t]*(?:const)?[ \t]*(?:noexcept)?[ \t]*(?:\n[ \t]*)?\{"#,
        options: [.anchorsMatchLines])

    static func symbols(in text: String) -> [SymbolInfo] {
        let ns = text as NSString
        let skip: Set<String> = ["if", "while", "for", "switch", "return", "catch", "else", "do", "sizeof"]
        var result: [SymbolInfo] = []
        for m in symbolRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 2))
            if skip.contains(name) { continue }
            let ret = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces) : ""
            if skip.contains(ret) || ret == "else" { continue }
            let params = ns.substring(with: m.range(at: 3)).replacingOccurrences(of: "\n", with: " ")
            let lineNo = ns.substring(to: m.range.location).components(separatedBy: "\n").count
            let sig = (ret.isEmpty ? "" : ret + " ") + name + "(" + params.trimmingCharacters(in: .whitespaces) + ")"
            result.append(SymbolInfo(name: name, signature: sig, line: lineNo))
        }
        return result
    }

    // MARK: Find in files

    func findInFiles(_ query: String, matchCase: Bool, wholeWord: Bool, scopeAll: Bool) {
        guard !query.isEmpty else { return }
        var results: [SearchResult] = []
        let projs = scopeAll ? projects : (activeProjectObj.map { [$0] } ?? [])
        var files: [(URL, String)] = []
        for p in projs { for u in p.units { files.append((u, p.rel(u))) } }
        let opts: NSString.CompareOptions = matchCase ? [] : [.caseInsensitive]
        let wordRe: NSRegularExpression? = wholeWord
            ? try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: query) + "\\b", options: matchCase ? [] : [.caseInsensitive])
            : nil
        for (u, display) in files {
            let text = openDocs.first(where: { $0.url == u.standardizedFileURL })?.text
                ?? (try? String(contentsOf: u, encoding: .utf8)) ?? ""
            for (i, line) in text.components(separatedBy: "\n").enumerated() {
                let hit: Bool
                if let wordRe {
                    hit = wordRe.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
                } else {
                    hit = line.range(of: query, options: opts) != nil
                }
                if hit {
                    results.append(SearchResult(file: u, display: display, line: i + 1, text: line.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        searchResults = results
        logTab = .search
        showLogs = true
        log("Searching for \"\(query)\": \(results.count) match(es) found")
    }
}
