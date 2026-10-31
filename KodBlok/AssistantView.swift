import SwiftUI
import AppKit

// MARK: - Claude panel (desno u KodBlok-u)

struct AssistantPanel: View {
    @EnvironmentObject var ws: Workspace
    @ObservedObject var ai = AssistantModel.shared
    @State private var showSettings = false
    @State private var includeCode = true
    @FocusState private var inputFocused: Bool

    static let topics = [
        "Algoritmi i algoritamske šeme", "Ulaz i izlaz (scanf, printf)", "Identifikatori i tipovi podataka",
        "Operatori i izrazi", "Grananja (if, else, switch)", "Ciklusi (for, while, do-while)",
        "Funkcije i doseg identifikatora", "Životni vek promenljivih (auto, static, extern)",
        "Mešovito — kao na kolokvijumu"
    ]

    var body: some View {
        VStack(spacing: 0) {
            PanelCaption(title: "Claude — asistent za učenje") { ws.showClaude = false }
            if !ai.isReady || showSettings {
                AssistantSetup(done: { showSettings = false })
            } else {
                header
                Divider()
                chat
                Divider()
                quickActions
                input
            }
        }
        .background(Color(white: 0.97))
    }

    var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.2))
            VStack(alignment: .leading, spacing: 0) {
                Text(ai.model == .sonnet ? "Sonnet 5.5" : "Haiku 5.5").font(.system(size: 11, weight: .semibold))
                Text(ai.backend == .subscription
                     ? "\(ai.materialsSummary) · tvoja Claude pretplata"
                     : "\(ai.materialsSummary) · potrošeno \(String(format: "$%.3f", ai.spentUSD))")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { ai.newConversation() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless).help("Nov razgovor")
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Podešavanja (povezivanje, model, predavanja)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if ai.messages.isEmpty { welcome }
                    ForEach(ai.messages) { m in
                        MessageBubble(message: m, streaming: ai.isStreaming && m.id == ai.messages.last?.id,
                                      onInsert: { ws.insertCode($0) })
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(8)
            }
            .onChange(of: ai.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: ai.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ćao! 👋 Tu sam da zajedno prođemo gradivo za kolokvijum.")
                .font(.system(size: 13, weight: .semibold))
            Text("Vidim kod koji pišeš i znam tvoja predavanja. Pitaj me bilo šta, ili probaj dugmad ispod:")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("• **Objasni moj kod** — šta tačno radi program u editoru")
                Text("• **Zašto ne radi?** — pomoć oko greške (prvo nagoveštaj)")
                Text("• **Zadatak** — zadatak za vežbu iz izabrane teme")
                Text("• **Kviz** — pitanja iz teorije, jedno po jedno")
                Text("• **Proveri rešenje** — ocena tvog koda kao na kolokvijumu")
            }
            .font(.system(size: 12))
            Text("Savet: označi deo koda, desni klik → „Objasni označeno (Claude)“.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.85)))
    }

    var quickActions: some View {
        let busy = ai.isStreaming
        let hasDoc = ws.currentDocument != nil
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                chip("Objasni moj kod", "text.magnifyingglass", disabled: busy || !hasDoc) {
                    ai.send("Objasni mi korak po korak šta radi ovaj program, liniju po liniju gde je važno.", context: ws.assistantContext())
                }
                chip("Zašto ne radi?", "ladybug", disabled: busy || !hasDoc) {
                    ai.send("Moj program ne radi kako treba (ili se ne kompajlira). Pomozi mi da nađem grešku — prvo mi daj nagoveštaj gde da gledam, ne celo rešenje.", context: ws.assistantContext())
                }
                Menu {
                    ForEach(Self.topics, id: \.self) { t in
                        Button(t) {
                            ai.send("Daj mi jedan zadatak za vežbu iz teme: \(t). Neka bude sličan kolokvijumskom. Nemoj odmah rešenje — sačekaj da ja pokušam.", context: nil)
                        }
                    }
                } label: { Label("Zadatak", systemImage: "list.bullet.clipboard") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(busy)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white)).overlay(Capsule().stroke(Color(white: 0.8)))
                Menu {
                    ForEach(Self.topics, id: \.self) { t in
                        Button(t) {
                            ai.send("Napravi mi kratak kviz iz teme: \(t) (iz teorije sa predavanja). Postavljaj mi pitanja JEDNO PO JEDNO, sačekaj moj odgovor, reci da li je tačno i objasni, pa onda sledeće pitanje. Ukupno 5 pitanja.", context: nil)
                        }
                    }
                } label: { Label("Kviz", systemImage: "questionmark.bubble") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(busy)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white)).overlay(Capsule().stroke(Color(white: 0.8)))
                chip("Proveri rešenje", "checkmark.seal", disabled: busy || !hasDoc) {
                    ai.send("Proveri moje rešenje: da li je tačno, ima li grešaka ili slučajeva koje ne pokriva, i šta bi asistent na kolokvijumu zamerio. Ako ima greška, prvo mi reci gde, ne prepravljaj ceo kod.", context: ws.assistantContext())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    func chip(_ title: String, _ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.white))
                .overlay(Capsule().stroke(Color(white: 0.8)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    var input: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                if ai.draft.isEmpty {
                    Text("Pitaj nešto… (⌘↩ šalje)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.6))
                        .padding(.horizontal, 5).padding(.vertical, 8)
                }
                TextEditor(text: $ai.draft)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .frame(minHeight: 44, maxHeight: 90)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(inputFocused ? Color.accentColor : Color(white: 0.8)))
            HStack(spacing: 8) {
                Toggle("Pošalji i moj trenutni kod", isOn: $includeCode)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Spacer()
                Button {
                    ai.openInClaudeAI(ai.draft.isEmpty ? "Pomozi mi oko ovog koda (Osnove programiranja, jezik C)." : ai.draft,
                                      context: includeCode ? ws.assistantContext() : nil)
                } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help("Otvori ovo pitanje na claude.ai (koristi tvoju Claude pretplatu, ne troši API kredit)")
                if ai.isStreaming {
                    Button("Stop") { ai.stop() }
                } else {
                    Button("Pošalji") {
                        let q = ai.draft
                        ai.draft = ""
                        ai.send(q, context: includeCode ? ws.assistantContext() : nil)
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(ai.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(8)
    }
}

// MARK: - Jedna poruka

struct MessageBubble: View {
    let message: ChatMessage
    let streaming: Bool
    let onInsert: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 4) {
                if message.role == .assistant {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text("Claude").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.2))
                }
                if message.text.isEmpty && streaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Razmišljam…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else if message.role == .assistant {
                    MarkdownBody(text: message.text, onInsert: onInsert)
                        .foregroundStyle(message.isError ? Color.red : Color.black)
                } else {
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.black)
                        .textSelection(.enabled)
                }
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(message.role == .user ? Color(red: 0.86, green: 0.92, blue: 1.0) : Color.white)
            )
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(white: message.role == .user ? 0.8 : 0.86)))
            if message.role == .assistant { Spacer(minLength: 10) }
        }
    }
}

