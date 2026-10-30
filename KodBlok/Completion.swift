import SwiftUI
import AppKit

// MARK: - Plutajući panel koji ne krade fokus editoru

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func make() -> FloatingPanel {
        let p = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = true
        p.becomesKeyOnlyIfNeeded = true
        p.appearance = NSAppearance(named: .aqua)
        p.isReleasedWhenClosed = false
        return p
    }
}

struct KindBadge: View {
    let kind: DocKind
    var color: Color {
        switch kind {
        case .function: return Color(red: 0.15, green: 0.4, blue: 0.85)
        case .userFunction: return Color(red: 0.1, green: 0.6, blue: 0.25)
        case .keyword: return Color(red: 0.55, green: 0.2, blue: 0.7)
        case .type: return Color(red: 0.85, green: 0.5, blue: 0.1)
        case .object: return Color(red: 0.1, green: 0.55, blue: 0.6)
        case .member, .field: return Color(red: 0.3, green: 0.45, blue: 0.8)
        case .macro, .directive: return Color(white: 0.45)
        case .variable: return Color(red: 0.6, green: 0.35, blue: 0.2)
        case .header: return Color(red: 0.0, green: 0.55, blue: 0.0)
        }
    }
    var body: some View {
        Text(kind.badge)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(RoundedRectangle(cornerRadius: 3).fill(color))
    }
}

struct DocDetail: View {
    let item: DocItem
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.signature)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0, green: 0, blue: 0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.header)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.4))
            Text(item.summary)
                .font(.system(size: 12))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lista za dopunjavanje

final class CompletionModel: ObservableObject {
    @Published var items: [DocItem] = []
    @Published var selected = 0
}

struct CompletionView: View {
    @ObservedObject var model: CompletionModel
    let onPick: (Int) -> Void
    static let rowHeight: CGFloat = 20
    static let width: CGFloat = 470
    static let detailHeight: CGFloat = 92

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { i, it in
                            let sel = i == model.selected
                            HStack(spacing: 6) {
                                KindBadge(kind: it.kind)
                                Text(it.name)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(sel ? .white : .black)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(it.kind == .header || it.kind == .directive ? it.header : it.signature)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(sel ? Color.white.opacity(0.85) : Color(white: 0.45))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.horizontal, 6)
                            .frame(height: Self.rowHeight)
                            .background(sel ? Color.accentColor : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { onPick(i) } else { model.selected = i }
                            }
                            .id(it.id)
                        }
                    }
                }
                .onChange(of: model.selected) { _, s in
                    if s < model.items.count { proxy.scrollTo(model.items[s].id) }
                }
            }
            .frame(height: CGFloat(min(model.items.count, 8)) * Self.rowHeight)
            Rectangle().fill(Color(white: 0.8)).frame(height: 1)
            Group {
                if model.selected < model.items.count {
                    DocDetail(item: model.items[model.selected])
                }
            }
            .padding(8)
            .frame(width: Self.width, height: Self.detailHeight, alignment: .topLeading)
            .background(Color(red: 1, green: 1, blue: 0.9))
        }
        .frame(width: Self.width)
        .background(Color.white)
        .overlay(Rectangle().stroke(Color(white: 0.6), lineWidth: 1))
    }
}

final class CompletionController {
    let model = CompletionModel()
    private var panel: FloatingPanel?
    var prefixStart = 0
    var onPick: ((Int) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }
    var selectedItem: DocItem? {
        model.selected < model.items.count ? model.items[model.selected] : nil
    }

    func show(_ items: [DocItem], start: Int, in tv: NSTextView) {
        model.items = items
        model.selected = 0
        prefixStart = start
        if panel == nil {
            let p = FloatingPanel.make()
            p.contentView = NSHostingView(rootView: CompletionView(model: model, onPick: { [weak self] i in self?.onPick?(i) }))
            panel = p
        }
        guard let panel, let window = tv.window else { return }
        let height = CGFloat(min(items.count, 8)) * CompletionView.rowHeight + 1 + CompletionView.detailHeight
        let size = NSSize(width: CompletionView.width, height: height)
        panel.setContentSize(size)
        let caret = tv.firstRect(forCharacterRange: NSRange(location: start, length: 0), actualRange: nil)
        var origin = NSPoint(x: caret.minX - 26, y: caret.minY - height - 3)
        if let screen = window.screen?.visibleFrame {
            if origin.y < screen.minY { origin.y = caret.maxY + 3 }
            if origin.x + size.width > screen.maxX { origin.x = screen.maxX - size.width - 4 }
            origin.x = max(origin.x, screen.minX + 4)
        }
        panel.setFrameOrigin(origin)
        if !panel.isVisible {
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    func move(_ d: Int) {
        guard !model.items.isEmpty else { return }
        model.selected = max(0, min(model.items.count - 1, model.selected + d))
    }

    func hide() {
        guard let p = panel, p.isVisible else { return }
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
    }
}

// MARK: - Oblačić (tooltip) na prelazak mišem

struct HoverDocView: View {
    let item: DocItem
    static let width: CGFloat = 400
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            KindBadge(kind: item.kind)
            DocDetail(item: item)
        }
        .padding(8)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(red: 1, green: 1, blue: 0.88))
        .overlay(Rectangle().stroke(Color(white: 0.55), lineWidth: 1))
    }
}

final class HoverController {
    private var panel: FloatingPanel?
    private(set) var shownName: String?
    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ item: DocItem, at wordRect: NSRect, in tv: NSTextView) {
        let hosting = NSHostingView(rootView: HoverDocView(item: item))
        let size = hosting.fittingSize
        if panel == nil { panel = FloatingPanel.make() }
        guard let panel, let window = tv.window else { return }
        panel.contentView = hosting
        panel.setContentSize(size)
        var origin = NSPoint(x: wordRect.minX, y: wordRect.minY - size.height - 4)
        if let screen = window.screen?.visibleFrame {
            if origin.y < screen.minY { origin.y = wordRect.maxY + 4 }
            if origin.x + size.width > screen.maxX { origin.x = screen.maxX - size.width - 4 }
        }
        panel.setFrameOrigin(origin)
        if !panel.isVisible {
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
        shownName = item.name
    }

    func hide() {
        shownName = nil
        guard let p = panel, p.isVisible else { return }
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
    }
}
