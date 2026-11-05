import AppKit
import SwiftUI

/// The welcome tour: four short pages, each showing one idea on a miniature note.
/// Opens by itself until it has been closed once, and again from Settings or Help ▸ Welcome Tour.
struct OnboardingView: View {
    /// `UserDefaults` key set when the tour is closed, so quitting midway shows it again next launch.
    static let seenKey = "onboardingSeen"
    static let size = CGSize(width: 560, height: 500)

    var onDone: () -> Void

    @State private var page = 0
    @State private var movingForward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 4
    private var isLast: Bool { page == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            pageContent
                .id(page)
                .transition(pageTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(arrowKeys)
    }

    // MARK: - Pages

    @ViewBuilder private var pageContent: some View {
        switch page {
        case 0: welcomePage
        case 1: buttonsPage
        case 2: checklistPage
        default: shortcutsPage
        }
    }

    private var welcomePage: some View {
        PageLayout(title: "Welcome to Stackies",
                   subtitle: "Sticky notes that float on your desktop. Just type: your text, position and color are saved as you go.") {
            ZStack {
                MiniNote(color: .lavender) { MiniLine("Call Sam") }
                    .rotationEffect(.degrees(-8)).offset(x: -130, y: 14)
                MiniNote(color: .mint) { MiniLine("Book flights").padding(.leading, 52) }
                    .rotationEffect(.degrees(7)).offset(x: 130, y: 16)
                MiniNote(color: .yellow, width: 216) {
                    Text("Today").font(.system(size: 17, weight: .bold))
                    MiniCheck("Review pull requests", color: .yellow)
                    MiniCheck("Write the README", done: true, color: .yellow)
                    MiniCheck("Water the plants", color: .yellow)
                }
            }
            .frame(height: 230)
        }
    }

    private var buttonsPage: some View {
        PageLayout(title: "Everything's on the note",
                   subtitle: "Hover over a note and its buttons appear.") {
            MiniNote(color: .blue, width: 300, showsControls: true) {
                MiniLine("Ideas for the weekend")
            }
            .padding(.bottom, 4)
        } details: {
            FeatureRow(symbol: "plus", title: "New note", keys: ["⌘N"])
            FeatureRow(symbol: "circle.fill", title: "Change color", keys: ["⌘1–7"])
            FeatureRow(symbol: "pin", title: "Keep on top of other apps", keys: ["⌘P"])
            FeatureRow(symbol: tuckSymbol, title: "Tuck away to the screen edge", keys: ["⌘J"])
        }
    }

    private var checklistPage: some View {
        PageLayout(title: "Check things off, stay focused",
                   subtitle: "Turn any line into a task, then start a timer on it.") {
            MiniNote(color: .peach, width: 300, showsTimer: true) {
                MiniCheck("Draft the proposal", color: .peach, tag: "⏱1h40m")
                MiniCheck("Send it to the team", done: true, color: .peach)
            }
            .padding(.bottom, 4)
        } details: {
            FeatureRow(symbol: "checklist", title: "Make a checklist, or type - [ ]", keys: ["⌘L"])
            FeatureRow(symbol: "checkmark.circle", title: "Mark an item done", keys: ["⌘↩"])
            FeatureRow(symbol: "timer", title: "Start or pause a focus timer", keys: ["⌘T"])
        }
    }

    private var shortcutsPage: some View {
        PageLayout(title: "A few more shortcuts",
                   subtitle: "Every shortcut is also in the menu bar, so there's nothing to memorize.") {
            EmptyView()
        } details: {
            FeatureRow(symbol: "bold", title: "Bold, italic", keys: ["⌘B", "⌘I"])
            FeatureRow(symbol: "arrow.up.arrow.down", title: "Move an item up or down", keys: ["⌘↑", "⌘↓"])
            FeatureRow(symbol: "rectangle.stack", title: "Show all notes", keys: ["⇧⌘A"])
            FeatureRow(symbol: tuckSymbol, title: "Tuck all notes away", keys: ["⇧⌘J"])
            FeatureRow(symbol: "arrow.uturn.backward", title: "Reopen a closed note", keys: ["⇧⌘T"])
            FeatureRow(symbol: "archivebox", title: "Archive a finished note", keys: ["⌃⌘A"])
            FeatureRow(symbol: "magnifyingglass", title: "Browse the archive", keys: ["⌥⌘A"])
            FeatureRow(symbol: "gearshape", title: "Settings, and this tour", keys: ["⌘,"])
        }
    }

    private var tuckSymbol: String {
        TuckTab.side == .right ? "arrow.right.to.line" : "arrow.left.to.line"
    }

    // MARK: - Footer

    /// The buttons hold their positions from page to page, so Next never moves under the pointer.
    private var footer: some View {
        ZStack {
            PageDots(count: pageCount, current: page)
            HStack(spacing: 8) {
                if !isLast {
                    Button("Skip", action: onDone)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Close the tour")
                }
                Spacer()
                if page > 0 {
                    Button("Back") { go(to: page - 1) }
                        .tourButton(prominent: false)
                }
                Button(isLast ? "Get Started" : page == 0 ? "Take the Tour" : "Next") {
                    if isLast { onDone() } else { go(to: page + 1) }
                }
                .tourButton(prominent: true)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .padding(.top, 8)
    }

    /// ← and → flip pages, and Esc closes the tour from any page.
    private var arrowKeys: some View {
        Group {
            Button("", action: onDone)
                .keyboardShortcut(.cancelAction)
            Button("") { if page > 0 { go(to: page - 1) } }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { if !isLast { go(to: page + 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func go(to index: Int) {
        movingForward = index > page
        if reduceMotion {
            page = index
        } else {
            withAnimation(.smooth(duration: 0.28)) { page = index }
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: Edge = movingForward ? .trailing : .leading
        let removal: Edge = movingForward ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: insertion).combined(with: .opacity),
                           removal: .move(edge: removal).combined(with: .opacity))
    }
}

// MARK: - Layout

/// Title and subtitle on top, then the picture, then a glass panel of feature rows.
private struct PageLayout<Hero: View, Details: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var details: () -> Details

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            hero()
            if Details.self != EmptyView.self {
                VStack(spacing: 0) { details() }
                    .padding(.vertical, 6)
                    .tourGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 32)
            }
        }
        // Clears the window's close button, which sits over the content.
        .padding(.top, 44)
    }
}

private extension PageLayout where Details == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder hero: @escaping () -> Hero) {
        self.init(title: title, subtitle: subtitle, hero: hero, details: { EmptyView() })
    }
}

/// One feature: its icon, what it does, and its shortcut.
private struct FeatureRow: View {
    let symbol: String
    let title: String
    let keys: [String]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { KeyCap(text: $0) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.primary.opacity(0.75) : Color.primary.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - Miniature notes

/// A small drawing of a real note, using the app's own note colors.
private struct MiniNote<Content: View>: View {
    let color: NoteColor
    var width: CGFloat = 170
    var showsControls = false
    var showsTimer = false
    @ViewBuilder var content: () -> Content

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleBar
            content()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(width: width, alignment: .leading)
        .background(Color(nsColor: color.background), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }

    private var titleBar: some View {
        ZStack {
            if showsTimer {
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill").font(.system(size: 9))
                    Text("24:37").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(Color(nsColor: color.accent))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .tourGlass(in: Capsule())
            }
            HStack(spacing: 4) {
                Spacer()
                if showsControls {
                    MiniControl(symbol: "plus")
                    MiniControl(swatch: color)
                    MiniControl(symbol: "pin")
                    MiniControl(symbol: TuckTab.side == .right ? "arrow.right.to.line" : "arrow.left.to.line")
                }
            }
        }
        .frame(minHeight: showsControls || showsTimer ? 24 : 4)
    }
}

private struct MiniControl: View {
    var symbol: String? = nil
    var swatch: NoteColor? = nil

    var body: some View {
        Group {
            if let swatch {
                Circle()
                    .fill(Color(nsColor: swatch.background))
                    .overlay(Circle().strokeBorder(Color(nsColor: swatch.accent), lineWidth: 1.5))
                    .frame(width: 11, height: 11)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .tourGlass(in: Circle())
    }
}

private struct MiniLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 13)).lineLimit(1)
    }
}

private struct MiniCheck: View {
    let text: String
    var done = false
    let color: NoteColor
    var tag: String? = nil

    init(_ text: String, done: Bool = false, color: NoteColor, tag: String? = nil) {
        self.text = text
        self.done = done
        self.color = color
        self.tag = tag
    }

    var body: some View {
        HStack(spacing: 7) {
            // Circles, like the real checkboxes: a filled accent disc with a white check when done.
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(done ? Color.white : Color(nsColor: color.accent), Color(nsColor: color.accent))
            Text(text)
                .font(.system(size: 13))
                .strikethrough(done)
                .foregroundStyle(done ? .secondary : .primary)
                .lineLimit(1)
            if let tag {
                Text(tag)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: color.accent))
            }
        }
    }
}

// MARK: - Liquid Glass, with fallbacks for macOS 14 and 15

private extension View {
    @ViewBuilder func tourGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder func tourButton(prominent: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent).controlSize(.large)
            } else {
                buttonStyle(.glass).controlSize(.large)
            }
        } else if prominent {
            buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            buttonStyle(.bordered).controlSize(.large)
        }
    }
}

/// The window behind the tour: frosted, so the desktop shows through without hurting legibility.
/// (Glass itself stays on the controls and panels above it, as Apple's design guidance asks.)
struct OnboardingBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
