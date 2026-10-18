import Foundation
import Darwin

struct Room: Hashable, Identifiable {
    let uuid: String
    let name: String
    let ip: String
    let coordinator: String
    var id: String { uuid }
}

struct Favourite: Hashable, Identifiable {
    let title: String
    let uri: String // empty for app-only shortcuts (e.g. Sonos Radio), which UPnP cannot start
    let meta: String
    var id: String { title + uri }
}

// Local UPnP control on :1400. Same discovery the official app uses (SsdpClient, ZonePlayer:1),
// but keyless, unlike its :1443 API which needs X-Sonos-Api-Key.
enum Sonos {
    struct NowPlaying: Equatable {
        var playing = false
        var title = "", artist = "", album = "", art: URL?
        var tv = false
    }

    static let i0 = "<InstanceID>0</InstanceID>"

    // MARK: Discovery and topology

    static func discover(timeout: Int = 2) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(1900).bigEndian
        addr.sin_addr.s_addr = inet_addr("239.255.255.250")
        let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
        for _ in 0..<2 { // UDP, so send twice
            _ = msg.withCString { p in
                withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, p, strlen(p), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var ips = Set<String>()
        var buf = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        while true {
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
            }
            if n <= 0 { break }
            ips.insert(String(cString: inet_ntoa(from.sin_addr)))
        }
        return ips.sorted()
    }

    static func topology(_ ip: String) async throws -> [Room] {
        parseTopology(value("ZoneGroupState", in: try await soap(ip, "ZoneGroupTopology", "GetZoneGroupState", "")) ?? "")
    }

