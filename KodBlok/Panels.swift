import SwiftUI
import AppKit

// MARK: - Zajednički izgled panela (naslov + tabovi)

struct PanelCaption: View {
    let title: String
    let close: () -> Void
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.15))
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(white: 0.3))
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(LinearGradient(colors: [Color(white: 0.86), Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.65)).frame(height: 1) }
    }
}

struct PanelTab: View {
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Color(white: 0.3)) }
            Text(title).font(.system(size: 11)).foregroundStyle(Color.black).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                .fill(selected ? Color.white : Color(white: 0.89))
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                .stroke(Color(white: 0.68), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - Management

struct ManagementPanel: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        VStack(spacing: 0) {
            PanelCaption(title: "Management") { ws.showManagement = false }
            HStack(spacing: 2) {
                ForEach(MgmtTab.allCases) { t in
                    PanelTab(title: t.rawValue, selected: ws.mgmtTab == t) { ws.mgmtTab = t }
                }
                Spacer()
            }
            .padding(.horizontal, 3)
            .padding(.top, 3)
            .background(Color(white: 0.86))
            Rectangle().fill(Color(white: 0.68)).frame(height: 1)
            Group {
                switch ws.mgmtTab {
                case .projects: ProjectsTree()
                case .files: FilesTab()
                case .symbols: SymbolsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
    }
}

struct TreeRow: View {
    let depth: Int
    let icon: String
    var iconColor: Color = Color(white: 0.35)
    let title: String
    var bold = false
    var expandable = false
    var isExpanded = false
    var selected = false
    var toggle: (() -> Void)?
    var tap: (() -> Void)?
    var doubleTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if expandable {
                    Image(systemName: isExpanded ? "minus.square" : "plus.square")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.4))
                        .onTapGesture { toggle?() }
                } else {
                    Color.clear
                }
            }
            .frame(width: 12)
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12, weight: bold ? .bold : .regular))
                .foregroundStyle(selected ? Color.white : Color.black)
                .lineLimit(1)
                .padding(.horizontal, 2)
                .background(selected ? Color.accentColor : Color.clear)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 16 + 4)
        .frame(height: 19)
        .contentShape(Rectangle())
        .onTapGesture {
            // Jedan gest za oba slučaja: macOS sam broji klikove (clickCount),
            // pa dupli klik pouzdano otvara fajl čak i kad se red osveži posle prvog klika.
            let clicks = NSApp.currentEvent?.clickCount ?? 1
            if clicks >= 2 {
                if let doubleTap { doubleTap() } else { toggle?() }
            } else {
                tap?()
            }
        }
    }
}

struct ProjectsTree: View {
    @EnvironmentObject var ws: Workspace

