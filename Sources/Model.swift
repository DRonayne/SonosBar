import SwiftUI
import MediaPlayer

@MainActor
final class Model: ObservableObject {
    @Published var rooms: [Room] = []
    @Published var selected = UserDefaults.standard.string(forKey: "room") {
        didSet {
            UserDefaults.standard.set(selected, forKey: "room")
            if oldValue != selected { Task { await refresh() } }
        }
    }
    @Published var now = Sonos.NowPlaying()
    @Published var art: NSImage?
    @Published var volume: Double = 0
    @Published var muted = false
    @Published var bass = 0
    @Published var treble = 0
    @Published var loudness = false
    @Published var nightMode = false
    @Published var homeTheaters: Set<String> = [] // room uuids with TV input
    @Published var favourites: [Favourite] = []
    @Published var searching = false
    @Published var error: String?

    var panelOpen = false
    var dragging = false // a slider is held, so polling must not move it
    private var started = false
    private var sending = false
    private var seedIP: String?
    private var artURL: URL?
    private var published: (Sonos.NowPlaying, NSImage?)?

    var room: Room? { rooms.first { $0.uuid == selected } }
    var coordinator: Room? { rooms.first { $0.uuid == room?.coordinator } }
    var group: [Room] { rooms.filter { $0.coordinator == room?.coordinator } }
    var isHomeTheater: Bool { room.map { homeTheaters.contains($0.uuid) } ?? false }

    func start() {
        guard !started else { return }
        started = true
        setUpMediaKeys()
        Task {
            await load()
            while true {
                // Quick while the panel is open; slow in the background to keep media keys and Now Playing current.
                try? await Task.sleep(for: .seconds(panelOpen ? 3 : 15))
                await refresh()
            }
        }
    }

    func load() async {
        searching = true
        defer { searching = false }
        let ips = await Task.detached { Sonos.discover() }.value
        guard let ip = ips.first else {
            rooms = []
            error = "No Sonos speakers found"
            return
        }
        seedIP = ip
        await refresh()
        favourites = (try? await Sonos.favourites(ip)) ?? []
    }

    func refresh() async {
        guard let ip = room?.ip ?? seedIP else { return }
        do {
            rooms = try await Sonos.topology(ip)
            if room == nil { selected = rooms.first?.uuid }
            guard let r = room, let c = coordinator else { return }
            let np = try await Sonos.nowPlaying(c.ip)
            if np != now { now = np }
            await loadArt(np.art)
            muted = try await Sonos.groupMute(c.ip)
            loudness = try await Sonos.loudness(r.ip)
            if let night = try? await Sonos.nightMode(r.ip) {
                nightMode = night
                homeTheaters.insert(r.uuid)
            } else {
                homeTheaters.remove(r.uuid)
            }
            if !dragging && !sending {
                volume = Double(try await Sonos.groupVolume(c.ip))
                bass = try await Sonos.tone(r.ip, "Bass")
                treble = try await Sonos.tone(r.ip, "Treble")
            }
            error = nil
            publishNowPlaying()
        } catch {
            self.error = "\(room?.name ?? "Speaker") isn't responding"
        }
    }

    private func loadArt(_ url: URL?) async {
        guard url != artURL else { return }
        artURL = url
        art = nil
        if let url, let (data, _) = try? await URLSession.shared.data(from: url) { art = NSImage(data: data) }
    }

    // MARK: Actions