    static func parseTopology(_ xml: String) -> [Room] {
        var coordinator = ""
        var rooms: [Room] = []
        for e in elements(xml) {
            if e.name == "ZoneGroup" { coordinator = e.attrs["Coordinator"] ?? "" }
            // Sub and surrounds are <Satellite> children; the second half of a stereo pair is Invisible.
            if e.name == "ZoneGroupMember", e.attrs["Invisible"] != "1",
               let uuid = e.attrs["UUID"], let ip = URL(string: e.attrs["Location"] ?? "")?.host {
                rooms.append(Room(uuid: uuid, name: e.attrs["ZoneName"] ?? ip, ip: ip, coordinator: coordinator))
            }
        }
        return rooms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Joins the speaker at ip to the group led by coordinatorUUID.
    static func join(_ ip: String, _ coordinatorUUID: String) async throws {
        try await setURI(ip, "x-rincon:\(coordinatorUUID)", "")
    }

    static func leave(_ ip: String) async throws {
        _ = try await soap(ip, "AVTransport", "BecomeCoordinatorOfStandaloneGroup", i0)
    }

    // MARK: Volume (group level, sent to the coordinator; a lone speaker is a group of one)

    static func groupVolume(_ ip: String) async throws -> Int {
        Int(value("CurrentVolume", in: try await soap(ip, "GroupRenderingControl", "GetGroupVolume", i0)) ?? "") ?? 0
    }

    static func setGroupVolume(_ ip: String, _ v: Int) async throws {
        // Snapshot first so members keep their relative levels.
        _ = try await soap(ip, "GroupRenderingControl", "SnapshotGroupVolume", i0)
        _ = try await soap(ip, "GroupRenderingControl", "SetGroupVolume", i0 + "<DesiredVolume>\(min(max(v, 0), 100))</DesiredVolume>")
    }

    static func groupMute(_ ip: String) async throws -> Bool {
        value("CurrentMute", in: try await soap(ip, "GroupRenderingControl", "GetGroupMute", i0)) == "1"
    }

    static func setGroupMute(_ ip: String, _ m: Bool) async throws {
        _ = try await soap(ip, "GroupRenderingControl", "SetGroupMute", i0 + "<DesiredMute>\(m ? 1 : 0)</DesiredMute>")
    }

    // MARK: Sound (per speaker)

    /// name: Bass or Treble, range -10...10
    static func tone(_ ip: String, _ name: String) async throws -> Int {
        Int(value("Current\(name)", in: try await soap(ip, "RenderingControl", "Get\(name)", i0)) ?? "") ?? 0
    }

    static func setTone(_ ip: String, _ name: String, _ v: Int) async throws {
        _ = try await soap(ip, "RenderingControl", "Set\(name)", i0 + "<Desired\(name)>\(min(max(v, -10), 10))</Desired\(name)>")
    }

    static func loudness(_ ip: String) async throws -> Bool {
        value("CurrentLoudness", in: try await soap(ip, "RenderingControl", "GetLoudness", i0 + "<Channel>Master</Channel>")) == "1"
    }

    static func setLoudness(_ ip: String, _ on: Bool) async throws {
        _ = try await soap(ip, "RenderingControl", "SetLoudness", i0 + "<Channel>Master</Channel><DesiredLoudness>\(on ? 1 : 0)</DesiredLoudness>")
    }

    /// Throws on speakers without TV input, which doubles as the home theatre check.
    static func nightMode(_ ip: String) async throws -> Bool {
        value("CurrentValue", in: try await soap(ip, "RenderingControl", "GetEQ", i0 + "<EQType>NightMode</EQType>")) == "1"
    }

    static func setNightMode(_ ip: String, _ on: Bool) async throws {
        _ = try await soap(ip, "RenderingControl", "SetEQ", i0 + "<EQType>NightMode</EQType><DesiredValue>\(on ? 1 : 0)</DesiredValue>")
    }

    // MARK: Playback (send to the coordinator)

    static func nowPlaying(_ ip: String) async throws -> NowPlaying {
        let state = value("CurrentTransportState", in: try await soap(ip, "AVTransport", "GetTransportInfo", i0))
        let pos = try await soap(ip, "AVTransport", "GetPositionInfo", i0)
        let meta = value("TrackMetaData", in: pos) ?? "" // DIDL-Lite, escaped inside the reply
        return NowPlaying(playing: state == "PLAYING" || state == "TRANSITIONING",
                          title: value("dc:title", in: meta) ?? "",
                          artist: value("dc:creator", in: meta) ?? "",
                          album: value("upnp:album", in: meta) ?? "",
                          art: value("upnp:albumArtURI", in: meta).flatMap { $0.hasPrefix("/") ? URL(string: "http://\(ip):1400\($0)") : URL(string: $0) },
                          tv: value("TrackURI", in: pos)?.hasPrefix("x-sonos-htastream:") ?? false)
    }

    /// action: Play, Pause, Next, Previous
    static func send(_ ip: String, _ action: String) async throws {
        _ = try await soap(ip, "AVTransport", action, i0 + (action == "Play" ? "<Speed>1</Speed>" : ""))
    }

    static func playTV(_ ip: String, _ uuid: String) async throws {
        try await setURI(ip, "x-sonos-htastream:\(uuid):spdif", "")
        try await send(ip, "Play")
    }

    static func favourites(_ ip: String) async throws -> [Favourite] {
        let r = try await soap(ip, "ContentDirectory", "Browse",
                               "<ObjectID>FV:2</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>100</RequestedCount><SortCriteria></SortCriteria>")
        return parseFavourites(value("Result", in: r) ?? "")
    }

    static func parseFavourites(_ didl: String) -> [Favourite] {
        let els = elements(didl)
        return els.indices.filter { els[$0].name == "item" }.map { i in
            func child(_ name: String) -> String { els.first { $0.parent == i && $0.name == name }?.text ?? "" }
            return Favourite(title: child("dc:title"), uri: child("res"), meta: child("r:resMD"))
        }
    }

    /// Playlists and albums go through the queue; streams and single tracks play directly.
    static func play(_ fav: Favourite, on ip: String, coordinatorUUID: String) async throws {
        if ["x-rincon-cpcontainer:", "x-rincon-playlist:", "file:///jffs/settings/savedqueues"].contains(where: fav.uri.hasPrefix) {
            _ = try await soap(ip, "AVTransport", "RemoveAllTracksFromQueue", i0)
            _ = try await soap(ip, "AVTransport", "AddURIToQueue", i0 + "<EnqueuedURI>\(esc(fav.uri))</EnqueuedURI><EnqueuedURIMetaData>\(esc(fav.meta))</EnqueuedURIMetaData><DesiredFirstTrackNumberEnqueued>0</DesiredFirstTrackNumberEnqueued><EnqueueAsNext>0</EnqueueAsNext>")
            try await setURI(ip, "x-rincon-queue:\(coordinatorUUID)#0", "")
        } else {
            try await setURI(ip, fav.uri, fav.meta)
        }
        try await send(ip, "Play")
    }

    private static func setURI(_ ip: String, _ uri: String, _ meta: String) async throws {
        _ = try await soap(ip, "AVTransport", "SetAVTransportURI", i0 + "<CurrentURI>\(esc(uri))</CurrentURI><CurrentURIMetaData>\(esc(meta))</CurrentURIMetaData>")
    }

    // MARK: SOAP and XML

    static func soap(_ ip: String, _ service: String, _ action: String, _ args: String) async throws -> String {
        let path = switch service {
        case "ContentDirectory": "/MediaServer/ContentDirectory/Control"
        case "ZoneGroupTopology": "/ZoneGroupTopology/Control"
        default: "/MediaRenderer/\(service)/Control"
        }
        let urn = "urn:schemas-upnp-org:service:\(service):1"
        var req = URLRequest(url: URL(string: "http://\(ip):1400\(path)")!, timeoutInterval: 3)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = Data("""
        <?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\(action) xmlns:u="\(urn)">\(args)</u:\(action)></s:Body></s:Envelope>
        """.utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return String(decoding: data, as: UTF8.self)
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Text of the first element with this (prefixed) name. Escaped XML inside it comes back unescaped.
    static func value(_ tag: String, in xml: String) -> String? {
        elements(xml).first { $0.name == tag }?.text
    }

    struct Element {
        let name: String
        let attrs: [String: String]
        let parent: Int?
        var text = ""
    }

    /// Every element in document order, with its parent's index.
    static func elements(_ xml: String) -> [Element] {
        final class Collector: NSObject, XMLParserDelegate {
            var out: [Element] = []
            var stack: [Int] = []
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                        qualifiedName: String?, attributes: [String: String] = [:]) {
                out.append(Element(name: name, attrs: attributes, parent: stack.last))
                stack.append(out.count - 1)
            }
            func parser(_ parser: XMLParser, foundCharacters s: String) {
                if let i = stack.last { out[i].text += s }
            }
            func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
                stack.removeLast()
            }
        }
        let c = Collector()
        let p = XMLParser(data: Data(xml.utf8))
        p.delegate = c
        p.parse()
        return c.out
    }

    /// Run with `SonosBar --selftest`.
    static func selfTest() {
        precondition(value("CurrentVolume", in: "<a><CurrentVolume>14</CurrentVolume></a>") == "14")
        precondition(value("CurrentMute", in: "<a></a>") == nil)
        let meta = value("M", in: "<r><M>&lt;t&gt;Rock &amp;amp; Roll&lt;/t&gt;</M></r>")!
        precondition(value("t", in: meta) == "Rock & Roll")

        let rooms = parseTopology("""
        <ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_A"><ZoneGroupMember UUID="RINCON_A" Location="http://10.0.0.2:1400/x.xml" ZoneName="Living Room"><Satellite UUID="RINCON_S" Location="http://10.0.0.3:1400/x.xml" ZoneName="Living Room"/></ZoneGroupMember><ZoneGroupMember UUID="RINCON_B" Location="http://10.0.0.4:1400/x.xml" ZoneName="Kitchen"/><ZoneGroupMember UUID="RINCON_C" Location="http://10.0.0.5:1400/x.xml" ZoneName="Kitchen" Invisible="1"/></ZoneGroup></ZoneGroups></ZoneGroupState>
        """)
        precondition(rooms == [Room(uuid: "RINCON_B", name: "Kitchen", ip: "10.0.0.4", coordinator: "RINCON_A"),
                               Room(uuid: "RINCON_A", name: "Living Room", ip: "10.0.0.2", coordinator: "RINCON_A")])

        let favs = parseFavourites("""
        <DIDL-Lite><item id="FV:2/1"><dc:title>Mix</dc:title><res>x-rincon-cpcontainer:abc?a=1&amp;b=2</res><r:resMD>&lt;DIDL-Lite/&gt;</r:resMD></item><item id="FV:2/2"><dc:title>Radio</dc:title><res></res></item></DIDL-Lite>
        """)
        precondition(favs == [Favourite(title: "Mix", uri: "x-rincon-cpcontainer:abc?a=1&b=2", meta: "<DIDL-Lite/>"),
                              Favourite(title: "Radio", uri: "", meta: "")])
        print("selftest ok")
    }
}
