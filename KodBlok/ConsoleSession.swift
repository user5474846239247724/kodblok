import AppKit
import Darwin

/// Crni konzolni prozor u kome radi pokrenut program (kao u Code::Blocks-u).
/// Program radi preko pseudo-terminala, pa printf/cout prikazuju tekst odmah, a cin/scanf čitaju sa tastature.
final class ConsoleWindowController: NSWindowController, NSWindowDelegate {
    let executable: URL
    let cwd: URL
    private let textView: TerminalTextView
    private var process: Process?
    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var startTime = Date()
    private let io = DispatchQueue(label: "kodblok.console.io")
    private var pending = Data()
    private(set) var finished = false

    var onExit: ((Int32, TimeInterval) -> Void)?
    var onClose: (() -> Void)?
    var isRunning: Bool { !finished && process != nil }

    static var cascadePoint = NSPoint.zero

    init(executable: URL, cwd: URL) {
        self.executable = executable
        self.cwd = cwd

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = executable.path
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = .black
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 360, height: 200)

        let scroll = NSScrollView(frame: win.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .black

        let tv = TerminalTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        tv.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        tv.backgroundColor = .black
        tv.drawsBackground = true
        tv.isRichText = false
        tv.allowsUndo = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.textContainerInset = NSSize(width: 6, height: 6)
        let font = NSFont(name: "Menlo", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let fg = NSColor(white: 0.80, alpha: 1)
        tv.font = font
        tv.textColor = fg
        tv.insertionPointColor = fg
        tv.termAttrs = [.font: font, .foregroundColor: fg]
        tv.typingAttributes = tv.termAttrs
        tv.selectedTextAttributes = [.backgroundColor: NSColor(white: 0.35, alpha: 1), .foregroundColor: NSColor.white]
        scroll.documentView = tv
        scroll.clipsToBounds = true
        tv.clipsToBounds = true
        win.contentView = scroll
        self.textView = tv

        super.init(window: win)
        win.delegate = self
        tv.console = self

        if Self.cascadePoint == .zero {
            win.center()
            Self.cascadePoint = NSPoint(x: win.frame.minX, y: win.frame.maxY)
        }
        Self.cascadePoint = win.cascadeTopLeft(from: Self.cascadePoint)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func start() {
        var master: Int32 = 0
        var slave: Int32 = 0
        var size = winsize(ws_row: 25, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            textView.appendOutput("Failed to open a console for the program.\n")
            processEnded(-1)
            return
        }
        var t = termios()
        tcgetattr(slave, &t)
        t.c_lflag &= ~tcflag_t(ECHO | ECHOE | ECHOK | ECHONL)
        t.c_oflag &= ~tcflag_t(ONLCR)
        tcsetattr(slave, TCSANOW, &t)

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        let p = Process()
        p.executableURL = executable
        p.currentDirectoryURL = cwd
        p.standardInput = slaveHandle
        p.standardOutput = slaveHandle
        p.standardError = slaveHandle
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        p.environment = env

        masterFD = master
        let src = DispatchSource.makeReadSource(fileDescriptor: master, queue: io)
        src.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(master, &buf, buf.count)
            if n > 0 {
                self?.received(Data(buf[0..<n]))
            } else {
                self?.readSource?.cancel()
            }
        }
        src.setCancelHandler {
            Darwin.close(master)
        }
        readSource = src
        src.resume()

        p.terminationHandler = { [weak self] proc in
            let code: Int32 = proc.terminationReason == .uncaughtSignal ? 128 + proc.terminationStatus : proc.terminationStatus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.processEnded(code)
            }
        }

        startTime = Date()
        do {
            try p.run()
            process = p
        } catch {
            Darwin.close(slave)
            textView.appendOutput("Failed to execute \(executable.path)\n\(error.localizedDescription)\n")
            processEnded(-1)
            return
        }
        Darwin.close(slave)
        window?.makeFirstResponder(textView)
    }

    /// Prima bajtove sa izlaza programa (na io redu) i šalje ih u prozor kao UTF-8 tekst.
    private func received(_ data: Data) {
        pending.append(data)
        var cut = pending.count
        // Ne seci UTF-8 karakter na pola
        while cut > 0, cut > pending.count - 4 {
            if String(data: pending.prefix(cut), encoding: .utf8) != nil { break }
            cut -= 1
        }
        if cut == 0 || String(data: pending.prefix(cut), encoding: .utf8) == nil {
            cut = pending.count
        }
        let chunk = pending.prefix(cut)
        pending = Data(pending.dropFirst(cut))
        let s = String(decoding: chunk, as: UTF8.self).replacingOccurrences(of: "\r", with: "")
        DispatchQueue.main.async { [weak self] in
            self?.textView.appendOutput(s)
        }
    }

