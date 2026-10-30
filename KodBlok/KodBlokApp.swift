import SwiftUI
import AppKit

extension KeyEquivalent {
    /// Funkcijski tasteri F1...F12 (Code::Blocks prečice)
    static func fn(_ n: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(UInt32(NSF1FunctionKey + n - 1))!))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Code::Blocks je svetao — i KodBlok uvek koristi svetlu temu
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Workspace.shared.confirmSaveAll() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        Workspace.shared.persist()
        Workspace.shared.killAll()
    }
}

@main
struct KodBlokApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var ws = Workspace.shared

    var body: some Scene {
        Window("KodBlok", id: "main") {
            MainView()
                .environmentObject(ws)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { MenuCommands(ws: ws) }

        Settings {
            SettingsView()
                .environmentObject(ws)
        }
    }
}

// MARK: - Meniji (File, Edit, View, Search, Project, Build, Debug, Tools, Settings)

struct MenuCommands: Commands {
    @ObservedObject var ws: Workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Menu("New") {
                Button("Project...") { ws.showNewProject = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("File...") { ws.showNewFile = true }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            Button("Open...") { ws.openPanel() }
                .keyboardShortcut("o")
            Menu("Recent projects") {
                ForEach(ws.recentProjects, id: \.self) { p in
                    Button(p) { ws.openProject(URL(fileURLWithPath: p)) }
                }
                if !ws.recentProjects.isEmpty {
                    Divider()
                    Button("Clear history") { ws.recentProjects = [] }
                }
            }
            Menu("Recent files") {
                ForEach(ws.recentFiles, id: \.self) { p in
                    Button(p) { ws.open(URL(fileURLWithPath: p)) }
                }
                if !ws.recentFiles.isEmpty {
                    Divider()
                    Button("Clear history") { ws.recentFiles = [] }
                }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save file") { ws.saveCurrent() }
                .keyboardShortcut("s")
            Button("Save everything") { ws.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Close file") { ws.closeCurrentTab() }
                .keyboardShortcut("w")
            Button("Close all files") { ws.closeAllFiles() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Close project") { ws.closeActiveProject() }
                .disabled(ws.activeProjectObj == nil)
            Button("Close workspace") { ws.closeWorkspace() }
                .disabled(ws.projects.isEmpty)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Comment") { ws.commentSelection(true) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Uncomment") { ws.commentSelection(false) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Toggle comment") { ws.toggleComment() }
                .keyboardShortcut("/")
        }
        CommandGroup(replacing: .sidebar) {
            Toggle("Manager", isOn: $ws.showManagement)
                .keyboardShortcut(.fn(2), modifiers: [.shift])
            Toggle("Logs", isOn: $ws.showLogs)
                .keyboardShortcut(.fn(2), modifiers: [])
            Toggle("Toolbars", isOn: $ws.showToolbars)
            Toggle("Status bar", isOn: $ws.showStatusBar)
            Divider()
            Button("Start page") { ws.showStartPage() }
            Divider()
        }
        CommandMenu("Search") {
            Button("Find...") { ws.textFinder(.showFindInterface) }
                .keyboardShortcut("f")
            Button("Find in files...") { ws.showFindInFiles = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Find next") { ws.textFinder(.nextMatch) }
                .keyboardShortcut("g")
            Button("Find previous") { ws.textFinder(.previousMatch) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Replace...") { ws.textFinder(.showReplaceInterface) }
                .keyboardShortcut("r")
            Divider()
            Button("Goto line...") { ws.gotoLineDialog() }
                .keyboardShortcut("l")
        }
        CommandMenu("Project") {
            Button("Add files...") { ws.addFilesDialog() }
                .disabled(ws.activeProjectObj == nil)
            Button("Remove current file from project") {
                if let d = ws.currentDocument, let p = ws.project(containing: d.url) { ws.removeUnit(d.url, from: p.file) }
            }
            .disabled(ws.currentDocument == nil)
            Divider()
            Button("Open project folder in Finder") {
                if let p = ws.activeProjectObj { ws.reveal(p.file) }
            }
            .disabled(ws.activeProjectObj == nil)
            Divider()
            Button("Close project") { ws.closeActiveProject() }
                .disabled(ws.activeProjectObj == nil)
        }
        CommandMenu("Build") {
            Button("Build") { ws.build() }
                .keyboardShortcut(.fn(9), modifiers: [.command])
                .disabled(ws.isBuilding)
            Button("Compile current file") { ws.compileCurrentFile() }
                .keyboardShortcut(.fn(9), modifiers: [.command, .shift])
                .disabled(ws.isBuilding)
            Button("Run") { ws.run() }
                .keyboardShortcut(.fn(10), modifiers: [.command])
                .disabled(ws.isBuilding)
            Button("Build and run") { ws.buildAndRun() }
                .keyboardShortcut(.fn(9), modifiers: [])
                .disabled(ws.isBuilding)
            Button("Rebuild") { ws.build(.rebuild) }
                .keyboardShortcut(.fn(11), modifiers: [.command])
                .disabled(ws.isBuilding)
            Button("Clean") { ws.build(.clean) }
                .disabled(ws.isBuilding)
            Divider()
            Button("Abort") { ws.abort() }
                .keyboardShortcut(".")
                .disabled(!(ws.isBuilding || ws.anyRunning))
            Divider()
            Menu("Select target") {
                ForEach(ws.activeProjectObj?.targets ?? ["Debug", "Release"], id: \.self) { t in
                    Toggle(t, isOn: Binding(get: { ws.target == t }, set: { if $0 { ws.target = t } }))
                }
            }
        }
        CommandMenu("Debug") {
            Button("Start / Continue") {}.disabled(true)
            Button("Break debugger") {}.disabled(true)
            Button("Stop debugger") {}.disabled(true)
            Divider()
            Button("Run to cursor") {}.disabled(true)
            Button("Next line") {}.disabled(true)
            Button("Step into") {}.disabled(true)
            Button("Step out") {}.disabled(true)
            Divider()
            Button("Toggle breakpoint") {}.disabled(true)
        }
        CommandMenu("Tools") {
            Button("Open Terminal in project folder") {
                ws.openTerminal(at: ws.activeProjectObj?.dir ?? ws.root)
            }
            Button("Open projects folder in Finder") { ws.reveal(ws.root) }
        }
        CommandMenu("Settings") {
            SettingsLink { Text("Editor...") }
            SettingsLink { Text("Compiler...") }
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard shortcuts") { ws.showShortcuts() }
            Button("Open projects folder") { ws.reveal(ws.root) }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("tabWidth") private var tabWidth: Int = 4
    @AppStorage("cxxStd") private var cxxStd = "default"
    @AppStorage("cStd") private var cStd = "default"
    @AppStorage("extraWarnings") private var extraWarnings = false
    @AppStorage("ccAuto") private var ccAuto = true
    @AppStorage("ccChars") private var ccChars = 3
    @AppStorage("ccHover") private var ccHover = true

    var body: some View {
        TabView {
            Form {
                Toggle("Automatically launch code completion while typing", isOn: $ccAuto)
                Stepper("After typing \(ccChars) letter(s)", value: $ccChars, in: 1...6)
                    .disabled(!ccAuto)
                Toggle("Show tooltip with description on mouse hover", isOn: $ccHover)
                Text("Esc or ⌃Space opens the list manually. ↑↓ choose, Enter/Tab insert, Esc close.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("Code completion", systemImage: "text.badge.plus") }

            Form {
                Stepper("Font size: \(Int(fontSize))", value: $fontSize, in: 9...28)
                Stepper("TAB size in spaces: \(tabWidth)", value: $tabWidth, in: 2...8)
            }
            .padding(20)
            .tabItem { Label("Editor", systemImage: "doc.text") }

            Form {
                Picker("Have g++ follow the C++ standard:", selection: $cxxStd) {
                    Text("Compiler default").tag("default")
                    Text("C++11 [-std=c++11]").tag("c++11")
                    Text("C++14 [-std=c++14]").tag("c++14")
                    Text("C++17 [-std=c++17]").tag("c++17")
                    Text("C++20 [-std=c++20]").tag("c++20")
                }
                Picker("Have gcc follow the C standard:", selection: $cStd) {
                    Text("Compiler default").tag("default")
                    Text("C99 [-std=c99]").tag("c99")
                    Text("C11 [-std=c11]").tag("c11")
                    Text("C17 [-std=c17]").tag("c17")
                }
                Toggle("Enable extra compiler warnings [-Wextra]", isOn: $extraWarnings)
                Text("Selected compiler: GNU GCC Compiler (Apple clang from Xcode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("Compiler", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 260)
    }
}