/// Jednostavan prikaz markdown-a: tekst (podebljano, `kod`) i blokovi koda sa dugmadima.
struct MarkdownBody: View {
    let text: String
    let onInsert: (String) -> Void

    struct Segment: Identifiable {
        let id = UUID()
        let isCode: Bool
        let text: String
    }

    var segments: [Segment] {
        var out: [Segment] = []
        var buf: [String] = []
        var inCode = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if !buf.isEmpty || inCode { out.append(Segment(isCode: inCode, text: buf.joined(separator: "\n"))) }
                buf = []
                inCode.toggle()
            } else {
                buf.append(line)
            }
        }
        if !buf.isEmpty { out.append(Segment(isCode: inCode, text: buf.joined(separator: "\n"))) }
        return out.filter { $0.isCode || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func attributed(_ s: String) -> AttributedString {
        // naslovi "## X" → podebljano, zadrži prelome redova
        let lines = s.components(separatedBy: "\n").map { line -> String in
            var l = line
            if let r = l.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                l = "**" + l[r.upperBound...] + "**"
            }
            return l
        }
        let joined = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(joined)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments) { seg in
                if seg.isCode {
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(seg.text)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.3))
                                .textSelection(.enabled)
                                .padding(7)
                        }
                        HStack(spacing: 10) {
                            Spacer()
                            Button("Kopiraj") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(seg.text, forType: .string)
                            }
                            Button("Ubaci u editor") { onInsert(seg.text) }
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 7)
                        .padding(.bottom, 4)
                    }
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.96, green: 0.96, blue: 0.98)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.85)))
                } else {
                    Text(attributed(seg.text))
                        .font(.system(size: 12.5))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Podešavanje (API ključ, model, predavanja)

struct AssistantSetup: View {
    @EnvironmentObject var ws: Workspace
    @ObservedObject var ai = AssistantModel.shared
    @AppStorage("claudeModel") private var modelID = AssistantModelChoice.sonnet.rawValue
    @State private var key = ""
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles").font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.2))
                    Text("Poveži Claude-a").font(.system(size: 16, weight: .bold))
                }
                Text("Izaberi kako da se povežem:").font(.system(size: 12))
                Picker("", selection: $ai.backend) {
                    Text("Moja Claude pretplata").tag(AssistantBackend.subscription)
                    Text("API ključ").tag(AssistantBackend.api)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if ai.backend == .subscription { subscriptionSetup } else { apiSetup }

                Divider()
                Text("Model").font(.system(size: 13, weight: .semibold))
                Picker("", selection: $modelID) {
                    ForEach(AssistantModelChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Divider()
                Text("Predavanja").font(.system(size: 13, weight: .semibold))
                Text("Claude čita sve PDF i TXT fajlove iz foldera **~/KodBlok Projekti/Materijali** i odgovara po tvom gradivu.")
                    .font(.system(size: 12))
                Text(ai.materialsSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Dodaj predavanja…") { ai.addMaterials() }
                    Button("Otvori folder") { NSWorkspace.shared.open(AssistantModel.materialsDir) }
                    Button("Osveži") { ai.reloadMaterials() }
                }

                Divider()
                Text("Ili u pretraživaču").font(.system(size: 13, weight: .semibold))
                Text("Možeš i da pitaš na **claude.ai** u pretraživaču — KodBlok će ti tamo poslati i kod iz editora.")
                    .font(.system(size: 12))
                Button {
                    ai.openInClaudeAI("Pomozi mi oko ovog koda (Osnove programiranja 1, jezik C). Objasni mi šta radi i da li ima grešaka.",
                                      context: ws.assistantContext())
                } label: {
                    Label("Pitaj o mom kodu na claude.ai", systemImage: "safari")
                }
            }
            .padding(14)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if ai.backend == .subscription && !ai.isReady { ai.refreshCLI() }
        }
        .onChange(of: ai.backend) { _, b in if b == .subscription { ai.refreshCLI() } }
    }

    // Povezivanje preko Claude pretplate (Claude Code na Mac-u) — bez API ključa i bez dodatnog plaćanja
    @ViewBuilder var subscriptionSetup: some View {
        Text("Koristim tvoju postojeću Claude pretplatu (Pro ili Max) preko **Claude Code**-a — zvaničnog Anthropic programa za Mac. Nema API ključa i nema dodatnog plaćanja; pitanja ulaze u limite tvoje pretplate.")
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
        if ai.cliChecking {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Proveravam…").font(.system(size: 12)) }
        } else if ai.cliPath == nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Klikni **Instaliraj Claude Code** — otvoriće se Terminal i sve će se samo instalirati.")
                Text("2. Otvoriće se pretraživač: prijavi se svojim Claude nalogom (isto kao na claude.ai, može i preko Google-a) i klikni **Authorize**.")
                Text("3. Vrati se u KodBlok — povezivanje se proverava samo.")
            }
            .font(.system(size: 12))
            HStack {
                Button("Instaliraj Claude Code") { ai.installCLI() }
                    .keyboardShortcut(.defaultAction)
                Button("Proveri ponovo") { ai.refreshCLI() }
            }
        } else if ai.cliLoggedIn == false {
            Label("Claude Code je instaliran, ali nisi prijavljen.", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 12)).foregroundStyle(.orange)
            Text("Klikni **Prijavi se** — otvoriće se pretraživač, prijavi se svojim Claude nalogom i klikni **Authorize**.")
                .font(.system(size: 12))
            HStack {
                Button("Prijavi se") { ai.loginCLI() }
                    .keyboardShortcut(.defaultAction)
                Button("Proveri ponovo") { ai.refreshCLI() }
            }
        } else {
            Label("Povezano preko tvoje Claude pretplate", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
            HStack {
                Button("Počni") { done() }
                    .keyboardShortcut(.defaultAction)
                Button("Prijavi drugi nalog") { ai.loginCLI() }
                Button("Proveri ponovo") { ai.refreshCLI() }
            }
        }
    }

    @ViewBuilder var apiSetup: some View {
        Text("API ključ se plaća posebno, po pitanju (nije deo Claude pretplate). Pravi se jednom:")
            .font(.system(size: 12))
        VStack(alignment: .leading, spacing: 4) {
            Text("1. Otvori **platform.claude.com** i prijavi se.")
            Text("2. **Billing** → dopuni kredit (dovoljno je par dolara; jedno pitanje košta oko 1 cent, sa Haiku modelom 10× manje).")
            Text("3. **API Keys** → **Create Key** → kopiraj ključ (počinje sa sk-ant-…).")
            Text("4. Nalepi ga ovde i klikni Sačuvaj.")
        }
        .font(.system(size: 12))
        Button("Otvori platform.claude.com") {
            NSWorkspace.shared.open(URL(string: "https://platform.claude.com/settings/keys")!)
        }
        SecureField("sk-ant-…", text: $key)
            .textFieldStyle(.roundedBorder)
        HStack {
            Button("Sačuvaj") {
                ai.saveKey(key)
                key = ""
                if ai.hasKey { done() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            if ai.hasKey {
                Button("Ukloni ključ") { ai.saveKey("") }
                Spacer()
                Button("Nazad") { done() }
            }
        }
        Text("Ključ se čuva u macOS Keychain-u na tvom Mac-u.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
