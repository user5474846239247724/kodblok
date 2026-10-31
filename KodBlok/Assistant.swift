import SwiftUI
import AppKit
import PDFKit
import Security

// MARK: - API ključ u macOS Keychain-u

enum Keychain {
    static let service = "com.mitar.kodblok.anthropic"
    static let account = "api-key"

    static func get() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard let v = value, !v.isEmpty, let d = v.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = d
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Poruke

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String          // šta se prikazuje
    var apiText: String       // šta se šalje Claude-u (sa kodom i greškama)
    var isError = false
}

enum AssistantModelChoice: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sonnet: return "Claude Sonnet 5.5 — najbolja objašnjenja"
        case .haiku: return "Claude Haiku 5.5 — brži i ~10× jeftiniji"
        }
    }
    // USD po milion tokena: ulaz, izlaz, keš upis, keš čitanje
    var prices: (input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        switch self {
        case .sonnet: return (2.0, 10.0, 2.5, 0.10)
        case .haiku: return (0.10, 0.50, 0.125, 0.01)
        }
    }
}

/// Kako KodBlok razgovara sa Claude-om
enum AssistantBackend: String, CaseIterable, Identifiable {
    case subscription   // Claude Code na Mac-u — koristi Claude pretplatu (Pro/Max), bez API ključa
    case api            // API ključ sa platform.claude.com — plaća se po pitanju
    var id: String { rawValue }
}

// MARK: - Asistent

final class AssistantModel: ObservableObject {
    static let shared = AssistantModel()

