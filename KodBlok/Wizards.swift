import SwiftUI
import AppKit

// MARK: - "New from template" + wizard (kao u Code::Blocks-u)

enum WizardKind { case project, file }

struct TemplateItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let color: Color
}

struct NewFromTemplateWizard: View {
    let kind: WizardKind
    @EnvironmentObject var ws: Workspace
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var selected: String = ""
    // projekat
    @State private var language = "C++"
    @State private var title = ""
    @State private var folder = ""
    @State private var debug = true
    @State private var release = true
    // fajl
    @State private var fileName = ""
    @State private var addToProject = true

    var templates: [TemplateItem] {
        switch kind {
        case .project:
            return [
                TemplateItem(id: "console", title: "Console application", icon: "terminal.fill", color: .black),
                TemplateItem(id: "empty", title: "Empty project", icon: "shippingbox", color: .blue)
            ]
        case .file:
            return [
                TemplateItem(id: "source", title: "C/C++ source", icon: "c.square.fill", color: .blue),
                TemplateItem(id: "header", title: "C/C++ header", icon: "h.square.fill", color: .purple),
                TemplateItem(id: "empty", title: "Empty file", icon: "doc", color: .gray)
            ]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if step == 0 { templatePage } else { wizardPage }
        }
        .frame(width: 640, height: 440)
        .onAppear {
            selected = templates.first?.id ?? ""
            folder = ws.root.path
        }
    }

