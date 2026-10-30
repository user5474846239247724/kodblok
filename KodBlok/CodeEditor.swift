import SwiftUI
import AppKit

// MARK: - Editor (Scintilla-stil kao u Code::Blocks-u)

final class CBTextView: NSTextView {
    var errorLines: Set<Int> = [] { didSet { if errorLines != oldValue { needsDisplay = true } } }
    var highlightCaretLine = true
    var onComplete: (() -> Void)?
    var onHover: ((NSPoint?) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = hoverArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        hoverArea = a
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHover?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        onHover?(nil)
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        onHover?(nil)
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        onHover?(nil)
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control),
           event.charactersIgnoringModifiers == " " {
            onComplete?()
            return
        }
        super.keyDown(with: event)
    }

    /// Esc (i ⌃Space) ručno otvara listu za dopunjavanje
    override func complete(_ sender: Any?) {
        onComplete?()
    }

    func lineFragmentRect(forLine line: Int) -> NSRect? {
        guard let lm = layoutManager else { return nil }
        let ns = string as NSString
        var current = 1
        var loc = 0
        while current < line && loc < ns.length {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(r)
            current += 1
        }
        if current != line { return nil }
        return lineRect(forCharIndex: loc, lm: lm, ns: ns)
    }

    private func lineRect(forCharIndex idx: Int, lm: NSLayoutManager, ns: NSString) -> NSRect {
        var rect: NSRect
        if ns.length == 0 || (idx >= ns.length && ns.character(at: ns.length - 1) == 10) {
            rect = lm.extraLineFragmentRect
            if rect.height == 0 {
                let h = lm.defaultLineHeight(for: font ?? .systemFont(ofSize: 13))
                rect = NSRect(x: 0, y: 0, width: bounds.width, height: h)
            }
        } else {
            let glyph = lm.glyphIndexForCharacter(at: min(idx, ns.length - 1))
            rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        rect.origin.x = 0
        rect.size.width = max(bounds.width, rect.width)
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager else { return }
        let ns = string as NSString
        if highlightCaretLine {
            let sel = selectedRange()
            let r = lineRect(forCharIndex: sel.location, lm: lm, ns: ns)
            if r.intersects(rect) {
                NSColor(srgbRed: 1.0, green: 1.0, blue: 0.80, alpha: 1).setFill()
                r.fill()
            }
        }
        if !errorLines.isEmpty {
            NSColor(srgbRed: 1.0, green: 0.80, blue: 0.80, alpha: 1).setFill()
            for line in errorLines {
                if let r = lineFragmentRect(forLine: line), r.intersects(rect) { r.fill() }
            }
        }
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }
}

struct CodeEditor: NSViewRepresentable {
    @ObservedObject var doc: OpenDocument
    var jump: JumpRequest?
    var errorLines: Set<Int>
    var fontSize: CGFloat
    var tabWidth: Int
    var isC: Bool = false
    var userDocs: () -> (items: [DocItem], fields: [DocItem]) = { ([], []) }
    var onCaret: (CaretInfo) -> Void
    var onFocus: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.hoverTimer?.invalidate()
        coordinator.completion.hide()
        coordinator.hover.hide()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .white

