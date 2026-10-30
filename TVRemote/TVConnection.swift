import Foundation
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

    struct App: Identifiable, Hashable {
        let id: String
        let title: String
        let icon: URL?
        var color: String? = nil
    }

    struct Input: Identifiable, Hashable {
        let id: String
        let label: String
        let connected: Bool
        var port: Int? = nil
        var signal = false
    }

    // MARK: Icons

    /// The TV serves icons over its self-signed TLS port, so they load
    /// through our own session (which trusts it) rather than AsyncImage.
    private let icons = NSCache<NSURL, UIImage>()

    func image(_ url: URL) async -> UIImage? {
        if let cached = icons.object(forKey: url as NSURL) { return cached }
        guard let (data, _) = try? await session.data(from: url), let image = UIImage(data: data) else { return nil }
        icons.setObject(image, forKey: url as NSURL)
        return image
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
    @Published private(set) var host: String? = UserDefaults.standard.string(forKey: "host")

    /// Every TV this phone has paired with.
    struct SavedTV: Codable, Hashable, Identifiable {
        var host: String
        var name: String
        var id: String { host }
    }
    @Published private(set) var saved: [SavedTV] = {
        guard let data = UserDefaults.standard.data(forKey: "tvs"),
              let list = try? JSONDecoder().decode([SavedTV].self, from: data) else { return [] }
        return list
    }()
    /// Showing setup to add another TV, while staying paired with this one.
    @Published var adding = false
    private var hostBeforeAdding: String?

    var current: SavedTV? { saved.first { $0.host == host } }

    init() {
        // Phones paired before there was a TV list: keep that TV.
        if saved.isEmpty, let host, UserDefaults.standard.string(forKey: "key.\(host)") != nil {
            save([SavedTV(host: host, name: "Living room")])
        }
    }

    private func save(_ list: [SavedTV]) {
        saved = list
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "tvs")
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
        foreground = "Netflix"
        saved = [SavedTV(host: "192.168.1.20", name: "Living room"), SavedTV(host: "192.168.1.31", name: "Upstairs")]
        apps = ["Netflix", "Prime Video", "Disney+", "YouTube", "Apple TV", "Spotify", "LG Channels", "Twitch"]
            .map { App(id: $0, title: $0, icon: nil) }
        inputs = [Input(id: "HDMI_1", label: "HDMI 1", connected: true),
                  Input(id: "HDMI_2", label: "PlayStation 5", connected: true),
                  Input(id: "HDMI_3", label: "HDMI 3", connected: false)]
        state = .connected
    }
    #endif

    /// A TV this phone has already been allowed into. Once paired, the remote
    /// stays on screen and reconnects quietly instead of going back to setup.
    var isPaired: Bool {
        guard let host else { return false }
        return UserDefaults.standard.string(forKey: "key.\(host)") != nil
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
        UserDefaults.standard.removeObject(forKey: "key.\(host)")
        save(saved.filter { $0.host != host })
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
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "permissions": [
                    "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE",
                    "CONTROL_AUDIO", "CONTROL_POWER", "CONTROL_DISPLAY",
                    "CONTROL_INPUT_JOYSTICK", "CONTROL_INPUT_MEDIA_PLAYBACK",
                    "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_INPUT_TV",
                    "READ_INSTALLED_APPS", "READ_RUNNING_APPS", "READ_APP_STATUS",
                    "READ_POWER_STATE", "READ_SETTINGS", "READ_INPUT_DEVICE_LIST",
                    "WRITE_NOTIFICATION_TOAST",
                ],
            ],
        ]
        if let host, let key = UserDefaults.standard.string(forKey: "key.\(host)") {
            payload["client-key"] = key
        }
        send(["type": "register", "id": "register", "payload": payload])
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

    /// Paired TVs get a few quiet retries (1s, 2s, 4s, 8s) before we stop and wait
    /// for the app to come back to the front.
    private func retryIfPaired() {
        guard isPaired, retries < 4 else { return }
        let delay = 1 << retries
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

        if id == "register" {
            switch type {
            case "response" where payload["pairingType"] as? String == "PROMPT":
                state = .waitingForApproval
            case "registered":
                if let key = payload["client-key"] as? String, let host {
                    UserDefaults.standard.set(key, forKey: "key.\(host)")
                }
                state = .connected
                retries = 0
                if let host, !saved.contains(where: { $0.host == host }) {
                    save(saved + [SavedTV(host: host, name: saved.isEmpty ? "Living room" : "TV \(saved.count + 1)")])
                }
                adding = false
                hostBeforeAdding = nil
                Task { await didConnect() }
            case "error":
                close()
                state = .failed("The TV said no. Try again and press OK on the TV.")
            default:
                break
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
        subscribe("ssap://com.webos.applicationManager/getForegroundAppInfo") { [weak self] payload in
            self?.foreground = payload["appId"] as? String
        }
        subscribe("ssap://com.webos.media/getForegroundAppInfo") { [weak self] payload in
            let info = (payload["foregroundAppInfo"] as? [[String: Any]])?.first
            log("\(self?.foreground ?? "?"): \(info?["playState"] as? String ?? "none")", "media")
            self?.playState = info?["playState"] as? String
        }
        subscribe("ssap://audio/getVolume") { [weak self] payload in
            let status = payload["volumeStatus"] as? [String: Any] ?? payload
            if let level = status["volume"] as? Int { self?.volume = level }
            if let mute = (status["muteStatus"] ?? status["muted"]) as? Bool { self?.muted = mute }
        }
        let launch = try? await request("ssap://com.webos.applicationManager/listLaunchPoints")
        dump(launch, "launchpoints")
        if let payload = launch,
           let points = payload["launchPoints"] as? [[String: Any]] {
            apps = points.compactMap { point in
                guard let id = point["id"] as? String, let title = point["title"] as? String else { return nil }
                let icon = (point["largeIcon"] as? String) ?? (point["icon"] as? String)
                return App(id: id, title: title, icon: icon.flatMap(URL.init(string:)), color: point["iconColor"] as? String)
            }
        }
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
            send(["type": "request", "id": id, "uri": uri, "payload": payload])
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
    func powerOff() { run("ssap://system/turnOff") }
    func switchInput(_ input: Input) { run("ssap://tv/switchInput", ["inputId": input.id]) }

    func loadInputs() async {
        let result: [String: Any]
        do { result = try await request("ssap://tv/getExternalInputList") }
        catch { dump(["error": error.localizedDescription], "inputs"); return }
        dump(result, "inputs")
        guard let payload = Optional(result),
              let devices = payload["devices"] as? [[String: Any]] else { return }
        inputs = devices.compactMap { device in
            guard let id = device["id"] as? String else { return nil }
            return Input(id: id, label: device["label"] as? String ?? id,
                         connected: device["connected"] as? Bool ?? false,
                         port: device["port"] as? Int,
                         signal: device["hdmiSignalExist"] as? Bool ?? false)
        }
    }
    func launch(_ app: App) { run("ssap://system.launcher/launch", ["id": app.id]) }
    func play() { run("ssap://media.controls/play") }
    func pause() { run("ssap://media.controls/pause") }

    func type(_ text: String) {
        run("ssap://com.webos.service.ime/insertText", ["text": text, "replace": 0])
    }

    func deleteCharacters(_ count: Int) {
        run("ssap://com.webos.service.ime/deleteCharacters", ["count": count])
    }

    func sendEnter() { run("ssap://com.webos.service.ime/sendEnterKey") }
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
private func log(_ line: String, _ name: String) {
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
