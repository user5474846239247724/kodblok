import SwiftUI
import AppKit

// MARK: - Glavni prozor

struct MainView: View {
    @EnvironmentObject var ws: Workspace
    @AppStorage("mgmtWidth") private var mgmtWidth: Double = 250
    @AppStorage("logsHeight") private var logsHeight: Double = 190

    var body: some View {
        VStack(spacing: 0) {
            if ws.showToolbars {
                ToolbarArea()
                Divider()
            }
            HStack(spacing: 0) {
                if ws.showManagement {
                    ManagementPanel()
                        .frame(width: mgmtWidth)
                    SplitHandle(vertical: true, value: $mgmtWidth, range: 160...600)
                }
                VStack(spacing: 0) {
                    EditorNotebook()
                        .frame(maxHeight: .infinity)
                    if ws.showLogs {
                        SplitHandle(vertical: false, value: $logsHeight, range: 90...650, invert: true)
                        LogsPanel()
                            .frame(height: logsHeight)
                    }
                }
                .frame(minWidth: 400)
            }
            if ws.showStatusBar {
                StatusBar()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(ws.windowTitle)
        .sheet(isPresented: $ws.showNewProject) { NewFromTemplateWizard(kind: .project) }
        .sheet(isPresented: $ws.showNewFile) { NewFromTemplateWizard(kind: .file) }
        .sheet(isPresented: $ws.showFindInFiles) { FindInFilesSheet() }
    }
}

// MARK: - Razdelnik panela (prevlačenjem se menja veličina, kao u Code::Blocks-u)

struct SplitHandle: View {
    let vertical: Bool
    @Binding var value: Double
    let range: ClosedRange<Double>
    var invert = false
    @State private var start: Double?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(white: 0.84))
            Rectangle()
                .fill(Color(white: 0.66))
                .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
        }
        .frame(width: vertical ? 5 : nil, height: vertical ? nil : 5)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside && !hovering {
                (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else if !inside && hovering {
                NSCursor.pop()
            }
            hovering = inside
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    if start == nil { start = value }
                    let d = Double(vertical ? g.translation.width : g.translation.height)
                    let v = (start ?? value) + (invert ? -d : d)
                    value = min(max(v, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in start = nil }
        )
    }
}

// MARK: - Toolbar-i

struct TBButton: View {
    let icon: String
    var color: Color = Color(nsColor: .darkGray)
    let help: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(disabled ? Color.gray.opacity(0.45) : color)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolButtonStyle())
        .help(help)
        .accessibilityLabel(help)
        .disabled(disabled)
    }
}

struct ToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(pressed: configuration.isPressed) { configuration.label }
    }
}

struct HoverHighlight<Label: View>: View {
    let pressed: Bool
    @ViewBuilder var label: Label
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(pressed ? Color.blue.opacity(0.25) : (hover && isEnabled ? Color.blue.opacity(0.12) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(hover && isEnabled ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .onHover { hover = $0 }
    }
}

/// "Build and run" ikonica: zupčanik + zelena strelica, kao u Code::Blocks-u
struct BuildRunIcon: View {
    var disabled: Bool
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12))
                .foregroundStyle(disabled ? Color.gray.opacity(0.45) : Color(red: 0.85, green: 0.65, blue: 0.0))
                .offset(x: -3, y: -2)
            Image(systemName: "play.fill")
                .font(.system(size: 8))
                .foregroundStyle(disabled ? Color.gray.opacity(0.45) : Color(red: 0.1, green: 0.6, blue: 0.1))
                .offset(x: 2, y: 2)
        }
        .frame(width: 24, height: 22)
    }
}

struct Grip: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<5) { _ in
                Circle().fill(Color.gray.opacity(0.5)).frame(width: 2, height: 2)
            }
        }
        .frame(width: 8, height: 22)
    }
}

struct TBSeparator: View {
    var body: some View {
        Rectangle().fill(Color.gray.opacity(0.35)).frame(width: 1, height: 18).padding(.horizontal, 3)
    }
}

struct ToolbarGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 1) {
            Grip()
            content
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color.white, Color(white: 0.93)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.25), lineWidth: 1))
    }
}