    private func processEnded(_ code: Int32) {
        guard !finished else { return }
        let secs = Date().timeIntervalSince(startTime)
        io.sync {
            if !pending.isEmpty {
                let s = String(decoding: pending, as: UTF8.self)
                pending = Data()
                DispatchQueue.main.async { [weak self] in self?.textView.appendOutput(s) }
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readSource?.cancel()
            self.readSource = nil
            self.masterFD = -1
            self.finished = true
            self.process = nil
            let hex = String(format: "0x%X", UInt32(bitPattern: code))
            self.textView.appendOutput(String(format: "\nProcess returned %d (%@)   execution time : %.3f s\nPress any key to continue.\n", code, hex, secs))
            self.onExit?(code, secs)
        }
    }

    func send(_ text: String) {
        guard isRunning, masterFD >= 0 else { return }
        let fd = masterFD
        let bytes = Array(text.utf8)
        io.async {
            bytes.withUnsafeBufferPointer { ptr in
                _ = Darwin.write(fd, ptr.baseAddress, ptr.count)
            }
        }
    }

    func sendEOF() {
        guard isRunning, masterFD >= 0 else { return }
        let fd = masterFD
        io.async {
            var eof: UInt8 = 4
            _ = Darwin.write(fd, &eof, 1)
        }
    }

    func interrupt() {
        guard let p = process, p.isRunning else { return }
        p.interrupt()
    }

    func kill() {
        guard let p = process, p.isRunning else { return }
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if p.isRunning { Darwin.kill(pid, SIGKILL) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        kill()
        onClose?()
    }
}

final class TerminalTextView: NSTextView {
    weak var console: ConsoleWindowController?
    var inputStart = 0
    var termAttrs: [NSAttributedString.Key: Any] = [:]

    func appendOutput(_ s: String) {
        guard let storage = textStorage, !s.isEmpty else { return }
        let at = min(inputStart, storage.length)
        storage.beginEditing()
        storage.insert(NSAttributedString(string: s, attributes: termAttrs), at: at)
        storage.endEditing()
        inputStart = at + (s as NSString).length
        setSelectedRange(NSRange(location: storage.length, length: 0))
        typingAttributes = termAttrs
        scrollToEndOfDocument(nil)
    }

    private func moveCaretToInput() {
        let len = (string as NSString).length
        if selectedRange().location < inputStart {
            setSelectedRange(NSRange(location: len, length: 0))
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let c = console else { super.keyDown(with: event); return }
        if c.finished {
            c.window?.performClose(nil)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control), let ch = event.charactersIgnoringModifiers?.lowercased() {
            if ch == "c" { c.interrupt(); return }
            if ch == "d" { c.sendEOF(); return }
        }
        if flags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        moveCaretToInput()
        typingAttributes = termAttrs
        super.keyDown(with: event)
    }

    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard let c = console, !c.finished else { return false }
        if range.location < inputStart { return false }
        return super.shouldChangeText(in: range, replacementString: replacementString)
    }

    override func insertNewline(_ sender: Any?) {
        guard let c = console, !c.finished else { return }
        let len = (string as NSString).length
        insertText("\n", replacementRange: NSRange(location: len, length: 0))
    }

    /// Svaka završena linija (do "\n") u delu za unos šalje se programu.
    override func didChangeText() {
        super.didChangeText()
        guard let c = console, !c.finished else { return }
        var ns = string as NSString
        while inputStart <= ns.length {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: inputStart, length: ns.length - inputStart))
            if r.location == NSNotFound { break }
            let line = ns.substring(with: NSRange(location: inputStart, length: r.location - inputStart + 1))
            inputStart = r.location + 1
            c.send(line)
            ns = string as NSString
        }
        typingAttributes = termAttrs
        scrollToEndOfDocument(nil)
    }

    override func paste(_ sender: Any?) {
        moveCaretToInput()
        pasteAsPlainText(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if let c = console, c.finished {
            super.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }
}
