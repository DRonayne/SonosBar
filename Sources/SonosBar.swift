import Combine
import SwiftUI

// Layout and type follow the system status menus (Battery, Wi-Fi, Sound).
struct Panel: View {
    @ObservedObject var model: Model
    @AppStorage("showSound") private var showSound = false
    @AppStorage("showRooms") private var showRooms = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let room = model.room {
                section {
                    nowPlaying(room)
                    transport
                    volume
                }
                section {
                    disclosure(model.group.count > 1 ? "Sound: \(room.name)" : "Sound", $showSound)
                    if showSound { sound }
                }
                if model.rooms.count > 1 {
                    section {
                        disclosure("Group Rooms", $showRooms)
                        if showRooms { rooms(room) }
                    }
                }
            } else {
                section { empty }
            }
            if let e = model.error {
                section { Label(e, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary) }
            }
            section {
                Button("Find Speakers Again") { Task { await model.load() } }
                Button("Quit SonosBar") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .buttonStyle(RowStyle())
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A block of rows under an inset separator, like the groups in the Battery menu.
    private func section(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 4) { content() }
        }
        .padding(.horizontal, 14)
    }

    private func row(_ title: String, _ symbol: String, on: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 26, height: 26)
                .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Circle())
            Text(title)
            Spacer(minLength: 0)
        }
    }

    private func disclosure(_ title: String, _ open: Binding<Bool>) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { open.wrappedValue.toggle() } } label: {
            HStack {
                Text(title).sectionHeader()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
            }
        }
    }

    private var header: some View {
        Menu {
            Picker("Room", selection: $model.selected) {
                ForEach(model.rooms) { Text($0.name).tag(Optional($0.uuid)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(roomTitle).font(.system(size: 13, weight: .bold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.rooms.isEmpty)
        .help("Choose a room")
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    private var roomTitle: String {
        guard let room = model.room else { return "Sonos" }
        return model.group.count > 1 ? "\(room.name) + \(model.group.count - 1)" : room.name
    }

    private func nowPlaying(_ room: Room) -> some View {
        let np = model.now
        return HStack(spacing: 10) {
            Group {
                if let art = model.art {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: np.tv ? "tv" : "music.note")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(np.tv ? "TV" : (np.title.isEmpty ? "Nothing Playing" : np.title))
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(np.tv ? "\(room.name) TV input" : [np.artist, np.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var transport: some View {
        HStack(spacing: 40) {
            Button { model.transport("Previous") } label: {
                Label("Previous", systemImage: "backward.fill").labelStyle(.iconOnly)
            }
            .disabled(model.now.tv)
            Button(action: model.playPause) {
                Label(model.now.playing ? "Pause" : "Play", systemImage: model.now.playing ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 22))
                    .frame(width: 24)
            }
            .keyboardShortcut(.space, modifiers: [])
            Button { model.transport("Next") } label: {
                Label("Next", systemImage: "forward.fill").labelStyle(.iconOnly)
            }
            .disabled(model.now.tv)
        }
        .font(.system(size: 16))
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var volume: some View {
        HStack(spacing: 8) {
            Button(action: model.toggleMute) {
                Label(model.muted ? "Unmute" : "Mute", systemImage: model.muted ? "speaker.slash.fill" : "speaker.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(model.muted ? "Unmute" : "Mute")
            Slider(value: model.volumeBinding, in: 0...100) {
                Text(model.group.count > 1 ? "Group volume" : "Volume")
            } onEditingChanged: { model.dragging = $0 }
            .labelsHidden()
            .help(model.group.count > 1 ? "Group volume" : "Volume")
            Text("\(Int(model.volume))")
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .opacity(model.muted ? 0.6 : 1)
        .padding(.bottom, 2)
    }

    private var sound: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(["Bass", "Treble"], id: \.self) { name in
                    GridRow {
                        Text(name).foregroundStyle(.secondary)
                        Slider(value: model.tone(name), in: -10...10) { Text(name) } onEditingChanged: { model.dragging = $0 }
                            .labelsHidden()
                        Text(String(format: "%+d", Int(model.tone(name).wrappedValue)))
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
            Toggle("Loudness", isOn: model.loudnessBinding)
                .help("Boosts bass and treble at low volume")
            if model.isHomeTheater {
                Toggle("Night Mode", isOn: model.nightModeBinding)
                    .help("Quietens loud TV moments and lifts dialogue")
            }
        }
        .toggleStyle(SwitchRowStyle())
        .padding(.vertical, 4)
    }

    private func rooms(_ current: Room) -> some View {
        ForEach(model.rooms) { r in
            let on = model.group.contains(r)
            Button { model.setInGroup(r, !on) } label: { row(r.name, "hifispeaker.fill", on: on) }
                .disabled(r == current && model.group.count == 1)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            if model.searching {
                ProgressView().controlSize(.small)
                Text("Looking for speakers…").foregroundStyle(.secondary)
            } else {
                Image(systemName: "hifispeaker.slash").font(.title2).foregroundStyle(.secondary)
                Text("No Speakers Found").font(.system(size: 13, weight: .semibold))
                Text("Check your Mac is on the same Wi-Fi, and that Local Network access is on for SonosBar.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private extension Text {
    func sectionHeader() -> some View { font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
}

/// Full width menu row with the rounded hover highlight status menus use.
private struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    private struct Row: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(.primary.opacity(configuration.isPressed ? 0.16 : hover && enabled ? 0.1 : 0),
                            in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, -9)
                .opacity(enabled ? 1 : 0.4)
                .onHover { hover = $0 }
        }
    }
}

/// Label on the left, small switch on the right, like the toggles in Control Center.
private struct SwitchRowStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) {
            HStack { configuration.label; Spacer() }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }
}

@main
struct SonosBar: App {
    @NSApplicationDelegateAdaptor(StatusItem.self) private var statusItem

    init() {
        if CommandLine.arguments.contains("--selftest") {
            Sonos.selfTest()
            exit(0)
        }
    }

    var body: some Scene { Settings { EmptyView() } }
}

/// Our own status item and panel: MenuBarExtra's window paints square fills we cannot turn off.
@MainActor
final class StatusItem: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = Model()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = MenuPanel()
    private var playing: AnyCancellable?

    func applicationDidFinishLaunching(_ note: Notification) {
        panel.content = Fitting(rootView: Panel(model: model))
        panel.delegate = self
        item.button?.target = self
        item.button?.action = #selector(toggle)
        playing = model.$now.map(\.playing).removeDuplicates().sink { [weak self] on in
            self?.item.button?.image = NSImage(systemSymbolName: on ? "hifispeaker.fill" : "hifispeaker",
                                               accessibilityDescription: "SonosBar")
        }
        model.start()
    }

    @objc private func toggle() {
        if panel.isVisible { return panel.close() }
        guard let button = item.button, let anchor = button.window?.convertToScreen(button.frame),
              let screen = button.window?.screen?.visibleFrame else { return }
        panel.fit()
        let size = panel.frame.size
        let x = min(max(anchor.minX, screen.minX + 6), screen.maxX - size.width - 6)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - 5))
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        model.panelOpen = true
        Task { await model.refresh() }
    }

    func windowDidResignKey(_ note: Notification) { panel.close() }

    func windowWillClose(_ note: Notification) {
        item.button?.highlight(false)
        model.panelOpen = false
    }
}

/// Titled but chromeless, the way Tophat does it: a titled window gets the system's rounded corner mask
/// and shadow for free, which a borderless one has to fake.
final class MenuPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { standardWindowButton(b)?.isHidden = true }
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        isFloatingPanel = true
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    }

    var content: Fitting<Panel>? {
        didSet {
            guard let content else { return }
            content.safeAreaRegions = []
            content.onResize = { [weak self] in self?.fit() }
            if #available(macOS 26, *) {
                let glass = NSGlassEffectView()
                glass.cornerRadius = 16
                glass.contentView = content
                contentView = glass
            } else {
                let blur = NSVisualEffectView()
                blur.material = .menu
                blur.state = .active
                blur.addSubview(content)
                content.frame = blur.bounds
                content.autoresizingMask = [.width, .height]
                contentView = blur
            }
            fit()
        }
    }

    /// Sizes the window to the SwiftUI content, keeping the top edge under the menu bar.
    func fit() {
        guard let size = content?.fittingSize else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

/// Hosting view that reports when its SwiftUI content changes size (a section expanding, say).
final class Fitting<Content: View>: NSHostingView<Content> {
    var onResize: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { self.onResize?() }
    }
}