struct ToolbarArea: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        let noDoc = ws.currentDocument == nil
        let noProj = ws.activeProjectObj == nil
        let busy = ws.isBuilding
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ToolbarGroup {
                    TBButton(icon: "doc.badge.plus", color: .blue, help: "New file") { ws.showNewFile = true }
                    TBButton(icon: "folder.fill", color: Color(red: 0.85, green: 0.65, blue: 0.1), help: "Open...") { ws.openPanel() }
                    TBButton(icon: "square.and.arrow.down", color: .blue, help: "Save", disabled: noDoc) { ws.saveCurrent() }
                    TBButton(icon: "square.and.arrow.down.on.square", color: .blue, help: "Save everything") { ws.saveAll() }
                    TBSeparator()
                    TBButton(icon: "arrow.uturn.backward", help: "Undo", disabled: noDoc) { ws.undo() }
                    TBButton(icon: "arrow.uturn.forward", help: "Redo", disabled: noDoc) { ws.redo() }
                    TBSeparator()
                    TBButton(icon: "scissors", help: "Cut", disabled: noDoc) { ws.cut() }
                    TBButton(icon: "doc.on.doc", help: "Copy", disabled: noDoc) { ws.copy() }
                    TBButton(icon: "doc.on.clipboard", help: "Paste", disabled: noDoc) { ws.paste() }
                    TBSeparator()
                    TBButton(icon: "magnifyingglass", help: "Find...", disabled: noDoc) { ws.textFinder(.showFindInterface) }
                    TBButton(icon: "arrow.left.arrow.right", help: "Replace...", disabled: noDoc) { ws.textFinder(.showReplaceInterface) }
                }
                ToolbarGroup {
                    TBButton(icon: "gearshape.fill", color: Color(red: 0.85, green: 0.65, blue: 0.0), help: "Build (⌘F9)", disabled: noProj || busy) { ws.build() }
                    TBButton(icon: "play.fill", color: Color(red: 0.1, green: 0.6, blue: 0.1), help: "Run (⌘F10)", disabled: noProj || busy) { ws.run() }
                    Button { ws.buildAndRun() } label: { BuildRunIcon(disabled: noProj || busy) }
                        .buttonStyle(ToolButtonStyle())
                        .help("Build and run (F9)")
                        .accessibilityLabel("Build and run (F9)")
                        .disabled(noProj || busy)
                    TBButton(icon: "arrow.triangle.2.circlepath", color: .blue, help: "Rebuild (⌘F11)", disabled: noProj || busy) { ws.build(.rebuild) }
                    TBButton(icon: "xmark.octagon.fill", color: .red, help: "Abort", disabled: !(busy || ws.anyRunning)) { ws.abort() }
                    TBSeparator()
                    Text("Build target:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                    Picker("", selection: $ws.target) {
                        ForEach(ws.activeProjectObj?.targets ?? ["Debug", "Release"], id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 96)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ToolbarGroup {
                    TBButton(icon: "play.fill", color: .red, help: "Debug / Continue (F8) — debugger is not available", disabled: true) {}
                    TBButton(icon: "arrow.right.to.line", help: "Run to cursor (F4)", disabled: true) {}
                    TBButton(icon: "arrow.turn.down.right", help: "Next line (F7)", disabled: true) {}
                    TBButton(icon: "arrow.down.to.line", help: "Step into (⇧F7)", disabled: true) {}
                    TBButton(icon: "arrow.up.to.line", help: "Step out (⌘F7)", disabled: true) {}
                    TBButton(icon: "forward.frame", help: "Next instruction", disabled: true) {}
                    TBButton(icon: "arrow.down.right", help: "Step into instruction", disabled: true) {}
                    TBSeparator()
                    TBButton(icon: "pause.fill", help: "Break debugger", disabled: true) {}
                    TBButton(icon: "stop.fill", color: .red, help: "Stop debugger (⇧F8)", disabled: true) {}
                    TBSeparator()
                    TBButton(icon: "macwindow", help: "Debugging windows", disabled: true) {}
                    TBButton(icon: "info.circle", help: "Various info", disabled: true) {}
                }
                ToolbarGroup {
                    CodeCompletionBar()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(white: 0.90))
    }
}

