import SwiftUI

struct Panel: View {
    @ObservedObject var model: Model
    @AppStorage("showSound") private var showSound = false
    @AppStorage("showRooms") private var showRooms = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let room = model.room {
                nowPlaying(room)
                transport
                volume
                Divider()
                DisclosureGroup(isExpanded: $showSound) { sound } label: {
                    Text(model.group.count > 1 ? "Sound: \(room.name)" : "Sound").font(.subheadline.weight(.medium))
                }
                if model.rooms.count > 1 {
                    DisclosureGroup(isExpanded: $showRooms) { rooms(room) } label: {
                        Text("Group rooms").font(.subheadline.weight(.medium))
                    }
                }
            } else {
                empty
            }
            if let e = model.error {
                Label(e, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background { Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q").opacity(0) }
        .onAppear {
            model.panelOpen = true
            Task { await model.refresh() }
        }
        .onDisappear { model.panelOpen = false }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Room", selection: $model.selected) {
                    ForEach(model.rooms) { Text($0.name).tag(Optional($0.uuid)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(roomTitle).font(.headline)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.rooms.isEmpty)
            .help("Choose a room")

            Spacer()

            if model.isHomeTheater {
                Button(action: model.playTV) {
                    Label("TV", systemImage: model.now.tv ? "tv.fill" : "tv").labelStyle(.iconOnly)
                }
                .foregroundStyle(model.now.tv ? Color.accentColor : .primary)
                .help(model.now.tv ? "Playing TV audio" : "Switch to TV audio")
            }

            Menu {
                ForEach(model.favourites) { f in
                    Button(f.title) { model.play(f) }.disabled(f.uri.isEmpty)
                }
                if model.favourites.isEmpty {
                    Text("No Sonos favourites yet")
                } else if model.favourites.contains(where: { $0.uri.isEmpty }) {
                    Divider()
                    Text("Greyed out ones only play from the Sonos app")
                }
            } label: {
                Label("Favourites", systemImage: "star").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.room == nil)
            .help("Sonos favourites")

            Menu {
                Button("Find speakers again") { Task { await model.load() } }
                Divider()
                Button("Quit SonosBar") { NSApp.terminate(nil) }
            } label: {
                Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.borderless)
    }

    private var roomTitle: String {
        guard let room = model.room else { return "Sonos" }
        return model.group.count > 1 ? "\(room.name) + \(model.group.count - 1)" : room.name
    }

    private func nowPlaying(_ room: Room) -> some View {
        let np = model.now
        return HStack(spacing: 12) {
            Group {
                if let art = model.art {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: np.tv ? "tv" : "music.note")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(np.tv ? "TV" : (np.title.isEmpty ? "Nothing playing" : np.title))
                    .font(.headline).lineLimit(2)
                Text(np.tv ? "\(room.name) TV input" : np.artist)
                    .foregroundStyle(.secondary).lineLimit(1)
                if !np.album.isEmpty && !np.tv {
                    Text(np.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var transport: some View {
        HStack(spacing: 36) {
            Button { model.transport("Previous") } label: {
                Label("Previous", systemImage: "backward.fill").labelStyle(.iconOnly).font(.title3)
            }
            .disabled(model.now.tv)
            Button(action: model.playPause) {
                Label(model.now.playing ? "Pause" : "Play",
                      systemImage: model.now.playing ? "pause.circle.fill" : "play.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 38))
            }
            .keyboardShortcut(.space, modifiers: [])
            Button { model.transport("Next") } label: {
                Label("Next", systemImage: "forward.fill").labelStyle(.iconOnly).font(.title3)
            }
            .disabled(model.now.tv)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
    }

    private var volume: some View {
        HStack(spacing: 10) {
            Button(action: model.toggleMute) {
                Label(model.muted ? "Unmute" : "Mute", systemImage: model.muted ? "speaker.slash.fill" : "speaker.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(model.muted ? "Unmute" : "Mute")
            Slider(value: model.volumeBinding, in: 0...100) {
                Text(model.group.count > 1 ? "Group volume" : "Volume")
            } onEditingChanged: { model.dragging = $0 }
            .labelsHidden()
            .help(model.group.count > 1 ? "Group volume" : "Volume")
            Text("\(Int(model.volume))")
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .opacity(model.muted ? 0.6 : 1)
    }

    private var sound: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(["Bass", "Treble"], id: \.self) { name in
                    GridRow {
                        Text(name).foregroundStyle(.secondary)
                        Slider(value: model.tone(name), in: -10...10) { Text(name) } onEditingChanged: { model.dragging = $0 }
                            .labelsHidden()
                        Text(String(format: "%+d", Int(model.tone(name).wrappedValue)))
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                    }
                }
            }
            HStack(spacing: 18) {
                Toggle("Loudness", isOn: model.loudnessBinding)
                    .help("Boosts bass and treble at low volume")
                if model.isHomeTheater {
                    Toggle("Night mode", isOn: model.nightModeBinding)
                        .help("Quietens loud TV moments and lifts dialogue")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.top, 8)
    }

    private func rooms(_ current: Room) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.rooms) { r in
                Toggle(r.name, isOn: Binding(get: { model.group.contains(r) }, set: { model.setInGroup(r, $0) }))
                    .disabled(r == current && model.group.count == 1)
            }
        }
        .padding(.top, 8)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            if model.searching {
                ProgressView().controlSize(.small)
                Text("Looking for speakers…").foregroundStyle(.secondary)
            } else {
                Image(systemName: "hifispeaker.slash").font(.title).foregroundStyle(.secondary)
                Text("No speakers found").font(.headline)
                Text("Check your Mac is on the same Wi-Fi, and that Local Network access is on for SonosBar.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Try again") { Task { await model.load() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

@main
struct SonosBar: App {
    @StateObject private var model = Model()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            Sonos.selfTest()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(model: model)
        } label: {
            Image(systemName: model.now.playing ? "hifispeaker.fill" : "hifispeaker")
                .task { model.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