    @Published var messages: [ChatMessage] = []
    @Published var isStreaming = false
    @Published var hasKey = false
    @Published var spentUSD: Double = UserDefaults.standard.double(forKey: "claudeSpentUSD") {
        didSet { UserDefaults.standard.set(spentUSD, forKey: "claudeSpentUSD") }
    }
    @Published var materialsSummary = ""
    @Published var draft = ""
    @Published var backend: AssistantBackend = AssistantBackend(rawValue: UserDefaults.standard.string(forKey: "claudeBackend") ?? "") ?? .subscription {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: "claudeBackend") }
    }
    /// Putanja do Claude Code programa (`claude`) ako je instaliran
    @Published var cliPath: String?
    /// nil = još ne znamo, true/false = prijavljen na Claude nalog
    @Published var cliLoggedIn: Bool?
    @Published var cliChecking = false

    /// Spreman za pitanja (izabrani način je podešen)
    var isReady: Bool {
        backend == .subscription ? (cliPath != nil && cliLoggedIn != false) : hasKey
    }

    private var task: Task<Void, Never>?
    private var process: Process?
    private var cliSession: String?
    private var materialsCache: String?

    var model: AssistantModelChoice {
        AssistantModelChoice(rawValue: UserDefaults.standard.string(forKey: "claudeModel") ?? "") ?? .sonnet
    }

    static var materialsDir: URL {
        Workspace.shared.root.appendingPathComponent("Materijali", isDirectory: true)
    }

    private init() {
        hasKey = !(Keychain.get() ?? "").isEmpty
        try? FileManager.default.createDirectory(at: Self.materialsDir, withIntermediateDirectories: true)
        reloadMaterials()
        refreshCLI()
    }

    func saveKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(k.isEmpty ? nil : k)
        hasKey = !k.isEmpty
    }

    // MARK: Materijali sa predavanja

    func reloadMaterials() {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: Self.materialsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { ["txt", "md", "pdf", "c", "cpp", "h"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var out = ""
        var count = 0
        for f in files {
            var text = ""
            if f.pathExtension.lowercased() == "pdf" {
                text = PDFDocument(url: f)?.string ?? ""
            } else {
                text = (try? String(contentsOf: f, encoding: .utf8)) ?? (try? String(contentsOf: f, encoding: .isoLatin1)) ?? ""
            }
            text = text.replacingOccurrences(of: "\u{0C}", with: "\n")
                .replacingOccurrences(of: "[ \\t]{3,}", with: "  ", options: .regularExpression)
                .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if out.count + text.count > 450_000 { break }
            out += "\n\n===== \(f.lastPathComponent) =====\n" + text
            count += 1
        }
        materialsCache = out
        materialsSummary = count == 0 ? "Nema materijala" : "\(count) fajl(ova) sa predavanja učitano"
    }

    func addMaterials() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Izaberi predavanja (PDF ili TXT) koja Claude treba da zna"
        guard panel.runModal() == .OK else { return }
        for u in panel.urls {
            let dest = Self.materialsDir.appendingPathComponent(u.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: u, to: dest)
        }
        reloadMaterials()
    }

    // MARK: Uputstvo za Claude-a (tutor za kolokvijum)

    private var rules: String {
        """
        Ti si Claude, asistent za učenje programiranja ugrađen u KodBlok (C/C++ okruženje u stilu Code::Blocks-a na Mac-u).
        Razgovaraš sa studentom prve godine koji uči predmet "Osnove programiranja 1" (jezik C) i sprema kolokvijum.
        Ispod su tekstovi predavanja sa tog predmeta — oslanjaj se na njih (terminologija, primeri, stil koda, gradivo).

        Kako da pomažeš:
        - Odgovaraj na srpskom, latinicom, jednostavno i korak po korak, kao dobar asistent na vežbama.
        - Budi kratak i jasan; koristi kratke pasuse i nabrajanja. Kod piši u ```c blokovima.
        - Piši C kao na predavanjima: #include <stdio.h>, int main(), scanf/printf, bez C++ (cout, string, vector) osim ako student sam pita.
        - Kada student traži pomoć oko zadatka za vežbu, prvo daj nagoveštaj ili sledeći korak i pusti ga da pokuša. Celo rešenje daj tek kad izričito traži ("daj rešenje") ili posle nekoliko pokušaja.
        - Kada proveravaš njegov kod: reci šta je dobro, šta je pogrešno i zašto (sa brojem linije), i kako da popravi. Pazi na tipične greške: & u scanf, %d/%f/%lf, = umesto ==, ; posle if/for, celobrojno deljenje, neinicijalizovane promenljive, granice petlji.
        - Kada zadaješ zadatke ili pitanja, neka liče na kolokvijumske i budu iz gradiva sa predavanja (algoritamske šeme, ulaz/izlaz, tipovi, operatori, grananja, ciklusi, funkcije, doseg i životni vek). Zadaj jedan po jedan i sačekaj odgovor.
        - Kada objašnjavaš algoritamske šeme (dijagrame toka), opiši ih tekstom: Početak → ulaz → obrada → uslov (da/ne) → izlaz → Kraj.
        - Ako u poruci postoji [Trenutni fajl] i [Build greške], to je kod koji student upravo piše u KodBlok-u — koristi ga.
        - Ohrabruj, ali budi iskren kad nešto nije tačno.
        """
    }

    // MARK: Slanje

    func send(_ question: String, context: String?) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isStreaming else { return }
        let key = Keychain.get()
        if backend == .api && (key ?? "").isEmpty { return }
        if backend == .subscription && cliPath == nil { return }
        var api = q
        if let context, !context.isEmpty { api = context + "\n\n" + q }
        messages.append(ChatMessage(role: .user, text: q, apiText: api))
        messages.append(ChatMessage(role: .assistant, text: "", apiText: ""))
        isStreaming = true
        let model = self.model
        let materials = materialsCache ?? ""
        let history = messages.dropLast().filter { !$0.isError && !($0.role == .assistant && $0.text.isEmpty) }
        if backend == .subscription, let cli = cliPath {
            let resume = cliSession
            let prompt = resume == nil ? Self.transcript(Array(history)) : api
            task = Task.detached { [weak self] in
                await self?.streamCLI(cli: cli, model: model, materials: materials, prompt: prompt, resume: resume)
            }
        } else if let key {
            task = Task.detached { [weak self] in
                await self?.stream(key: key, model: model, materials: materials, history: Array(history))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        isStreaming = false
    }

    func newConversation() {
        stop()
        messages = []
        cliSession = nil
    }

    /// Kad nastavljamo stari razgovor bez sačuvane sesije: ceo dosadašnji razgovor u jednoj poruci
    private static func transcript(_ history: [ChatMessage]) -> String {
        guard history.count > 1 else { return history.last?.apiText ?? "" }
        var out = "Dosadašnji razgovor:\n"
        for m in history.dropLast() {
            out += (m.role == .user ? "\n[Student]: " : "\n[Ti]: ") + m.apiText + "\n"
        }
        return out + "\n[Student — nova poruka]:\n" + (history.last?.apiText ?? "")
    }

    private func appendToLast(_ s: String) {
        guard let i = messages.indices.last else { return }
        messages[i].text += s
        messages[i].apiText = messages[i].text
    }

    private func failLast(_ s: String) {
        guard let i = messages.indices.last else { return }
        if messages[i].text.isEmpty {
            messages[i].text = s
            messages[i].isError = true
        } else {
            messages[i].text += "\n\n⚠️ " + s
        }
    }

    private func ui(_ f: @escaping () -> Void) async {
        await MainActor.run { f() }
    }

    private func stream(key: String, model: AssistantModelChoice, materials: String, history: [ChatMessage]) async {
        var system: [[String: Any]] = [["type": "text", "text": rules]]
        if !materials.isEmpty {
            system.append(["type": "text",
                           "text": "MATERIJALI SA PREDAVANJA:\n" + materials,
                           "cache_control": ["type": "ephemeral"]])
        }
        let msgs: [[String: Any]] = history.map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.apiText]
        }
        let body: [String: Any] = ["model": model.rawValue, "max_tokens": 2048, "stream": true,
                                   "system": system, "messages": msgs]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var inTok = 0, outTok = 0, cacheW = 0, cacheR = 0
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                var raw = ""
                for try await line in bytes.lines { raw += line }
                let msg = (try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
                    .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? raw
                let text = Self.explain(status: status, message: msg)
                await ui { self.failLast(text); self.isStreaming = false; self.task = nil }
                return
            }
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard line.hasPrefix("data:") else { continue }
                let json = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                      let type = obj["type"] as? String else { continue }
                switch type {
                case "content_block_delta":
                    if let d = obj["delta"] as? [String: Any], let t = d["text"] as? String {
                        await ui { self.appendToLast(t) }
                    }
                case "message_start":
                    if let u = (obj["message"] as? [String: Any])?["usage"] as? [String: Any] {
                        inTok = u["input_tokens"] as? Int ?? 0
                        cacheW = u["cache_creation_input_tokens"] as? Int ?? 0
                        cacheR = u["cache_read_input_tokens"] as? Int ?? 0
                    }
                case "message_delta":
                    if let u = obj["usage"] as? [String: Any] { outTok = u["output_tokens"] as? Int ?? outTok }
                case "error":
                    let m = (obj["error"] as? [String: Any])?["message"] as? String ?? "Nepoznata greška"
                    let text = Self.explain(status: 0, message: m)
                    await ui { self.failLast(text) }
                default:
                    break
                }
            }
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            let text = "Nema veze sa Claude-om: \(error.localizedDescription)\nProveri internet konekciju."
            await ui { self.failLast(text) }
        }
        let p = model.prices
        let cost = (Double(inTok) * p.input + Double(outTok) * p.output + Double(cacheW) * p.cacheWrite + Double(cacheR) * p.cacheRead) / 1_000_000
        await ui {
            self.spentUSD += cost
            self.isStreaming = false
            self.task = nil
        }
    }

    // MARK: Claude pretplata preko Claude Code-a (bez API ključa)

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    private static var extraPath: [String] {
        ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
         "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin"]
    }

    private static var cliEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPath + [path]).joined(separator: ":")
        env.removeValue(forKey: "ANTHROPIC_API_KEY")   // da sigurno ide preko pretplate
        return env
    }

    /// Pronađi `claude` i proveri da li je prijavljen
    func refreshCLI() {
        cliChecking = true
        Task.detached { [weak self] in
            let fm = FileManager.default
            var found = Self.extraPath.map { $0 + "/claude" }.first { fm.isExecutableFile(atPath: $0) }
            if found == nil {
                let out = Self.runQuick("/bin/zsh", ["-lc", "command -v claude"])
                let p = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if p.hasPrefix("/"), fm.isExecutableFile(atPath: p) { found = p }
            }
            var logged: Bool? = nil
            if let found {
                let out = Self.runQuick(found, ["auth", "status", "--json"])
                if let d = out.data(using: .utf8),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let li = o["loggedIn"] as? Bool {
                    logged = li
                }
            }
            let f = found, l = logged
            await self?.ui {
                self?.cliPath = f
                self?.cliLoggedIn = l
                self?.cliChecking = false
            }
        }
    }

    private static func runQuick(_ exe: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = cliEnvironment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let deadline = Date().addingTimeInterval(15)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return "" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Otvori Terminal i pokreni komande (instalacija / prijava)
    private func runInTerminal(_ script: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KodBlok-Claude-\(UUID().uuidString.prefix(6)).command")
        let body = "#!/bin/zsh\nexport PATH=\"\(Self.extraPath.joined(separator: ":")):$PATH\"\nclear\n" + script + "\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }

    func installCLI() {
        runInTerminal("""
        echo "Instaliram Claude Code (zvanični Anthropic program)..."
        echo
        curl -fsSL https://claude.ai/install.sh | bash
        echo
        echo "Sada se prijavi svojim Claude nalogom (otvoriće se pretraživač)."
        echo
        claude auth login --claudeai
        echo
        echo "Gotovo! Vrati se u KodBlok i klikni 'Proveri ponovo'. Ovaj prozor možeš da zatvoriš."
        """)
    }

    func loginCLI() {
        let exe = cliPath ?? "claude"
        runInTerminal("""
        echo "Prijava na Claude nalog (otvoriće se pretraživač)..."
        echo
        "\(exe)" auth login --claudeai
        echo
        echo "Gotovo! Vrati se u KodBlok i klikni 'Proveri ponovo'. Ovaj prozor možeš da zatvoriš."
        """)
    }

    private func streamCLI(cli: String, model: AssistantModelChoice, materials: String, prompt: String, resume: String?) async {
        var system = rules
        if !materials.isEmpty { system += "\n\nMATERIJALI SA PREDAVANJA:\n" + materials }
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                    "--tools", "", "--strict-mcp-config", "--model", model.rawValue,
                    "--system-prompt", system]
        if let resume { args += ["--resume", resume] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = args
        p.environment = Self.cliEnvironment
        p.currentDirectoryURL = Self.materialsDir
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = inp
        do { try p.run() } catch {
            await ui {
                self.failLast("Ne mogu da pokrenem Claude Code: \(error.localizedDescription)")
                self.isStreaming = false; self.task = nil
            }
            return
        }
        await ui { self.process = p }
        inp.fileHandleForWriting.write(Data(prompt.utf8))
        try? inp.fileHandleForWriting.close()

        var gotText = false
        var errorText: String?
        var finalText: String?
        do {
            for try await line in out.fileHandleForReading.bytes.lines {
                if Task.isCancelled { break }
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                if let sid = obj["session_id"] as? String, resume == nil || sid != resume {
                    await ui { self.cliSession = sid }
                }
                switch obj["type"] as? String {
                case "stream_event":
                    if let ev = obj["event"] as? [String: Any], ev["type"] as? String == "content_block_delta",
                       let d = ev["delta"] as? [String: Any], let t = d["text"] as? String {
                        gotText = true
                        await ui { self.appendToLast(t) }
                    }
                case "assistant":
                    if !gotText, let m = obj["message"] as? [String: Any], let c = m["content"] as? [[String: Any]] {
                        finalText = c.compactMap { $0["text"] as? String }.joined()
                    }
                case "result":
                    if obj["is_error"] as? Bool == true {
                        errorText = (obj["result"] as? String) ?? (obj["errors"] as? [String])?.joined(separator: "\n") ?? "Nepoznata greška"
                    } else if !gotText, finalText == nil {
                        finalText = obj["result"] as? String
                    }
                default: break
                }
            }
        } catch {}
        p.waitUntilExit()
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let cancelled = Task.isCancelled
        let status = p.terminationStatus
        let gotAny = gotText, fin = finalText, errText = errorText
        await ui {
            if !cancelled {
                if let t = fin, !gotAny, !t.isEmpty { self.appendToLast(t) }
                if let e = errText ?? ((status != 0 && !gotAny && fin == nil) ? (stderr.isEmpty ? "Claude Code je završio sa greškom \(status)." : stderr) : nil) {
                    self.failLast(Self.explainCLI(e))
                    if e.lowercased().contains("login") || e.lowercased().contains("logged") { self.cliLoggedIn = false }
                    if resume != nil, e.lowercased().contains("session") { self.cliSession = nil }
                }
            }
            self.process = nil
            self.isStreaming = false
            self.task = nil
        }
    }

    static func explainCLI(_ message: String) -> String {
        let m = message.lowercased()
        if m.contains("login") || m.contains("logged") || m.contains("api key") || m.contains("authenticat") {
            return "Claude Code nije prijavljen na tvoj Claude nalog. Klikni zupčanik u ovom panelu → 'Prijavi se'."
        }
        if m.contains("limit") || m.contains("usage") {
            return "Dostigao si limit svoje Claude pretplate za sada. Limit se resetuje za nekoliko sati — do tada možeš da koristiš claude.ai dugme ili API ključ.\n(\(message.trimmingCharacters(in: .whitespacesAndNewlines)))"
        }
        if m.contains("no conversation found") || m.contains("session") {
            return "Prethodni razgovor nije pronađen — klikni 'Novi razgovor' i pitaj ponovo."
        }
        return "Greška: " + message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func explain(status: Int, message: String) -> String {
        let m = message.lowercased()
        if status == 401 || m.contains("api key") || m.contains("authentication") {
            return "API ključ nije ispravan. Otvori podešavanje (zupčanik u ovom panelu) i nalepi ključ ponovo."
        }
        if m.contains("credit") || m.contains("balance") || m.contains("billing") {
            return "Na Claude nalogu nema dovoljno kredita. Dopuni na platform.claude.com → Billing."
        }
        if status == 429 { return "Previše zahteva u kratkom roku — sačekaj par sekundi i pokušaj ponovo." }
        if status == 529 || m.contains("overloaded") { return "Claude je trenutno preopterećen — pokušaj ponovo za trenutak." }
        return "Greška (\(status)): \(message)"
    }

    // MARK: Besplatna opcija: otvori pitanje na claude.ai (koristi tvoju pretplatu)

    func openInClaudeAI(_ question: String, context: String?) {
        var text = question
        if let context, !context.isEmpty { text = question + "\n\n" + context }
        if text.count > 6000 { text = String(text.prefix(6000)) + "\n…" }
        var comps = URLComponents(string: "https://claude.ai/new")!
        comps.queryItems = [URLQueryItem(name: "q", value: text)]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }
}