    func key(_ p: CBProject, _ folder: String) -> String { p.file.path + "#" + folder }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                let wsOpen = ws.expanded.contains("workspace")
                TreeRow(depth: 0, icon: "square.stack.3d.up.fill", iconColor: Color(red: 0.3, green: 0.45, blue: 0.75),
                        title: "Workspace", expandable: true, isExpanded: wsOpen,
                        toggle: { toggle("workspace") })
                    .contextMenu {
                        Button("New project...") { ws.showNewProject = true }
                        Button("Open project...") { ws.openPanel() }
                        Divider()
                        Button("Close workspace") { ws.closeWorkspace() }
                    }
                if wsOpen {
                    ForEach(ws.projects) { p in
                        projectRows(p)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func toggle(_ k: String) {
        if ws.expanded.contains(k) { ws.expanded.remove(k) } else { ws.expanded.insert(k) }
    }

    @ViewBuilder
    func projectRows(_ p: CBProject) -> some View {
        let open = ws.expanded.contains(p.file.path)
        let active = ws.activeProjectObj?.file == p.file
        TreeRow(depth: 1, icon: "shippingbox.fill", iconColor: Color(red: 0.25, green: 0.55, blue: 0.85),
                title: p.title, bold: active, expandable: true, isExpanded: open,
                selected: ws.selectedTreeItem == p.file,
                toggle: { toggle(p.file.path) },
                tap: { ws.selectedTreeItem = p.file },
                doubleTap: { ws.activate(p.file); toggle(p.file.path) })
            .contextMenu {
                Button("Activate project") { ws.activate(p.file) }
                Divider()
                Button("Build") { ws.activate(p.file); ws.build() }
                Button("Rebuild") { ws.activate(p.file); ws.build(.rebuild) }
                Button("Clean") { ws.activate(p.file); ws.build(.clean) }
                Divider()
                Button("Add files...") { ws.activate(p.file); ws.addFilesDialog() }
                Button("New file...") { ws.activate(p.file); ws.showNewFile = true }
                Divider()
                Button("Open project folder in Finder") { ws.reveal(p.file) }
                Button("Open Terminal here") { ws.openTerminal(at: p.dir) }
                Divider()
                Button("Close project") { ws.closeProject(p.file) }
            }
        if open {
            folderRows(p, "Sources", p.sources)
            folderRows(p, "Headers", p.headers)
            folderRows(p, "Others", p.others)
        }
    }

    @ViewBuilder
    func folderRows(_ p: CBProject, _ name: String, _ files: [URL]) -> some View {
        if !files.isEmpty {
            let k = key(p, name)
            let open = ws.expanded.contains(k)
            TreeRow(depth: 2, icon: open ? "folder.fill" : "folder", iconColor: Color(red: 0.9, green: 0.7, blue: 0.2),
                    title: name, expandable: true, isExpanded: open, toggle: { toggle(k) })
            if open {
                ForEach(files.sorted { p.rel($0).localizedStandardCompare(p.rel($1)) == .orderedAscending }, id: \.self) { u in
                    TreeRow(depth: 3, icon: Ext.isHeader(u) ? "h.square" : (Ext.isSource(u) ? "c.square" : "doc"),
                            iconColor: Ext.isHeader(u) ? .purple : .blue,
                            title: p.rel(u),
                            selected: ws.selectedTreeItem == u,
                            tap: { ws.selectedTreeItem = u },
                            doubleTap: { ws.open(u) })
                        .contextMenu {
                            Button("Open file") { ws.open(u) }
                            Button("Show in Finder") { ws.reveal(u) }
                            Divider()
                            Button("Remove file from project") { ws.removeUnit(u, from: p.file) }
                        }
                }
            }
        }
    }
}

struct FilesTab: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        let dir = ws.activeProjectObj?.dir ?? ws.root
        let items = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        VStack(alignment: .leading, spacing: 0) {
            Text(dir.path)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.head)
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.95))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items, id: \.self) { u in
                        let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                        TreeRow(depth: 0, icon: isDir ? "folder.fill" : "doc.text",
                                iconColor: isDir ? Color(red: 0.9, green: 0.7, blue: 0.2) : .blue,
                                title: u.lastPathComponent,
                                selected: ws.selectedTreeItem == u,
                                tap: { ws.selectedTreeItem = u },
                                doubleTap: {
                                    if isDir { ws.reveal(u) }
                                    else if u.pathExtension.lowercased() == "cbp" { ws.openProject(u) }
                                    else { ws.open(u) }
                                })
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct SymbolsTab: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        let symbols = ws.currentDocument.map { Workspace.symbols(in: $0.text) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let d = ws.currentDocument {
                    TreeRow(depth: 0, icon: "doc.text", iconColor: .blue, title: d.name, bold: true)
                    ForEach(symbols) { s in
                        TreeRow(depth: 1, icon: "f.cursive", iconColor: .purple, title: s.signature,
                                tap: { ws.jump(to: d.url, line: s.line) })
                    }
                } else {
                    Text("No file open").font(.system(size: 11)).foregroundStyle(.secondary).padding(8)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Logs & others

struct LogsPanel: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        VStack(spacing: 0) {
            PanelCaption(title: "Logs & others") { ws.showLogs = false }
            HStack(spacing: 2) {
                ForEach(LogTab.allCases) { t in
                    PanelTab(title: t.rawValue, icon: t.icon, selected: ws.logTab == t) { ws.logTab = t }
                }
                Spacer()
            }
            .padding(.horizontal, 3)
            .padding(.top, 3)
            .background(Color(white: 0.86))
            Rectangle().fill(Color(white: 0.68)).frame(height: 1)
            Group {
                switch ws.logTab {
                case .app: AppLogView()
                case .search: SearchResultsView()
                case .buildLog: BuildLogView()
                case .messages: BuildMessagesView()
                case .debugger:
                    Text("The debugger is not available in this version of KodBlok.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
    }
}

struct AppLogView: View {
    @EnvironmentObject var ws: Workspace
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(ws.appLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 12)).foregroundStyle(Color.black).textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: ws.appLog.count) { _, _ in proxy.scrollTo("end") }
        }
    }
}

struct BuildLogView: View {
    @EnvironmentObject var ws: Workspace

    func color(_ k: LogKind) -> Color {
        switch k {
        case .error, .failure: return Color(red: 0.85, green: 0, blue: 0)
        case .warning: return Color(red: 0, green: 0, blue: 0.8)
        case .success: return Color(red: 0, green: 0, blue: 0.85)
        default: return .black
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(ws.buildLog) { l in
                        Text(l.text.isEmpty ? " " : l.text)
                            .font(.system(size: 12, weight: (l.kind == .failure) ? .bold : .regular))
                            .foregroundStyle(color(l.kind))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: ws.buildLog.count) { _, _ in proxy.scrollTo("end") }
        }
    }
}

struct BuildMessagesView: View {
    @EnvironmentObject var ws: Workspace
    @State private var selection = Set<UUID>()

    func color(_ m: BuildMessage) -> Color {
        switch m.kind {
        case .error, .footerFail: return Color(red: 0.8, green: 0, blue: 0)
        case .warning: return Color(red: 0, green: 0, blue: 0.75)
        case .note: return Color(white: 0.3)
        default: return .black
        }
    }

    var body: some View {
        Table(ws.messages, selection: $selection) {
            TableColumn("File") { m in
                Text(m.file).foregroundStyle(color(m)).font(.system(size: 12))
            }
            .width(min: 60, ideal: 150, max: 400)
            TableColumn("Line") { m in
                Text(m.line.map(String.init) ?? "").foregroundStyle(color(m)).font(.system(size: 12))
            }
            .width(min: 30, ideal: 45, max: 80)
            TableColumn("Message") { m in
                Text(m.text)
                    .foregroundStyle(color(m))
                    .font(.system(size: 12, weight: [.header, .footerOK, .footerFail].contains(m.kind) ? .semibold : .regular))
                    .textSelection(.enabled)
            }
        }
        .onChange(of: selection) { _, ids in
            if let id = ids.first, let m = ws.messages.first(where: { $0.id == id }), let u = m.fileURL, let line = m.line {
                ws.jump(to: u, line: line)
            }
        }
    }
}

struct SearchResultsView: View {
    @EnvironmentObject var ws: Workspace
    @State private var selection = Set<UUID>()

    var body: some View {
        Table(ws.searchResults, selection: $selection) {
            TableColumn("File") { r in Text(r.display).font(.system(size: 12)) }
                .width(min: 60, ideal: 150, max: 400)
            TableColumn("Line") { r in Text("\(r.line)").font(.system(size: 12)) }
                .width(min: 30, ideal: 45, max: 80)
            TableColumn("Text") { r in Text(r.text).font(.system(size: 12, design: .monospaced)) }
        }
        .onChange(of: selection) { _, ids in
            if let id = ids.first, let r = ws.searchResults.first(where: { $0.id == id }) {
                ws.jump(to: r.file, line: r.line)
            }
        }
    }
}

// MARK: - Start here

struct StartPage: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KodBlok")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.2, blue: 0.4))
                        Text("C/C++ IDE for macOS")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(white: 0.3))
                        Text("Release 2.3")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .padding(.top, 30)

                VStack(alignment: .leading, spacing: 10) {
                    link("Create a new project", icon: "plus.square.fill") { ws.showNewProject = true }
                    link("Open an existing project", icon: "folder.fill") { ws.openPanel() }
                }
                .padding(.top, 8)

                if !ws.recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent projects").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black)
                        ForEach(ws.recentProjects, id: \.self) { path in
                            link(path, icon: "shippingbox") { ws.openProject(URL(fileURLWithPath: path)) }
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                }
                if !ws.recentFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent files").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black)
                        ForEach(ws.recentFiles.prefix(6), id: \.self) { path in
                            link(path, icon: "doc.text") { ws.open(URL(fileURLWithPath: path)) }
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                }
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
        }
        .background(Color.white)
    }

    func link(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.75))
                Text(title)
                    .underline()
                    .foregroundStyle(Color(red: 0.0, green: 0.2, blue: 0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}
