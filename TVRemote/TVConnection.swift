import Foundation
import Network
import PilotKit
import UIKit

/// Talks to an LG webOS TV over the local network, using the same
/// "connect apps" socket LG's own phone app uses. The TV asks once on
/// screen before it lets a new phone in; after that we keep its key.
@MainActor
final class TVConnection: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case waitingForApproval
        case connected
        case failed(String)
    }

    typealias App = TVApp
    typealias Input = TVInput
    typealias SavedTV = PilotKit.SavedTV

    /// The HDMI input on screen (the PS5, say), if that's what's showing.
    var foregroundInput: Input? { inputs.first { $0.appId != nil && $0.appId == foreground } }

    // MARK: Icons

    /// The TV serves icons over its self-signed TLS port, so they load
    /// through our own session (which trusts it) rather than AsyncImage.
    private let icons = NSCache<NSURL, UIImage>()

    func image(_ url: URL) async -> UIImage? {
        if let cached = icons.object(forKey: url as NSURL) { return cached }
        // Kept on the phone too, so logos show at once, even before the TV answers.
        let file = Self.iconFile(url)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            icons.setObject(image, forKey: url as NSURL)
            return image
        }
        guard let (data, _) = try? await session.data(from: url), let image = UIImage(data: data) else { return nil }
        icons.setObject(image, forKey: url as NSURL)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
        return image
    }

    private static func iconFile(_ url: URL) -> URL {
        let name = url.path.split(separator: "/").suffix(2).joined(separator: "-")
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("icons", isDirectory: true)
            .appendingPathComponent(name)
    }

    /// The apps LG puts on its remote's shortcut keys, in that order.
    var shortcuts: [App] {
        let preferred = ["netflix", "amazon", "com.disney.disneyplus-prod", "youtube.leanback.v4"]
        let picked = preferred.compactMap { id in apps.first { $0.id == id } }
        let rest = apps.filter { !picked.contains($0) }
        return Array((picked + rest).prefix(4))
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var apps: [App] = []
    @Published private(set) var inputs: [Input] = []
    @Published private(set) var volume: Int?
    @Published private(set) var muted = false
    /// The app on screen right now, from the TV.
    @Published private(set) var foreground: String?
    /// "playing", "paused", … for the app on screen, when it reports one.
    @Published var playState: String?
    /// The TV's own keyboard is up: a text field on screen wants typing.
    @Published private(set) var keyboardOpen = false
    @Published private(set) var host: String? = UserDefaults.standard.string(forKey: "host")

    /// Pairing keys, wake addresses and the saved list, kept on the phone.
    private let pairings = Pairings(store: UserDefaults.standard)

    /// Every TV this phone has paired with.
    @Published private(set) var saved: [SavedTV] = Pairings(store: UserDefaults.standard).saved
    /// Showing setup to add another TV, while staying paired with this one.
    @Published var adding = false
    private var hostBeforeAdding: String?

    var current: SavedTV? { saved.first { $0.host == host } }

    /// One connection for the whole app, so Lock Screen buttons (which wake the app
    /// in the background) use the same TV and pairing as the remote.
    static let shared = TVConnection()

    /// Waits for the TV to accept us, for Lock Screen buttons pressed while we were asleep.
    func waitUntilConnected(seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while state != .connected && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return state == .connected
    }

    init() {
        // Phones paired before there was a TV list: keep that TV.
        if saved.isEmpty, let host, pairings.key(for: host) != nil {
            save([SavedTV(host: host, name: "Living room")])
        }
    }

    private func save(_ list: [SavedTV]) {
        saved = list
        pairings.save(list)
    }

    func rename(to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let host else { return }
        save(saved.map { $0.host == host ? SavedTV(host: host, name: name) : $0 })
    }

    func startAdding() {
        hostBeforeAdding = host
        adding = true
    }

    func stopAdding() {
        adding = false
        if let previous = hostBeforeAdding, previous != host || state != .connected { connect(to: previous) }
        hostBeforeAdding = nil
    }

    /// Checks whether an address on the Wi-Fi is an LG TV: they answer on the
    /// TLS remote port with a plain 200.
    func isTV(_ address: String) async -> Bool {
        guard let url = URL(string: "https://\(address):3001/") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 1.5)
        request.httpMethod = "GET"
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private let session = URLSession(configuration: .default, delegate: LocalTrust(), delegateQueue: nil)
    private var socket: URLSessionWebSocketTask?
    private var pointer: URLSessionWebSocketTask?
    private var secure = true
    private var retries = 0
    private var nextID = 0
    private var replies: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var subscriptions: [String: ([String: Any]) -> Void] = [:]

    // MARK: Connecting

    func connect(to host: String) {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        if host != self.host {
            // A different TV: drop what we knew about the last one.
            apps = []; inputs = []; volume = nil; muted = false; foreground = nil; playState = nil
        }
        self.host = host
        UserDefaults.standard.set(host, forKey: "host")
        secure = true
        retries = 0
        open()
    }

    #if DEBUG
    /// Launch with `-demo` to see the remote without a TV.
    func demo() {
        host = "192.168.1.20"
        volume = 14
        foreground = CommandLine.arguments.contains("-ps5") ? "com.webos.app.hdmi2" : "Netflix"
        saved = [SavedTV(host: "192.168.1.20", name: "Living room"), SavedTV(host: "192.168.1.31", name: "Upstairs")]
        apps = ["Netflix", "Prime Video", "Disney+", "YouTube", "Apple TV", "Spotify", "LG Channels", "Twitch"]
            .map { App(id: $0, title: $0, icon: nil) }
        inputs = [Input(id: "HDMI_1", label: "HDMI 1", connected: true),
                  Input(id: "HDMI_2", label: "PlayStation 5", connected: true, port: 2, appId: "com.webos.app.hdmi2"),
                  Input(id: "HDMI_3", label: "HDMI 3", connected: false)]
        state = .connected
    }
    #endif

    /// A TV this phone has already been allowed into. Once paired, the remote
    /// stays on screen and reconnects quietly instead of going back to setup.
    var isPaired: Bool {
        guard let host else { return false }
        return pairings.key(for: host) != nil
    }

    /// The app went to the background: iOS will kill the socket anyway, so close it cleanly.
    func suspend() {
        guard isPaired else { return }
        close()
        retries = 0
        state = .idle
    }

    func reconnect() {
        guard let host, state != .connected, state != .connecting, state != .waitingForApproval else { return }
        connect(to: host)
    }

    /// Forget the current TV. If there's another one, switch to it.
    func forget() {
        guard let host else { return }
        pairings.forget(host)
        saved = pairings.saved
        close()
        if let next = saved.first {
            connect(to: next.host)
        } else {
            UserDefaults.standard.removeObject(forKey: "host")
            self.host = nil
            state = .idle
        }
    }

    private func open() {
        guard let host else { return }
        close()
        state = .connecting
        // Newer firmware only answers on the TLS port; older firmware only on the plain one.
        let url = URL(string: secure ? "wss://\(host):3001" : "ws://\(host):3000")!
        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()
        listen(on: task)
        register()
        // Give up if the TV doesn't answer, instead of spinning forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, self.socket === task, self.state == .connecting else { return }
            if self.secure {
                self.secure = false
                self.open()
            } else {
                self.close()
                self.state = .failed("No TV answered at \(host). Check the address and that the TV is on.")
                self.retryIfPaired()
            }
        }
    }

    func cancel() {
        close()
        state = .idle
    }

    private func close() {
        socket?.cancel(with: .goingAway, reason: nil)
        pointer?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pointer = nil
        replies.values.forEach { $0.resume(throwing: CancellationError()) }
        replies = [:]
        subscriptions = [:]
    }

    private func register() {
        send(WebOS.registration(key: host.flatMap(pairings.key(for:))))
    }

    private func listen(on task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while true {
                do {
                    let message = try await task.receive()
                    guard case .string(let text) = message,
                          let data = text.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }
                    self?.handle(json)
                } catch {
                    self?.dropped(task, error)
                    return
                }
            }
        }
    }

    private func dropped(_ task: URLSessionWebSocketTask, _ error: Error) {
        guard task === socket else { return }
        if secure && state == .connecting {
            secure = false
            open()
            return
        }
        close()
        state = .failed("Couldn't reach the TV. Check it's on and on the same Wi-Fi.")
        retryIfPaired()
    }

    /// Paired TVs get quick quiet retries (1s, 2s, 4s, 8s), then one every 5s for as long
    /// as Pilot is open: a TV that's just been turned on can take a minute to join the
    /// Wi-Fi, and stopping early left it looking off while it was on. Leaving the app
    /// (suspend) stops the retries. Every so often we also look for it at a new address.
    private func retryIfPaired() {
        unreachable = true
        guard isPaired else { return }
        if retries % 12 == 0, !waking { Task { await relocate() } }
        let delay = retries < 4 ? 1 << retries : 5
        retries += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, case .failed = self.state else { return }
            self.secure = true
            self.open()
        }
    }

    private func handle(_ json: [String: Any]) {
        let id = json["id"] as? String ?? ""
        let type = json["type"] as? String ?? ""
        let payload = json["payload"] as? [String: Any] ?? [:]

        if let reply = WebOS.registerReply(json) {
            switch reply {
            case .prompt:
                state = .waitingForApproval
            case .registered(let key):
                if let key, let host { pairings.setKey(key, for: host) }
                state = .connected
                retries = 0
                unreachable = false
                if let host, !saved.contains(where: { $0.host == host }) {
                    save(saved + [SavedTV(host: host, name: saved.isEmpty ? "Living room" : "TV \(saved.count + 1)")])
                }
                adding = false
                hostBeforeAdding = nil
                Task { await didConnect() }
            case .refused:
                close()
                state = .failed("The TV said no. Try again and press OK on the TV.")
            }
            return
        }

        if let handler = subscriptions[id] {
            handler(payload)
        } else if let reply = replies.removeValue(forKey: id) {
            if type == "error" {
                reply.resume(throwing: TVError(message: json["error"] as? String ?? "Request failed"))
            } else {
                reply.resume(returning: payload)
            }
        }
    }

    private func didConnect() async {
        await openPointer()
        await loadInputs()
        await learnAddress()
        subscribe("ssap://com.webos.applicationManager/getForegroundAppInfo") { [weak self] payload in
            self?.foreground = payload["appId"] as? String
            if let self { LiveRemote.update(self) }
        }
        subscribe("ssap://com.webos.service.ime/registerRemoteKeyboard") { [weak self] payload in
            log("\(self?.foreground ?? "?") keyboard \(payload)", "ime")
            if let widget = payload["currentWidget"] as? [String: Any] {
                self?.keyboardOpen = widget["focus"] as? Bool ?? false
            }
        }
        subscribe("ssap://com.webos.media/getForegroundAppInfo") { [weak self] payload in
            let info = (payload["foregroundAppInfo"] as? [[String: Any]])?.first
            log("\(self?.foreground ?? "?"): \(info?["playState"] as? String ?? "none")", "media")
            self?.playState = info?["playState"] as? String
        }
        subscribe("ssap://audio/getVolume") { [weak self] payload in
            let status = WebOS.volume(from: payload)
            if let level = status.level { self?.volume = level }
            if let mute = status.muted { self?.muted = mute }
            if let self { LiveRemote.update(self) }
        }
        let launch = try? await request("ssap://com.webos.applicationManager/listLaunchPoints")
        dump(launch, "launchpoints")
        if let launch { apps = WebOS.apps(from: launch) }
    }

    // MARK: Requests

    private func send(_ object: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return }
        socket.send(.string(text)) { _ in }
    }

    @discardableResult
    func request(_ uri: String, _ payload: [String: Any] = [:]) async throws -> [String: Any] {
        nextID += 1
        let id = "req_\(nextID)"
        return try await withCheckedThrowingContinuation { continuation in
            replies[id] = continuation
            send(WebOS.request(id: id, uri: uri, payload: payload))
        }
    }

    private func subscribe(_ uri: String, _ handler: @escaping ([String: Any]) -> Void) {
        nextID += 1
        let id = "sub_\(nextID)"
        subscriptions[id] = handler
        send(["type": "subscribe", "id": id, "uri": uri, "payload": [:]])
    }

    /// Fire and forget, for buttons.
    func run(_ uri: String, _ payload: [String: Any] = [:]) {
        Task { try? await request(uri, payload) }
    }

    // MARK: Pointer socket (buttons, trackpad)

    private func openPointer() async {
        guard let payload = try? await request("ssap://com.webos.service.networkinput/getPointerInputSocket"),
              var path = payload["socketPath"] as? String
        else { return }
        if secure, path.hasPrefix("ws://") {
            path = path.replacingOccurrences(of: "ws://", with: "wss://")
                .replacingOccurrences(of: ":3000/", with: ":3001/")
        }
        guard let url = URL(string: path) else { return }
        let task = session.webSocketTask(with: url)
        pointer = task
        task.resume()
    }

    private func sendPointer(_ lines: String) {
        pointer?.send(.string(lines + "\n\n")) { _ in }
    }

    func press(_ button: Button) {
        sendPointer("type:button\nname:\(button.rawValue)")
    }

    func move(dx: Double, dy: Double) {
        sendPointer("type:move\ndx:\(Int(dx.rounded()))\ndy:\(Int(dy.rounded()))\ndown:0")
    }

    func click() {
        sendPointer("type:click")
    }

    func scroll(dy: Double) {
        sendPointer("type:scroll\ndx:0\ndy:\(Int(dy.rounded()))")
    }

    /// Names the TV's pointer socket understands, same as the physical remote's keys.
    enum Button: String {
        case up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT"
        case enter = "ENTER", back = "BACK", exit = "EXIT", home = "HOME", settings = "MENU"
        case play = "PLAY", pause = "PAUSE", rewind = "REWIND", fastForward = "FASTFORWARD"
        case red = "RED", green = "GREEN", yellow = "YELLOW", blue = "BLUE"
        case info = "INFO", guide = "GUIDE", captions = "CC", dash = "DASH"
    }



    // MARK: Everything else

    var foregroundApp: App? { apps.first { $0.id == foreground } }

    /// Sets the level directly (dragging the volume bar). Shown right away, confirmed by the TV.
    func setVolume(_ level: Int) {
        volume = level
        run("ssap://audio/setVolume", ["volume": level])
    }

    func volumeUp() { run("ssap://audio/volumeUp") }
    func volumeDown() { run("ssap://audio/volumeDown") }
    func toggleMute() { run("ssap://audio/setMute", ["mute": !muted]) }
    // MARK: Turning on

    /// Waking up: the magic packet's gone out and we're waiting for the TV to answer.
    @Published private(set) var waking = false
    /// A try has failed since the TV last answered: it's off, or not on this Wi-Fi.
    @Published private(set) var unreachable = false

    // MARK: Finding a TV that moved

    private var relocating = false

    /// The router can hand the TV a new address, and then the saved one stops answering.
    /// Look over the Wi-Fi for a TV we don't know and offer it our pairing: only the TV we
    /// paired with accepts it, and then the pairing, name and wake address move over.
    private func relocate() async {
        guard !relocating, let old = host, let key = pairings.key(for: old) else { return }
        relocating = true
        defer { relocating = false }
        let answering = await TVFinder.find(with: self)
        let moved = await Finding.moved(from: old, known: Set(saved.map(\.host)), answering: answering) { address in
            // Stop asking if it came back at the old address meanwhile.
            guard self.host == old, self.state != .connected else { return false }
            return await self.accepts(address, key: key)
        }
        guard let moved, host == old, state != .connected else { return }
        log("\(old) moved to \(moved)", "relocate")
        pairings.move(from: old, to: moved)
        saved = pairings.saved
        connect(to: moved)
    }

    /// Whether the TV at `address` already knows our pairing key. A TV that doesn't
    /// would ask to pair, so we hang up as soon as it says so.
    private func accepts(_ address: String, key: String) async -> Bool {
        guard let url = URL(string: "wss://\(address):3001") else { return false }
        let task = session.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }
        guard let data = try? JSONSerialization.data(withJSONObject: WebOS.registration(key: key)),
              let text = String(data: data, encoding: .utf8) else { return false }
        try? await task.send(.string(text))
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                while let message = try? await task.receive() {
                    guard case .string(let text) = message,
                          let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
                    else { continue }
                    switch WebOS.registerReply(json) {
                    case .registered: return true
                    case .prompt, .refused: return false
                    case nil: continue
                    }
                }
                return false
            }
            group.addTask { try? await Task.sleep(for: .seconds(4)); return false }
            let answer = await group.next() ?? false
            group.cancelAll()
            task.cancel(with: .goingAway, reason: nil)
            return answer
        }
    }

    /// The TV can be woken: we've learned its network (MAC) address.
    var canWake: Bool { host.flatMap(pairings.mac(for:)) != nil }

    /// Learns the TV's network address while it's on, so it can be woken later.
    private func learnAddress() async {
        guard let host else { return }
        guard let info = try? await request("ssap://com.webos.service.connectionmanager/getinfo") else { return }
        if let mac = WebOS.macAddress(from: info) { pairings.setMac(mac, for: host) }
    }

    /// Wake-on-LAN. iOS won't let us broadcast, so the packet goes straight to the
    /// TV's address; then we keep trying to reconnect for a while.
    func wake() {
        guard let host, let mac = pairings.mac(for: host), let packet = WebOS.wakePacket(mac: mac) else { return }
        for port in [9, 7] as [UInt16] {
            let link = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
            link.start(queue: .main)
            link.send(content: packet, completion: .contentProcessed { _ in link.cancel() })
        }
        waking = true
        Task {
            for _ in 0..<8 {
                try? await Task.sleep(for: .seconds(3))
                if state == .connected { break }
                if state != .connecting { connect(to: host) }
            }
            waking = false
        }
    }

    func powerOff() {
        run("ssap://system/turnOff")
        LiveRemote.end()
    }
    func switchInput(_ input: Input) { run("ssap://tv/switchInput", ["inputId": input.id]) }

    func loadInputs() async {
        let result: [String: Any]
        do { result = try await request("ssap://tv/getExternalInputList") }
        catch { dump(["error": error.localizedDescription], "inputs"); return }
        dump(result, "inputs")
        inputs = WebOS.inputs(from: result)
    }
    func launch(_ app: App) { run("ssap://system.launcher/launch", ["id": app.id]) }
    func play() { run("ssap://media.controls/play") }
    func pause() { run("ssap://media.controls/pause") }

    // MARK: Typing

    func type(_ text: String) { ime("insertText", ["text": text, "replace": 0]) }
    func deleteCharacters(_ count: Int) { ime("deleteCharacters", ["count": count]) }
    func sendEnter() { ime("sendEnterKey") }

    // MARK: Screenshot

    /// Asks the TV for a still of the screen and downloads it. Protected video
    /// (Netflix and the like, most HDMI video) comes back black: that's the TV's rule.
    func screenshot() async throws -> UIImage {
        let reply = try await request("ssap://tv/executeOneShot", ["path": "/tmp/capture.jpg", "method": "DISPLAY", "format": "JPG"])
        log("screenshot → \(reply)", "capture")
        guard let uri = reply["imageUri"] as? String, let url = URL(string: uri) else {
            throw TVError(message: "The TV didn't send a picture.")
        }
        let (data, _) = try await session.data(from: url)
        guard let image = UIImage(data: data) else { throw TVError(message: "The TV's picture didn't load.") }
        return image
    }

    /// YouTube's TV app draws its own keyboard and ignores typed text, so we
    /// open its search results directly instead.
    static let youtube = "youtube.leanback.v4"

    func searchYouTube(_ query: String) {
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name: "launch", value: "voice"), URLQueryItem(name: "vq", value: query)]
        let target = "https://www.youtube.com/tv?\(parts.percentEncodedQuery ?? "")"
        Task {
            // Hand the search to YouTube as it is; no closing and reopening.
            let reply = try? await request("ssap://system.launcher/launch", ["id": Self.youtube, "params": ["contentTarget": target]])
            log("youtube search \(target) → \(reply ?? [:])", "ime")
        }
    }

    /// Sends to the TV's system keyboard, logging whether it took it.
    private func ime(_ method: String, _ payload: [String: Any] = [:]) {
        Task {
            do {
                let reply = try await request("ssap://com.webos.service.ime/\(method)", payload)
                log("\(foreground ?? "?") \(method) \(payload) → \(reply)", "ime")
            } catch {
                log("\(foreground ?? "?") \(method) \(payload) → error \(error.localizedDescription)", "ime")
            }
        }
    }
}

/// Saves a raw TV response to the app's Documents folder, for debugging from the Mac.
private func dump(_ object: [String: Any]?, _ name: String) {
    guard let object,
          let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
          let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    try? data.write(to: dir.appendingPathComponent("\(name).json"))
}

/// Appends a line to Documents/<name>.log, for debugging from the Mac.
func log(_ line: String, _ name: String) {
    guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let url = dir.appendingPathComponent("\(name).log")
    let entry = Data("\(Date().formatted(date: .omitted, time: .standard)) \(line)\n".utf8)
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(entry)
        try? handle.close()
    } else {
        try? entry.write(to: url)
    }
}

struct TVError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The TV's TLS port uses a self-signed certificate. Accept it only for
/// addresses on the local network, never for anything on the internet.
final class LocalTrust: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let host = challenge.protectionSpace.host
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           Self.isLocal(host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    static func isLocal(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return host.hasSuffix(".local") }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}