        let tv = CBTextView(frame: .zero)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.backgroundColor = .white
        tv.drawsBackground = true
        tv.textColor = .black
        tv.insertionPointColor = .black
        tv.selectedTextAttributes = [.backgroundColor: NSColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1)]
        tv.textContainerInset = NSSize(width: 2, height: 2)
        let font = NSFont(name: "Menlo", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.font = font
        let ps = NSMutableParagraphStyle()
        ps.defaultTabInterval = (String(repeating: " ", count: tabWidth) as NSString).size(withAttributes: [.font: font]).width
        ps.tabStops = []
        tv.defaultParagraphStyle = ps
        tv.typingAttributes = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: ps]
        tv.string = doc.text
        tv.delegate = context.coordinator
        scroll.documentView = tv
        context.coordinator.textView = tv
        let coord = context.coordinator
        tv.onComplete = { [weak coord] in coord?.updateCompletion(auto: false) }
        tv.onHover = { [weak coord] p in coord?.hoverMoved(p) }
        coord.completion.onPick = { [weak coord] i in coord?.accept(i) }

        let ruler = LineNumberRuler(textView: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.ruler = ruler
        // macOS 14+: pogledi po defaultu ne seku crtanje na svojim granicama,
        // pa bi linija margine "procurela" preko toolbar-a.
        scroll.clipsToBounds = true
        scroll.contentView.clipsToBounds = true
        ruler.clipsToBounds = true
        tv.clipsToBounds = true

        Highlighter.highlight(tv)
        tv.errorLines = errorLines
        ruler.errorLines = errorLines
        onFocus(tv)
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            if tv.selectedRange().location == 0 { tv.setSelectedRange(NSRange(location: 0, length: 0)) }
            context.coordinator.reportCaret()
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        if tv.string != doc.text && !context.coordinator.isEditing {
            tv.string = doc.text
            Highlighter.highlight(tv)
            context.coordinator.ruler?.needsDisplay = true
        }
        if tv.errorLines != errorLines {
            tv.errorLines = errorLines
            context.coordinator.ruler?.errorLines = errorLines
        }
        if let j = jump, j.url == doc.url, j.token != context.coordinator.lastJump {
            context.coordinator.lastJump = j.token
            DispatchQueue.main.async { context.coordinator.goTo(line: j.line) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: CBTextView?
        weak var ruler: LineNumberRuler?
        var lastJump: UUID?
        var isEditing = false
        var suppress = false
        let completion = CompletionController()
        let hover = HoverController()
        var hoverTimer: Timer?
        var hoverWordRange = NSRange(location: NSNotFound, length: 0)
        var lastTyped: String?
        var completing = false

        init(_ parent: CodeEditor) { self.parent = parent }

        var indentUnit: String { String(repeating: " ", count: parent.tabWidth) }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            isEditing = true
            parent.doc.text = tv.string
            if !parent.doc.dirty { parent.doc.dirty = true }
            isEditing = false
            Highlighter.highlight(tv)
            ruler?.needsDisplay = true
            updateBraceMatch()

            let typed = lastTyped
            lastTyped = nil
            if completing { return }
            if completion.isVisible {
                updateCompletion(auto: true)
            } else if let t = typed, t.count == 1, let ch = t.utf16.first,
                      Self.isIdent(ch) || ch == 46 || ch == 62 || ch == 60 || ch == 34 || ch == 35 {
                updateCompletion(auto: true)
            }
        }

        // MARK: Dopunjavanje koda (code completion)

        static func isIdent(_ c: unichar) -> Bool {
            (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
        }

        static let includeRe = try! NSRegularExpression(pattern: #"^\s*#\s*include\s*[<"]([\w./+-]*)$"#)
        static let directiveRe = try! NSRegularExpression(pattern: #"^\s*#\s*(\w*)$"#)

        func inStringOrComment(_ tv: NSTextView, _ idx: Int) -> Bool {
            guard let storage = tv.textStorage, idx >= 0, idx < storage.length else { return false }
            guard let color = storage.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor else { return false }
            return color == Highlighter.cString || color == Highlighter.cComment || color == Highlighter.cChar
        }

        func updateCompletion(auto: Bool) {
            guard let tv = textView else { return }
            let defaults = UserDefaults.standard
            if auto && !completion.isVisible && (defaults.object(forKey: "ccAuto") as? Bool ?? true) == false { return }
            let minChars = max(1, defaults.object(forKey: "ccChars") as? Int ?? 3)
            let sel = tv.selectedRange()
            guard sel.length == 0 else { completion.hide(); return }
            let ns = tv.string as NSString
            let caret = sel.location
            let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
            let lineBefore = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
            let lb = lineBefore as NSString
            var start = caret
            while start > lineStart, Self.isIdent(ns.character(at: start - 1)) { start -= 1 }
            let prefix = ns.substring(with: NSRange(location: start, length: caret - start))
            let isC = parent.isC
            var items: [DocItem] = []

            if let m = Self.includeRe.firstMatch(in: lineBefore, range: NSRange(location: 0, length: lb.length)) {
                let partial = lb.substring(with: m.range(at: 1))
                start = caret - (partial as NSString).length
                items = CodeDocs.headers.filter {
                    (!isC || $0.lang == .c) && (partial.isEmpty || $0.name.lowercased().hasPrefix(partial.lowercased()))
                }
            } else if let m = Self.directiveRe.firstMatch(in: lineBefore, range: NSRange(location: 0, length: lb.length)) {
                let partial = lb.substring(with: m.range(at: 1))
                items = CodeDocs.directives.filter { partial.isEmpty || $0.name.hasPrefix(partial) }
            } else {
                if inStringOrComment(tv, caret - 1) { completion.hide(); return }
                let c1: unichar = start > 0 ? ns.character(at: start - 1) : 0
                let c2: unichar = start > 1 ? ns.character(at: start - 2) : 0
                var member = c1 == 46 || (c1 == 62 && c2 == 45)
                if c1 == 46 && c2 >= 48 && c2 <= 57 { member = false }
                if member {
                    let pool = parent.userDocs().fields + (isC ? [] : CodeDocs.members)
                    items = CodeDocs.rank(pool, prefix: prefix)
                } else {
                    if prefix.isEmpty && auto { completion.hide(); return }
                    if auto && prefix.count < minChars { completion.hide(); return }
                    if let f = prefix.utf16.first, f >= 48 && f <= 57 { completion.hide(); return }
                    items = CodeDocs.rank(parent.userDocs().items + CodeDocs.base(isC: isC), prefix: prefix)
                }
            }
            if items.isEmpty || (auto && items.count == 1 && items[0].name == prefix) {
                completion.hide()
                return
            }
            hover.hide()
            completion.show(items, start: start, in: tv)
        }

        func accept(_ i: Int) {
            guard let tv = textView, i < completion.model.items.count else { return }
            let it = completion.model.items[i]
            let ns = tv.string as NSString
            let caret = tv.selectedRange().location
            var end = caret
            while end < ns.length, Self.isIdent(ns.character(at: end)) || (it.kind == .header && [46, 47].contains(ns.character(at: end))) {
                end += 1
            }
            let start = min(completion.prefixStart, caret)
            let range = NSRange(location: start, length: end - start)
            var text = it.name
            var caretOffset = (text as NSString).length
            let after: unichar? = end < ns.length ? ns.character(at: end) : nil
            switch it.kind {
            case _ where it.isCallable:
                if after != 40 {
                    text += "()"
                    caretOffset = (it.name as NSString).length + (it.hasParams ? 1 : 2)
                }
            case .header:
                let open: unichar = start > 0 ? ns.character(at: start - 1) : 60
                let close = open == 34 ? "\"" : ">"
                if after != 62 && after != 34 { text += close }
                caretOffset = (text as NSString).length
            case .directive:
                text += it.name == "include" ? " <" : " "
                caretOffset = (text as NSString).length
            default:
                break
            }
            completing = true
            tv.insertText(text, replacementRange: range)
            completing = false
            tv.setSelectedRange(NSRange(location: start + caretOffset, length: 0))
            completion.hide()
            if it.kind == .directive && it.name == "include" { updateCompletion(auto: false) }
        }

        // MARK: Oblačić sa opisom na prelazak mišem

        func hoverMoved(_ p: NSPoint?) {
            hoverTimer?.invalidate()
            hoverTimer = nil
            guard let p, let tv = textView, (UserDefaults.standard.object(forKey: "ccHover") as? Bool ?? true),
                  !completion.isVisible, let r = wordRange(at: p, in: tv) else {
                hover.hide()
                hoverWordRange.location = NSNotFound
                return
            }
            if NSEqualRanges(r, hoverWordRange) && hover.isVisible { return }
            hover.hide()
            hoverWordRange = r
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.showHover(r)
            }
        }

        private func wordRange(at p: NSPoint, in tv: NSTextView) -> NSRange? {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
            let ns = tv.string as NSString
            guard ns.length > 0 else { return nil }
            let pt = NSPoint(x: p.x - tv.textContainerOrigin.x, y: p.y - tv.textContainerOrigin.y)
            var frac: CGFloat = 0
            let g = lm.glyphIndex(for: pt, in: tc, fractionOfDistanceThroughGlyph: &frac)
            guard g < lm.numberOfGlyphs else { return nil }
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
            guard rect.insetBy(dx: -1, dy: 0).contains(pt) else { return nil }
            let idx = lm.characterIndexForGlyph(at: g)
            guard idx < ns.length, Self.isIdent(ns.character(at: idx)) else { return nil }
            var s = idx, e = idx
            while s > 0, Self.isIdent(ns.character(at: s - 1)) { s -= 1 }
            while e < ns.length, Self.isIdent(ns.character(at: e)) { e += 1 }
            let first = ns.character(at: s)
            if first >= 48 && first <= 57 { return nil }
            return NSRange(location: s, length: e - s)
        }

        private func showHover(_ r: NSRange) {
            guard let tv = textView, tv.window?.isKeyWindow == true else { return }
            let ns = tv.string as NSString
            guard NSMaxRange(r) <= ns.length, !inStringOrComment(tv, r.location) else { return }
            let word = ns.substring(with: r)
            let isMember = r.location > 0 && ns.character(at: r.location - 1) == 46
            let docs = parent.userDocs()
            var item: DocItem?
            if isMember {
                item = docs.fields.first { $0.name == word } ?? (parent.isC ? nil : CodeDocs.members.first { $0.name == word })
            }
            if item == nil { item = docs.items.first { $0.name == word && ($0.kind == .userFunction || $0.kind == .macro || $0.kind == .type) } }
            if item == nil, let lib = CodeDocs.byName[word], !(parent.isC && lib.lang == .cpp) { item = lib }
            if item == nil { item = docs.items.first { $0.name == word } }
            guard let item else { return }
            let rect = tv.firstRect(forCharacterRange: r, actualRange: nil)
            hover.show(item, at: rect, in: tv)
        }

        func textDidBeginEditing(_ notification: Notification) {
            if let tv = textView { parent.onFocus(tv) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if completion.isVisible, let tv = textView {
                let sel = tv.selectedRange()
                let ns = tv.string as NSString
                let lineStart = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0)).location
                if sel.length > 0 || sel.location < completion.prefixStart || lineStart > completion.prefixStart {
                    completion.hide()
                }
            }
            reportCaret()
            updateBraceMatch()
            textView?.needsDisplay = true
            ruler?.needsDisplay = true
        }

        func reportCaret() {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            let before = ns.substring(to: loc)
            let line = before.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let lastNL = before.lastIndex(of: "\n")
            let col = lastNL.map { before.distance(from: $0, to: before.endIndex) } ?? (before.count + 1)
            parent.onCaret(CaretInfo(line: line, col: col, pos: loc))
        }

        // Isticanje parnih zagrada
        func updateBraceMatch() {
            guard let tv = textView, let lm = tv.layoutManager else { return }
            let ns = tv.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            let sel = tv.selectedRange()
            guard sel.length == 0, ns.length > 0 else { return }
            let open: [unichar: unichar] = [40: 41, 91: 93, 123: 125]   // ( [ {
            let close: [unichar: unichar] = [41: 40, 93: 91, 125: 123]
            for idx in [sel.location - 1, sel.location] where idx >= 0 && idx < ns.length {
                let c = ns.character(at: idx)
                var match: Int?
                if let target = open[c] {
                    var depth = 0
                    var i = idx
                    let limit = min(ns.length, idx + 50000)
                    while i < limit {
                        let ch = ns.character(at: i)
                        if ch == c { depth += 1 } else if ch == target { depth -= 1; if depth == 0 { match = i; break } }
                        i += 1
                    }
                } else if let target = close[c] {
                    var depth = 0
                    var i = idx
                    let limit = max(0, idx - 50000)
                    while i >= limit {
                        let ch = ns.character(at: i)
                        if ch == c { depth += 1 } else if ch == target { depth -= 1; if depth == 0 { match = i; break } }
                        i -= 1
                    }
                } else {
                    continue
                }
                if let m = match {
                    for r in [NSRange(location: idx, length: 1), NSRange(location: m, length: 1)] {
                        lm.addTemporaryAttributes([.backgroundColor: NSColor(srgbRed: 0.75, green: 0.85, blue: 1.0, alpha: 1),
                                                   .foregroundColor: NSColor.red], forCharacterRange: r)
                    }
                } else {
                    lm.addTemporaryAttributes([.backgroundColor: NSColor(srgbRed: 1.0, green: 0.6, blue: 0.6, alpha: 1)],
                                              forCharacterRange: NSRange(location: idx, length: 1))
                }
                return
            }
        }

        private func insert(_ tv: NSTextView, _ text: String, range: NSRange, caretOffset: Int) {
            suppress = true
            tv.insertText(text, replacementRange: range)
            suppress = false
            tv.setSelectedRange(NSRange(location: range.location + caretOffset, length: 0))
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            if !suppress && !completing { lastTyped = text }
            guard !suppress, let text, range.length == 0 else { return true }
            let ns = textView.string as NSString
            let next: unichar? = range.location < ns.length ? ns.character(at: range.location) : nil
            let prev: unichar? = range.location > 0 ? ns.character(at: range.location - 1) : nil
            let nextIsFree = next == nil || [32, 9, 10, 41, 93, 125, 59, 44].contains(next!)

            switch text {
            case "(":
                if nextIsFree { insert(textView, "()", range: range, caretOffset: 1); return false }
            case "[":
                if nextIsFree { insert(textView, "[]", range: range, caretOffset: 1); return false }
            case ")", "]":
                if let n = next, n == (text == ")" ? 41 : 93) {
                    textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                    return false
                }
            case "\"", "'":
                let q: unichar = text == "\"" ? 34 : 39
                if let n = next, n == q {
                    textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                    return false
                }
                let prevIsWord = prev.map { CharacterSet.alphanumerics.contains(UnicodeScalar($0) ?? " ") || $0 == 92 } ?? false
                if nextIsFree && !prevIsWord {
                    insert(textView, text + text, range: range, caretOffset: 1)
                    return false
                }
            case "}":
                // vrati uvlačenje kad se } otkuca na praznoj liniji
                let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let before = ns.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
                let unit = indentUnit
                if !before.isEmpty, before.allSatisfy({ $0 == " " }), before.count >= unit.count {
                    let r = NSRange(location: lineRange.location, length: range.location - lineRange.location)
                    insert(textView, String(before.dropLast(unit.count)) + "}", range: r, caretOffset: before.count - unit.count + 1)
                    return false
                }
            default:
                break
            }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if completion.isVisible {
                switch selector {
                case #selector(NSResponder.moveUp(_:)):
                    completion.move(-1); return true
                case #selector(NSResponder.moveDown(_:)):
                    completion.move(1); return true
                case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
                    completion.move(-8); return true
                case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
                    completion.move(8); return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    accept(completion.model.selected); return true
                case #selector(NSResponder.cancelOperation(_:)):
                    completion.hide(); return true
                case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)),
                     #selector(NSResponder.moveToBeginningOfLine(_:)), #selector(NSResponder.moveToEndOfLine(_:)):
                    completion.hide()
                default:
                    break
                }
            }
            hover.hide()
            let unit = indentUnit
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let ns = textView.string as NSString
                let sel = textView.selectedRange()
                let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
                let before = ns.substring(with: NSRange(location: lineRange.location, length: sel.location - lineRange.location))
                var lineEnd = NSMaxRange(lineRange)
                if lineEnd > lineRange.location, lineEnd <= ns.length, ns.character(at: lineEnd - 1) == 10 { lineEnd -= 1 }
                let afterLoc = NSMaxRange(sel)
                let after = afterLoc < lineEnd ? ns.substring(with: NSRange(location: afterLoc, length: lineEnd - afterLoc)) : ""
                let indent = String(before.prefix { $0 == " " || $0 == "\t" })
                let trimmed = before.trimmingCharacters(in: .whitespaces)
                if trimmed.hasSuffix("{") {
                    let inner = indent + unit
                    if after.trimmingCharacters(in: .whitespaces).hasPrefix("}") {
                        let s = "\n" + inner + "\n" + indent
                        let r = NSRange(location: sel.location, length: sel.length + (after.count - after.drop { $0 == " " }.count))
                        insert(textView, s, range: r, caretOffset: 1 + inner.count)
                        return true
                    }
                    let opens = textView.string.filter { $0 == "{" }.count
                    let closes = textView.string.filter { $0 == "}" }.count
                    if opens > closes {
                        insert(textView, "\n" + inner + "\n" + indent + "}", range: sel, caretOffset: 1 + inner.count)
                        return true
                    }
                    insert(textView, "\n" + inner, range: sel, caretOffset: 1 + inner.count)
                    return true
                }
                insert(textView, "\n" + indent, range: sel, caretOffset: 1 + indent.count)
                return true
            }
            if selector == #selector(NSResponder.insertTab(_:)) {
                let sel = textView.selectedRange()
                let ns = textView.string as NSString
                if sel.length > 0, ns.substring(with: sel).contains("\n") {
                    shiftLines(textView, indent: true)
                } else {
                    insert(textView, unit, range: sel, caretOffset: unit.count)
                }
                return true
            }
            if selector == #selector(NSResponder.insertBacktab(_:)) {
                shiftLines(textView, indent: false)
                return true
            }
            return false
        }

        private func shiftLines(_ tv: NSTextView, indent: Bool) {
            let ns = tv.string as NSString
            let range = ns.lineRange(for: tv.selectedRange())
            let block = ns.substring(with: range)
            var lines = block.components(separatedBy: "\n")
            let trailing = block.hasSuffix("\n")
            if trailing { lines.removeLast() }
            let unit = indentUnit
            let out = lines.map { line -> String in
                if indent { return line.isEmpty ? line : unit + line }
                var l = Substring(line)
                var n = 0
                while n < unit.count, let f = l.first, f == " " { l = l.dropFirst(); n += 1 }
                if n == 0, l.first == "\t" { l = l.dropFirst() }
                return String(l)
            }.joined(separator: "\n") + (trailing ? "\n" : "")
            if tv.shouldChangeText(in: range, replacementString: out) {
                suppress = true
                tv.replaceCharacters(in: range, with: out)
                suppress = false
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: range.location, length: (out as NSString).length))
            }
        }

        func goTo(line target: Int) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            var line = 1
            var loc = 0
            while line < target && loc < ns.length {
                let r = ns.lineRange(for: NSRange(location: loc, length: 0))
                loc = NSMaxRange(r)
                line += 1
            }
            let r = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: r.location, length: 0))
            tv.scrollRangeToVisible(r)
            var vis = r
            if vis.length > 0, ns.character(at: NSMaxRange(vis) - 1) == 10 { vis.length -= 1 }
            if vis.length > 0 { tv.showFindIndicator(for: vis) }
        }
    }
}