    // Korak 0: izbor šablona
    var templatePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New from template").font(.system(size: 16, weight: .semibold))
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(kind == .project ? "Projects" : "Files")
                        .font(.system(size: 12))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.85))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .frame(width: 140)
                .padding(6)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.gray.opacity(0.4)))

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 12) {
                        ForEach(templates) { t in
                            VStack(spacing: 6) {
                                Image(systemName: t.icon)
                                    .font(.system(size: 34))
                                    .foregroundStyle(t.color)
                                    .frame(width: 56, height: 48)
                                Text(t.title)
                                    .font(.system(size: 11))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(selected == t.id ? .white : .black)
                                    .padding(.horizontal, 3)
                                    .background(selected == t.id ? Color.accentColor : Color.clear)
                            }
                            .frame(width: 110, height: 90)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { selected = t.id; go() }
                            .simultaneousGesture(TapGesture().onEnded { selected = t.id })
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { selected = t.id }
                        }
                    }
                    .padding(10)
                }
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.gray.opacity(0.4)))
            }
            Text("Select a template and click Go (or double-click it).")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Go", action: go).keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }

    func go() {
        if kind == .file && ws.activeProjectObj == nil { addToProject = false }
        if kind == .file && fileName.isEmpty {
            fileName = selected == "header" ? "header.h" : (selected == "empty" ? "file.txt" : "source.cpp")
        }
        step = 1
    }

    // Wizard stranice
    var lastStep: Int {
        switch kind {
        case .project: return selected == "console" ? 3 : 2
        case .file: return selected == "source" ? 2 : 1
        }
    }

    var wizardTitle: String {
        templates.first { $0.id == selected }?.title ?? ""
    }

    var wizardPage: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // bočna slika wizarda
                ZStack {
                    LinearGradient(colors: [Color(red: 0.15, green: 0.25, blue: 0.5), Color(red: 0.05, green: 0.1, blue: 0.25)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                        Text(wizardTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .multilineTextAlignment(.center).padding(.horizontal, 8)
                    }
                }
                .frame(width: 170)

                VStack(alignment: .leading, spacing: 12) {
                    pageContent
                    Spacer()
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            Divider()
            HStack {
                Spacer()
                Button("< Back") { step -= 1 }.disabled(step == 0)
                if step < lastStep {
                    Button("Next >") { next() }.keyboardShortcut(.defaultAction).disabled(!canContinue)
                } else {
                    Button("Finish") { finish() }.keyboardShortcut(.defaultAction).disabled(!canContinue)
                }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
    }

    var canContinue: Bool {
        switch (kind, step) {
        case (.project, 2) where selected == "console", (.project, 1) where selected == "empty":
            return !title.trimmingCharacters(in: .whitespaces).isEmpty && !folder.isEmpty
        case (.file, lastStep):
            return !fileName.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    func next() { step += 1 }

    @ViewBuilder
    var pageContent: some View {
        switch kind {
        case .project:
            if selected == "console" {
                switch step {
                case 1: languagePage(project: true)
                case 2: titlePage
                default: compilerPage
                }
            } else {
                switch step {
                case 1: titlePage
                default: compilerPage
                }
            }
        case .file:
            if selected == "source" && step == 1 {
                languagePage(project: false)
            } else {
                filePage
            }
        }
    }

    func languagePage(project: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Please select the language you want to use.").font(.system(size: 13))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(["C", "C++"], id: \.self) { l in
                    Button { language = l } label: {
                        Text(l)
                            .font(.system(size: 13))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(language == l ? Color.accentColor : Color.white)
                            .foregroundStyle(language == l ? .white : .black)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(l)
                }
            }
            .frame(width: 220)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.5)))
        }
        .onChange(of: language) { _, l in
            if !project {
                let base = (fileName as NSString).deletingPathExtension
                fileName = base + (l == "C" ? ".c" : ".cpp")
            }
        }
    }

    var titlePage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Please select the folder where you want the new project to be created as well as its title.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Text("Project title:").font(.system(size: 12))
            TextField("", text: $title).textFieldStyle(.roundedBorder)
            Text("Folder to create project in:").font(.system(size: 12))
            HStack {
                TextField("", text: $folder).textFieldStyle(.roundedBorder)
                Button("...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = URL(fileURLWithPath: folder)
                    if panel.runModal() == .OK, let u = panel.url { folder = u.path }
                }
            }
            Text("Project filename:").font(.system(size: 12))
            TextField("", text: .constant(title.isEmpty ? "" : title + ".cbp")).textFieldStyle(.roundedBorder).disabled(true)
            Text("Resulting filename:").font(.system(size: 12))
            TextField("", text: .constant(title.isEmpty ? "" : (folder as NSString).appendingPathComponent(title + "/" + title + ".cbp")))
                .textFieldStyle(.roundedBorder).disabled(true)
        }
    }

    var compilerPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Please select the compiler to use and which configurations you want enabled in your project.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Text("Compiler:").font(.system(size: 12))
            Picker("", selection: .constant("gcc")) {
                Text("GNU GCC Compiler").tag("gcc")
            }
            .labelsHidden()
            .frame(width: 260)
            Toggle("Create \"Debug\" configuration:", isOn: $debug)
            Group {
                Text("Output dir.:     bin/Debug/")
                Text("Objects output dir.:     obj/Debug/")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 20)
            Toggle("Create \"Release\" configuration:", isOn: $release)
            Group {
                Text("Output dir.:     bin/Release/")
                Text("Objects output dir.:     obj/Release/")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 20)
        }
    }

    var filePage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Please enter the file's location and name and whether to add it to the active project.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Text("Filename with full path:").font(.system(size: 12))
            HStack(spacing: 4) {
                Text((ws.activeProjectObj?.dir.path ?? ws.root.path) + "/")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                TextField("", text: $fileName).textFieldStyle(.roundedBorder)
            }
            Toggle("Add file to active project", isOn: $addToProject)
                .disabled(ws.activeProjectObj == nil)
            if addToProject, let p = ws.activeProjectObj {
                Text("In build target(s): " + p.targets.joined(separator: ", "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 20)
            }
        }
    }

    func finish() {
        switch kind {
        case .project:
            let ok = ws.createProject(title: title, folder: URL(fileURLWithPath: folder),
                                      language: language, empty: selected == "empty",
                                      debug: debug, release: release)
            if ok { dismiss() }
        case .file:
            let k = selected == "header" ? "header" : (selected == "empty" ? "empty" : (language == "C" ? "c" : "cpp"))
            if ws.createFile(name: fileName, kind: k, addToProject: addToProject) { dismiss() }
        }
    }
}

// MARK: - Find in files

struct FindInFilesSheet: View {
    @EnvironmentObject var ws: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var matchCase = false
    @State private var wholeWord = false
    @State private var scope = "project"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find in files").font(.system(size: 15, weight: .semibold))
            Text("Text to search for:").font(.system(size: 12))
            TextField("", text: $query).textFieldStyle(.roundedBorder).onSubmit(search)
            HStack(spacing: 20) {
                Toggle("Match case", isOn: $matchCase)
                Toggle("Whole word", isOn: $wholeWord)
            }
            Picker("Scope:", selection: $scope) {
                Text("Project files").tag("project")
                Text("Workspace files").tag("workspace")
            }
            .pickerStyle(.radioGroup)
            HStack {
                Spacer()
                Button("OK", action: search).keyboardShortcut(.defaultAction).disabled(query.isEmpty)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear {
            if let tv = ws.activeTextView {
                let sel = (tv.string as NSString).substring(with: tv.selectedRange())
                if !sel.isEmpty && !sel.contains("\n") { query = sel }
            }
        }
    }

    func search() {
        ws.findInFiles(query, matchCase: matchCase, wholeWord: wholeWord, scopeAll: scope == "workspace")
        dismiss()
    }
}