    private func perform(_ failure: String, _ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { self.error = failure }
            try? await Task.sleep(for: .milliseconds(600)) // let the speaker settle before reading back
            await refresh()
        }
    }

    func transport(_ action: String) {
        guard let c = coordinator else { return }
        if action == "Play" || action == "Pause" { now.playing = action == "Play" }
        perform("Couldn't \(action.lowercased())") { try await Sonos.send(c.ip, action) }
    }

    func playPause() { transport(now.playing ? "Pause" : "Play") }

    func playTV() {
        guard let r = room else { return }
        let grouped = r.coordinator != r.uuid
        perform("Couldn't switch to TV") {
            if grouped { try await Sonos.leave(r.ip) } // only a coordinator can change source
            try await Sonos.playTV(r.ip, r.uuid)
        }
    }

    func play(_ fav: Favourite) {
        guard let c = coordinator else { return }
        perform("Couldn't play \(fav.title)") { try await Sonos.play(fav, on: c.ip, coordinatorUUID: c.uuid) }
    }

    func setInGroup(_ other: Room, _ on: Bool) {
        guard let c = coordinator else { return }
        perform("Couldn't change the group") {
            if on { try await Sonos.join(other.ip, c.uuid) } else { try await Sonos.leave(other.ip) }
        }
    }

    func toggleMute() {
        guard let c = coordinator else { return }
        muted.toggle()
        let m = muted
        perform("Couldn't change mute") { try await Sonos.setGroupMute(c.ip, m) }
    }

    // Bindings set the speaker from user input only, so values read back by polling are never echoed.

    var volumeBinding: Binding<Double> {
        Binding(get: { self.volume }, set: { self.volume = $0; self.pushVolume() })
    }

    // Sends only the latest slider value, so a drag does not queue dozens of requests.
    private func pushVolume() {
        guard !sending, let c = coordinator else { return }
        sending = true
        Task {
            var sent = -1
            while Int(volume) != sent {
                sent = Int(volume)
                do { try await Sonos.setGroupVolume(c.ip, sent) } catch { self.error = "Couldn't change volume"; break }
            }
            sending = false
        }
    }

    func tone(_ name: String) -> Binding<Double> {
        Binding(
            get: { Double(name == "Bass" ? self.bass : self.treble) },
            set: { new in
                let v = Int(new.rounded())
                guard v != (name == "Bass" ? self.bass : self.treble), let r = self.room else { return }
                if name == "Bass" { self.bass = v } else { self.treble = v }
                Task { try? await Sonos.setTone(r.ip, name, v) }
            })
    }

    var loudnessBinding: Binding<Bool> {
        Binding(get: { self.loudness }, set: { on in
            guard let r = self.room else { return }
            self.loudness = on
            self.perform("Couldn't change loudness") { try await Sonos.setLoudness(r.ip, on) }
        })
    }

    var nightModeBinding: Binding<Bool> {
        Binding(get: { self.nightMode }, set: { on in
            guard let r = self.room else { return }
            self.nightMode = on
            self.perform("Couldn't change night mode") { try await Sonos.setNightMode(r.ip, on) }
        })
    }

    // MARK: Media keys and Control Center Now Playing

    private func setUpMediaKeys() {
        let c = MPRemoteCommandCenter.shared()
        let handlers: [(MPRemoteCommand, @MainActor (Model) -> Void)] = [
            (c.togglePlayPauseCommand, { $0.playPause() }),
            (c.playCommand, { $0.transport("Play") }),
            (c.pauseCommand, { $0.transport("Pause") }),
            (c.nextTrackCommand, { $0.transport("Next") }),
            (c.previousTrackCommand, { $0.transport("Previous") }),
        ]
        for (command, handler) in handlers {
            command.addTarget { [weak self] _ in
                Task { @MainActor in if let self { handler(self) } }
                return .success
            }
        }
    }

    // Only on change: re-asserting "playing" every poll would keep stealing the media keys from other apps.
    private func publishNowPlaying() {
        if let p = published, p.0 == now, p.1 === art { return }
        published = (now, art)
        let center = MPNowPlayingInfoCenter.default()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: now.tv ? "TV" : now.title,
            MPMediaItemPropertyArtist: now.tv ? (room?.name ?? "") : now.artist,
            MPMediaItemPropertyAlbumTitle: now.album,
        ]
        if let art { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art } }
        center.nowPlayingInfo = info
        center.playbackState = now.playing ? .playing : .paused
    }
}