// MARK: - Boje sintakse (podrazumevana Code::Blocks tema)

enum Highlighter {
    static let keywords = [
        "alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor", "bool", "break", "case", "catch",
        "char", "char16_t", "char32_t", "class", "compl", "const", "constexpr", "const_cast", "continue", "decltype",
        "default", "delete", "do", "double", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false",
        "float", "for", "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept",
        "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private", "protected", "public", "register",
        "reinterpret_cast", "return", "short", "signed", "sizeof", "static", "static_assert", "static_cast",
        "struct", "switch", "template", "this", "thread_local", "throw", "true", "try", "typedef", "typeid",
        "typename", "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq",
        "override", "final", "NULL"
    ]

    static let keywordRe = try! NSRegularExpression(pattern: "\\b(" + keywords.joined(separator: "|") + ")\\b")
    static let operatorRe = try! NSRegularExpression(pattern: #"[-+*/%=<>!&|^~?:;,.(){}\[\]]"#)
    static let numberRe = try! NSRegularExpression(pattern: #"\b(0[xX][0-9a-fA-F]+|\d+(\.\d*)?([eE][+-]?\d+)?)[uUlLfF]*\b"#)
    static let preprocRe = try! NSRegularExpression(pattern: #"^[ \t]*#.*$"#, options: [.anchorsMatchLines])
    static let stringRe = try! NSRegularExpression(pattern: #""(\\.|[^"\\\n])*"?"#)
    static let charRe = try! NSRegularExpression(pattern: #"'(\\.|[^'\\\n])*'?"#)
    static let commentRe = try! NSRegularExpression(pattern: #"//[^\n]*|/\*[\s\S]*?(\*/|$(?![\s\S]))"#)

    static let cText = NSColor.black
    static let cKeyword = NSColor(srgbRed: 0, green: 0, blue: 0.627, alpha: 1)
    static let cString = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    static let cChar = NSColor(srgbRed: 0.878, green: 0.627, blue: 0, alpha: 1)
    static let cComment = NSColor(srgbRed: 0.627, green: 0.627, blue: 0.627, alpha: 1)
    static let cNumber = NSColor(srgbRed: 0.941, green: 0, blue: 0.941, alpha: 1)
    static let cPreproc = NSColor(srgbRed: 0, green: 0.627, blue: 0, alpha: 1)
    static let cOperator = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

    static func highlight(_ tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        let font = tv.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        storage.beginEditing()
        var base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: cText]
        if let ps = tv.defaultParagraphStyle { base[.paragraphStyle] = ps }
        storage.setAttributes(base, range: full)
        func paint(_ re: NSRegularExpression, _ color: NSColor, _ f: NSFont? = nil) {
            for m in re.matches(in: text, range: full) {
                storage.addAttribute(.foregroundColor, value: color, range: m.range)
                if let f { storage.addAttribute(.font, value: f, range: m.range) }
            }
        }
        paint(operatorRe, cOperator)
        paint(numberRe, cNumber)
        paint(keywordRe, cKeyword, bold)
        paint(stringRe, cString, font)
        paint(charRe, cChar, font)
        paint(preprocRe, cPreproc, font)
        paint(commentRe, cComment, font)
        storage.endEditing()
        var typing = base
        typing[.foregroundColor] = cText
        tv.typingAttributes = typing
    }
}

// MARK: - Margina sa brojevima linija

final class LineNumberRuler: NSRulerView {
    weak var textView: NSTextView?
    var errorLines: Set<Int> = [] { didSet { needsDisplay = true } }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc func refresh() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        let area = rect.intersection(bounds)
        NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1).setFill()
        area.fill()
        // tanka margina za "folding" kao u Scintilla editoru
        NSColor(srgbRed: 0.98, green: 0.98, blue: 0.98, alpha: 1).setFill()
        NSRect(x: bounds.maxX - 12, y: area.minY, width: 12, height: area.height).fill()
        NSColor(srgbRed: 0.80, green: 0.80, blue: 0.80, alpha: 1).setFill()
        NSRect(x: bounds.maxX - 13, y: area.minY, width: 1, height: area.height).fill()

        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let ns = tv.string as NSString
        let fontSize = max(9, (tv.font?.pointSize ?? 13) - 2)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.45, green: 0.45, blue: 0.45, alpha: 1)
        ]
        let origin = convert(NSPoint.zero, from: tv)
        let insetY = tv.textContainerOrigin.y
        let numRight = ruleThickness - 16

        func draw(_ n: Int, _ lineRect: NSRect) {
            let y = origin.y + insetY + lineRect.minY
            if errorLines.contains(n) {
                NSColor(srgbRed: 0.85, green: 0.1, blue: 0.1, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 3, y: y + (lineRect.height - 9) / 2, width: 9, height: 9), xRadius: 2, yRadius: 2).fill()
            }
            let s = "\(n)" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: numRight - size.width, y: y + (lineRect.height - size.height) / 2), withAttributes: attrs)
        }

        if ns.length == 0 {
            let h = lm.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 13))
            draw(1, NSRect(x: 0, y: 0, width: 10, height: h))
            return
        }

        let glyphRange = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var lineNumber = 1
        var idx = 0
        while idx < charRange.location {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: idx, length: charRange.location - idx))
            if r.location == NSNotFound { break }
            lineNumber += 1
            idx = r.location + 1
        }
        var charIndex = charRange.location
        let end = NSMaxRange(charRange)
        repeat {
            let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphIdx = lm.glyphIndexForCharacter(at: lineRange.location)
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            draw(lineNumber, lineRect)
            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
        } while charIndex < end
        if end == ns.length, ns.character(at: ns.length - 1) == 10 {
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 { draw(lineNumber, extra) }
        }
    }
}