/// Code completion toolbar: opseg + lista funkcija u fajlu
struct CodeCompletionBar: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        let symbols = ws.currentDocument.map { Workspace.symbols(in: $0.text) } ?? []
        let current = symbols.last { $0.line <= ws.caret.line }
        HStack(spacing: 4) {
            Menu {
                Text("<global>")
            } label: {
                Text("<global>").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 130)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.4)))

            Menu {
                ForEach(symbols) { s in
                    Button("\(s.signature) : \(s.line)") {
                        if let d = ws.currentDocument { ws.jump(to: d.url, line: s.line) }
                    }
                }
            } label: {
                Text(current?.signature ?? "").font(.system(size: 11)).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 260)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.4)))
            .disabled(symbols.isEmpty)
        }
        .frame(height: 22)
    }
}

// MARK: - Editor sa tabovima

struct EditorNotebook: View {
    @EnvironmentObject var ws: Workspace
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("tabWidth") private var tabWidth: Int = 4

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    if ws.startPageOpen {
                        NotebookTab(title: "Start here", dirty: false, selected: ws.currentTab == .start,
                                    select: { ws.currentTab = .start }, close: { ws.closeTab(.start) })
                    }
                    ForEach(ws.openDocs) { doc in
                        DocTab(doc: doc)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
            .frame(height: 30)
            .background(Color(white: 0.86))
            Rectangle().fill(Color(white: 0.70)).frame(height: 1)
            Group {
                switch ws.currentTab {
                case .start:
                    StartPage()
                case .file:
                    if let doc = ws.currentDocument {
                        CodeEditor(
                            doc: doc,
                            jump: ws.jump,
                            errorLines: Set(ws.messages.filter { $0.kind == .error && $0.fileURL?.standardizedFileURL == doc.url }.compactMap { $0.line }),
                            fontSize: CGFloat(fontSize),
                            tabWidth: tabWidth,
                            isC: ws.isCFile(doc.url),
                            userDocs: { Workspace.shared.userDocs(for: doc.url) },
                            onCaret: { c in if ws.caret != c { ws.caret = c } },
                            onFocus: { tv in ws.activeTextView = tv }
                        )
                        .id(doc.id.path + "-\(fontSize)-\(tabWidth)")
                    } else {
                        Color.white
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DocTab: View {
    @EnvironmentObject var ws: Workspace
    @ObservedObject var doc: OpenDocument
    var body: some View {
        NotebookTab(title: doc.name, dirty: doc.dirty, selected: ws.currentTab == .file(doc.url),
                    select: { ws.currentTab = .file(doc.url) }, close: { ws.closeTab(.file(doc.url)) })
            .contextMenu {
                Button("Close") { ws.closeTab(.file(doc.url)) }
                Button("Close all") { ws.closeAllFiles() }
                Divider()
                Button("Save") { ws.save(doc) }
                Button("Show in Finder") { ws.reveal(doc.url) }
            }
            .help(doc.url.path)
    }
}

struct NotebookTab: View {
    let title: String
    let dirty: Bool
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Text((dirty ? "*" : "") + title)
                .font(.system(size: 12))
                .foregroundStyle(Color.black)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(white: 0.35))
            }
            .buttonStyle(.borderless)
            .opacity(selected || hover ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 25)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                .fill(selected ? Color.white : (hover ? Color(white: 0.95) : Color(white: 0.91)))
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                .stroke(Color(white: 0.68), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hover = $0 }
    }
}

// MARK: - Statusna traka

struct StatusBar: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        HStack(spacing: 0) {
            Text(ws.currentDocument?.url.path ?? "")
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
            if let d = ws.currentDocument {
                cell(d.eol)
                cell("UTF-8")
                cell("Line \(ws.caret.line), Col \(ws.caret.col), Pos \(ws.caret.pos)")
                cell("Insert")
                cell(FileManager.default.isWritableFile(atPath: d.url.path) ? "Read/Write" : "Read only")
                cell("default")
            } else {
                cell(ws.isBuilding ? "Building..." : (ws.anyRunning ? "Running..." : "default"))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(white: 0.2))
        .frame(height: 22)
        .background(Color(white: 0.90))
        .overlay(alignment: .top) { Rectangle().fill(Color(white: 0.75)).frame(height: 1) }
    }

    func cell(_ s: String) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(white: 0.72)).frame(width: 1, height: 14)
            Text(s).lineLimit(1).padding(.horizontal, 8)
        }
    }
}
