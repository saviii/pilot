import AVKit
import SwiftUI

/// Typing on the TV. Most apps take text live through LG's keyboard; YouTube
/// draws its own and ignores it, so there the field becomes a YouTube search,
/// with one choice of where it plays: the TV's YouTube, or the console (cast
/// from your phone, since text can't get through HDMI).
struct KeyboardSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var text = ""
    @State private var onConsole = false
    @FocusState private var focused: Bool
    @AppStorage("recentSearches") private var recentRaw = ""

    /// An HDMI input is on screen: text can't reach it, only the TV's own apps.
    private var input: TVConnection.Input? { tv.foregroundInput }
    /// A console you could play YouTube on instead: the input on screen, or a PlayStation plugged in.
    private var console: TVConnection.Input? {
        input ?? tv.inputs.first { $0.connected && $0.label.contains("PlayStation") }
    }
    /// YouTube search mode: YouTube's on screen, or you're on an input (nothing else can take text there).
    private var youtube: Bool { tv.foreground == TVConnection.youtube || input != nil }
    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if youtube, let app = tv.apps.first(where: { $0.id == TVConnection.youtube }) {
                    AppIcon(app: app, radius: 10, inset: 3).frame(width: 36, height: 36)
                } else if let app = tv.foregroundApp {
                    AppIcon(app: app, radius: 10, inset: 3).frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(youtube ? "Search YouTube" : "Type on \(tv.current?.name ?? "the TV")").font(.headline)
                    Caption(subtitle)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 12) {
                Image(systemName: youtube ? "magnifyingglass" : "keyboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                TextField(youtube ? "Search YouTube" : "Type", text: $text)
                    .font(.title3)
                    .tint(Theme.accent)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(youtube ? .search : .send)
                    .onSubmit { submit() }
                if !text.isEmpty {
                    Button {
                        if !youtube { tv.deleteCharacters(text.count) }
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.muted)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(Theme.key, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(focused ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1))
            .animation(.easeOut(duration: 0.15), value: text.isEmpty)
            .animation(.easeOut(duration: 0.15), value: focused)
            .onChange(of: text) { old, new in
                guard !youtube else { return }
                if new.hasPrefix(old) {
                    tv.type(String(new.dropFirst(old.count)))
                } else if old.hasPrefix(new) {
                    tv.deleteCharacters(old.count - new.count)
                } else {
                    tv.deleteCharacters(old.count)
                    tv.type(new)
                }
            }

            // Where it plays.
            if youtube, let console {
                HStack(spacing: 4) {
                    segment("The TV", symbol: "tv", on: !onConsole) { onConsole = false }
                    segment(console.label, symbol: console.label.contains("PlayStation") ? "gamecontroller" : "cable.connector",
                            on: onConsole) { onConsole = true }
                }
                .padding(4)
                .background(Theme.key, in: RoundedRectangle(cornerRadius: 16))
                .animation(.easeOut(duration: 0.15), value: onConsole)
            }

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Caption("Recent")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recents, id: \.self) { query in
                                Button {
                                    haptic()
                                    if !youtube { tv.deleteCharacters(text.count) }
                                    text = query
                                    submit()
                                } label: {
                                    Text(query)
                                        .font(Theme.mono(12))
                                        .lineLimit(1)
                                        .padding(.horizontal, 14)
                                        .frame(height: 36)
                                }
                                .buttonStyle(KeyStyle(shape: Capsule()))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contentMargins(.horizontal, 24, for: .scrollContent)
                    .padding(.horizontal, -24)
                }
            }
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .onAppear {
            // On the console already? Play there by default. And on an input you're
            // probably not typing yet, so the phone keyboard waits for a tap.
            onConsole = input != nil
            focused = input == nil
        }
    }

    private var subtitle: String {
        guard youtube else { return "Shows on the TV as you type" }
        if onConsole { return "Cast from your phone" }
        return "Results open on the TV"
    }

    private func segment(_ title: String, symbol: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button {
            haptic()
            pick()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.subheadline.weight(on ? .semibold : .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(on ? Theme.background : Theme.ink)
            .background(on ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(Pressable())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Search goes where "Play on" says: the TV's YouTube, or YouTube on this phone
    /// to cast to the console. Outside YouTube, it's the TV's Enter key.
    private func submit() {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        haptic(.medium)
        if youtube && onConsole {
            var parts = URLComponents(string: "https://www.youtube.com/results")!
            parts.queryItems = [URLQueryItem(name: "search_query", value: query)]
            if let url = parts.url { openURL(url) }
        } else if youtube {
            tv.searchYouTube(query)
        } else {
            tv.sendEnter()
        }
        recentRaw = ([query] + recents.filter { $0 != query }).prefix(6).joined(separator: "\n")
        dismiss()
    }
}

struct InputsSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Inputs").padding(.bottom, 6)
            ForEach(tv.inputs) { input in
                Key(shape: RoundedRectangle(cornerRadius: 16), action: {
                    tv.switchInput(input)
                    dismiss()
                }) {
                    HStack(spacing: 14) {
                        Text(input.port.map { String($0) } ?? "")
                            .font(Theme.dot(26))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(input.label).font(.body.weight(.medium))
                            Caption(input.signal ? "HDMI \(input.port ?? 0) · On" : "HDMI \(input.port ?? 0)")
                        }
                        Spacer()
                        Circle()
                            .fill(input.signal ? Theme.accent : Theme.muted.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 64)
                }
            }
            if tv.inputs.isEmpty {
                Text("No inputs found.").foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(24)
        .task { await tv.loadInputs() }
    }
}

/// Edit the top strip, in the strip's own language: tiles. What's on top is
/// numbered in order; hold and drag a tile onto another to move it. Tap any tile
/// to move it between the two sections; its badge says which way it'll go.
struct AppsSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @Namespace private var tiles
    @State private var query = ""
    @State private var target: String?
    private let pins = Pins()

    private var pinned: [TVConnection.App] {
        pins.ids.compactMap { id in tv.apps.first { $0.id == id } }
    }
    private var others: [TVConnection.App] {
        let rest = tv.apps.filter { !pins.contains($0.id) }
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? rest : rest.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your apps").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Caption("On top")
                        Spacer()
                        if pinned.count > 1 { Caption("Hold to move") }
                    }
                    if pinned.isEmpty {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Theme.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 6]))
                            .frame(height: 96)
                            .overlay(Text("Tap apps below to put them here").font(.subheadline).foregroundStyle(Theme.muted))
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(Array(pinned.enumerated()), id: \.element.id) { index, app in
                                tile(app, number: index + 1, badge: "minus", tint: Theme.ink) { toggle(app) }
                                    .draggable(app.id) {
                                        AppIcon(app: app, radius: 16, inset: 7).frame(width: 64, height: 64)
                                            .environmentObject(tv)
                                    }
                                    .dropDestination(for: String.self) { items, _ in
                                        guard let id = items.first else { return false }
                                        haptic(.medium)
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            pins.place(id, at: app.id, visible: pinned.map(\.id))
                                        }
                                        return true
                                    } isTargeted: { over in
                                        target = over ? app.id : (target == app.id ? nil : target)
                                    }
                            }
                        }
                    }

                    Caption("Add apps").padding(.top, 14)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        TextField("Find an app", text: $query)
                            .tint(Theme.accent)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Theme.key, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(others) { app in
                            tile(app, number: nil, badge: "plus", tint: Theme.accent) { toggle(app) }
                        }
                    }
                    if others.isEmpty {
                        Text(query.isEmpty ? "Everything's on top." : "No app called \u{201C}\(query)\u{201D}.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .foregroundStyle(Theme.ink)
    }

    /// One app: its tile, a badge for what a tap does, and its name (numbered when on top).
    private func tile(_ app: TVConnection.App, number: Int?, badge: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            VStack(spacing: 8) {
                AppIcon(app: app, radius: 16, inset: 7)
                    .frame(width: 64, height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.accent, lineWidth: 2)
                            .opacity(target == app.id ? 1 : 0)
                    )
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: badge)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(tint == Theme.accent ? Theme.background : Theme.ink)
                            .frame(width: 22, height: 22)
                            .background(tint == Theme.accent ? Theme.accent : Theme.key, in: Circle())
                            .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                            .offset(x: 7, y: -7)
                    }
                    .matchedGeometryEffect(id: app.id, in: tiles)
                HStack(spacing: 4) {
                    if let number {
                        Text("\(number)").font(Theme.dot(13)).foregroundStyle(Theme.accent)
                    }
                    Text(app.title)
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .lineLimit(1)
                }
                .frame(maxWidth: 80)
            }
        }
        .buttonStyle(Pressable())
        .animation(.easeOut(duration: 0.15), value: target)
    }

    private func toggle(_ app: TVConnection.App) {
        withAnimation(.easeInOut(duration: 0.25)) { pins.toggle(app.id) }
    }
}

/// Your TVs: switch, rename or forget the current one, add another.
struct TVsSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var name = ""
    @State private var confirmForget = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your TVs").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 8)

            ForEach(tv.saved) { saved in
                if saved.host == tv.host {
                    current(saved)
                    inputs
                } else {
                    other(saved)
                }
            }

            Button {
                haptic()
                dismiss()
                tv.startAdding()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                    Text("Add a TV").font(.body.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 68)
                .foregroundStyle(Theme.muted)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 6]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(Pressable())

            Spacer(minLength: 0)
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .confirmationDialog("Forget \(tv.current?.name ?? "this TV")?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                tv.forget()
                dismiss()
            }
        } message: {
            Text("You'll need to press OK on the TV again to pair it.")
        }
    }

    // MARK: Cards

    private func current(_ saved: TVConnection.SavedTV) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                glyph(active: true)
                VStack(alignment: .leading, spacing: 4) {
                    if editing {
                        TextField("Name", text: $name)
                            .font(.title3.weight(.semibold))
                            .tint(Theme.accent)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(save)
                    } else {
                        Text(saved.name).font(.title3.weight(.semibold))
                    }
                    HStack(spacing: 6) {
                        Circle().fill(tv.state == .connected ? Theme.accent : Theme.muted).frame(width: 5, height: 5)
                        Caption(tv.state == .connected ? "Connected" : "Reconnecting")
                    }
                }
                Spacer()
                if let volume = tv.volume, tv.state == .connected {
                    Text(tv.muted ? "--" : String(format: "%02d", volume))
                        .font(Theme.dot(26))
                        .foregroundStyle(tv.muted ? Theme.muted : Theme.accent)
                }
            }

            // What it's doing right now: the app on screen, and which input it's on.
            if tv.state == .connected {
                HStack(spacing: 8) {
                    chip {
                        if let app = tv.foregroundApp {
                            AppIcon(app: app, radius: 6, inset: 2).frame(width: 22, height: 22)
                            Text(app.title).font(.subheadline).lineLimit(1)
                        } else {
                            Image(systemName: "house").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                            Text(tv.foregroundInput?.label ?? "Home").font(.subheadline).lineLimit(1)
                        }
                    }
                    if let input = tv.foregroundInput ?? tv.inputs.first(where: { $0.signal }) {
                        chip {
                            Text(input.port.map(String.init) ?? "").font(Theme.dot(16)).foregroundStyle(Theme.accent)
                            Text(input.label).font(.subheadline).lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: 20) {
                if editing {
                    action("Save", Theme.accent, save)
                    action("Cancel", Theme.muted) { editing = false }
                } else {
                    action("Rename", Theme.ink) {
                        name = saved.name
                        editing = true
                        focused = true
                    }
                    action("TV settings", Theme.ink) {
                        tv.press(.settings)
                        dismiss()
                    }
                    action("Forget", Theme.muted) { confirmForget = true }
                }
            }
            .padding(.leading, 2)
        }
        .padding(16)
        .background(Theme.key, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.accent.opacity(0.55), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: editing)
    }

    /// This TV's HDMI inputs: tap one to switch to it.
    @ViewBuilder
    private var inputs: some View {
        if !tv.inputs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tv.inputs) { input in
                        let on = tv.foreground == input.appId
                        Button {
                            haptic()
                            tv.switchInput(input)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Text(input.port.map(String.init) ?? "").font(Theme.dot(18)).foregroundStyle(on ? Theme.background : Theme.accent)
                                Text(input.label).font(.subheadline.weight(.medium)).lineLimit(1)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .foregroundStyle(on ? Theme.background : Theme.ink)
                            .background(on ? Theme.accent : Theme.key, in: Capsule())
                            .overlay(Capsule().stroke(Theme.hairline))
                        }
                        .buttonStyle(Pressable())
                    }
                }
                .padding(.vertical, 2)
            }
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .padding(.horizontal, -24)
        }
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func other(_ saved: TVConnection.SavedTV) -> some View {
        Key(shape: RoundedRectangle(cornerRadius: 18), action: {
            tv.connect(to: saved.host)
            dismiss()
        }) {
            HStack(spacing: 14) {
                glyph(active: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(saved.name).font(.title3.weight(.semibold))
                    Caption(saved.host)
                }
                Spacer()
                Caption("Switch")
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.background, in: Capsule())
            }
            .padding(14)
        }
    }

    private func glyph(active: Bool) -> some View {
        Image(systemName: "tv")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(active ? Theme.accent : Theme.muted)
            .frame(width: 40, height: 40)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func action(_ title: String, _ color: Color, _ run: @escaping () -> Void) -> some View {
        Button(title.uppercased(), action: run)
            .font(Theme.mono(11))
            .tracking(1)
            .foregroundStyle(color)
            .frame(height: 28)
    }

    private var status: String {
        guard tv.state == .connected else { return "Reconnecting · \(tv.host ?? "")" }
        if let app = tv.foregroundApp { return "Connected · \(app.title)" }
        return "Connected · \(tv.host ?? "")"
    }

    private func save() {
        tv.rename(to: name)
        editing = false
    }
}


/// A still of the TV's screen: save it or send it on.
struct ScreenshotSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failure: String?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Screenshot").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.accent)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Theme.key)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if let failure {
                    Text(failure).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding()
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))

            HStack(spacing: 10) {
                Button {
                    guard let image else { return }
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    haptic(.medium)
                    saved = true
                    // Show "Saved" for a beat, then get out of the way.
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        dismiss()
                    }
                } label: {
                    Label(saved ? "Saved" : "Save to Photos", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(Theme.background)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(Pressable())
                .disabled(image == nil || saved)

                // Always there, so the two buttons never shift; it just wakes up with the picture.
                Group {
                    if let image {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("TV screenshot", image: Image(uiImage: image))) {
                            shareLabel
                        }
                    } else {
                        shareLabel
                    }
                }
            }
            .opacity(image == nil ? 0.5 : 1)
            .animation(.easeOut(duration: 0.15), value: saved)
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task {
            do { image = try await tv.screenshot() }
            catch { failure = "Couldn't get a screenshot: \(error.localizedDescription)" }
        }
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(Theme.ink)
            .background(Theme.key, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
    }
}

/// The Sonos: what it's playing, its TV sound settings and its sleep timer.
/// Every switch here is yours; nothing turns on by itself.
struct SonosSheet: View {
    @EnvironmentObject private var sonos: Sonos
    @Environment(\.dismiss) private var dismiss
    @State private var sleepPick: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "hifispeaker.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(Theme.key, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sonos.room).font(.headline)
                        Caption(sonos.model.isEmpty ? "Sonos" : sonos.model)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.accent)
                }

                nowPlaying
                PlayFromPhone()

                VStack(spacing: 0) {
                    toggle("Speech Enhancement", "Clearer dialogue", isOn: Binding(get: { sonos.speech }, set: sonos.setSpeech))
                    Divider().overlay(Theme.hairline).padding(.leading, 16)
                    toggle("Night Sound", "Quieter loud parts, louder quiet ones", isOn: Binding(get: { sonos.night }, set: sonos.setNight))
                }
                .background(Theme.key, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))

                level("Sub", value: $sonos.sub, range: -15...15, signed: true, commit: sonos.commitSub)
                level("Sonos volume", value: $sonos.volume, range: 0...100, signed: false, commit: sonos.commitVolume)

                sleep
            }
            .padding(24)
        }
        .foregroundStyle(Theme.ink)
        .task {
            // Keep what's showing current while the sheet is open.
            while !Task.isCancelled {
                await sonos.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: What's playing

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.background)
                    if let art = sonos.track?.art {
                        AsyncImage(url: art) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                    } else {
                        Image(systemName: sonos.onTV ? "tv" : sonos.fromAirPlay ? "iphone" : "music.note")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(sonos.onTV ? "TV sound" : sonos.track?.title ?? (sonos.fromAirPlay ? "Your iPhone" : "Nothing playing"))
                        .font(.body.weight(.semibold)).lineLimit(1)
                    Text(sonos.onTV ? "From the TV" : sonos.fromAirPlay ? "From your iPhone · AirPlay" : sonos.track?.artist ?? "Music")
                        .font(.subheadline).foregroundStyle(Theme.ink.opacity(0.65)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if !sonos.onTV {
                HStack(spacing: 8) {
                    small("backward.end.fill", sonos.previous)
                    Button {
                        haptic()
                        sonos.playPause()
                    } label: {
                        Image(systemName: sonos.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(Theme.background)
                            .frame(width: 52, height: 52)
                            .background(Theme.ink, in: Circle())
                    }
                    .buttonStyle(Pressable())
                    small("forward.end.fill", sonos.next)
                    Spacer(minLength: 8)
                    Button {
                        haptic(.medium)
                        sonos.backToTV()
                    } label: {
                        Label("Back to TV", systemImage: "tv")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .foregroundStyle(Theme.background)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(Pressable())
                }
            }
        }
        .padding(14)
        .background(Theme.key, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline))
        .animation(.easeOut(duration: 0.2), value: sonos.onTV)
    }

    private func small(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Theme.background, in: Circle())
        }
        .buttonStyle(Pressable())
    }

    // MARK: Settings

    private func toggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .frame(height: 64)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    private func level(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, signed: Bool, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Caption(title)
                Spacer()
                Text(signed && value.wrappedValue > 0 ? "+\(value.wrappedValue)" : "\(value.wrappedValue)")
                    .font(Theme.dot(22))
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            DotTrack(value: value, range: range, signed: signed, commit: commit)
                .accessibilityLabel(title)
        }
    }

    // MARK: Sleep timer

    private var sleep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Caption("Sleep timer")
                Spacer()
                if let left = sonos.sleepLeft {
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(Theme.dot(20))
                        .foregroundStyle(Theme.accent)
                        .monospacedDigit()
                }
            }
            HStack(spacing: 8) {
                chip("Off", active: sonos.sleepLeft == nil) { sonos.sleep(minutes: nil); sleepPick = nil }
                ForEach([15, 30, 60, 90], id: \.self) { minutes in
                    chip("\(minutes)", active: sonos.sleepLeft != nil && sleepPick == minutes) {
                        sonos.sleep(minutes: minutes)
                        sleepPick = minutes
                    }
                }
            }
        }
    }

    private func chip(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            Text(title)
                .font(Theme.mono(12))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(active ? Theme.background : Theme.ink)
                .background(active ? Theme.accent : Theme.key, in: Capsule())
                .overlay(Capsule().stroke(active ? .clear : Theme.hairline))
        }
        .buttonStyle(Pressable())
    }
}


/// A level drawn as a row of dots with a knob: drag along it, it saves when you let go.
/// Signed levels (the Sub) light from the center mark outwards.
struct DotTrack: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var signed = false
    let commit: () -> Void

    private let dots = 17
    private let knob: CGFloat = 18
    private let ticks = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let span = Double(range.upperBound - range.lowerBound)
            let at = Double(value - range.lowerBound) / span
            let zero = signed ? Double(-range.lowerBound) / span : 0
            let travel = geo.size.width - knob

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<dots, id: \.self) { i in
                        let f = Double(i) / Double(dots - 1)
                        Circle()
                            .fill(lit(f, at: at, zero: zero) ? Theme.accent : Theme.muted.opacity(0.3))
                            .frame(width: 5, height: 5)
                        if i < dots - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, knob / 2 - 2.5)
                if signed {
                    Capsule().fill(Theme.muted)
                        .frame(width: 2, height: 14)
                        .offset(x: zero * travel + knob / 2 - 1)
                }
                Circle()
                    .fill(Theme.ink)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: at * travel)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let f = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                        let next = range.lowerBound + Int((f * span).rounded())
                        if next != value {
                            value = next
                            ticks.selectionChanged()
                        }
                    }
                    .onEnded { _ in commit() }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            value = min(max(value + (direction == .increment ? 1 : -1), range.lowerBound), range.upperBound)
            commit()
        }
    }

    private func lit(_ f: Double, at: Double, zero: Double) -> Bool {
        signed ? (f >= min(at, zero) - 0.001 && f <= max(at, zero) + 0.001 && abs(at - zero) > 0.001) : f <= at + 0.001
    }
}


/// Sends this phone's audio to the Sonos (or back) through iOS's own AirPlay
/// picker: the only thing allowed to move a phone's sound. One tap opens it.
struct PlayFromPhone: View {
    @EnvironmentObject private var sonos: Sonos
    @State private var picker = AirPlayPicker()

    var body: some View {
        Button {
            haptic()
            picker.open()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "airplay.audio")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sonos.fromAirPlay ? "Playing from this phone" : "Play from this phone")
                        .font(.body.weight(.semibold))
                    Text(sonos.fromAirPlay ? "Pick iPhone to bring it back" : "Pick \(sonos.room) in the list")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Theme.key, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline))
        }
        .buttonStyle(Pressable())
        .foregroundStyle(Theme.ink)
        .background(picker.view.frame(width: 1, height: 1).opacity(0.02))
    }
}

/// iOS's AirPlay picker, kept off to the side; `open()` presses its button for you.
@MainActor
final class AirPlayPicker {
    private let routes = AVRoutePickerView()

    var view: some View { Holder(routes: routes) }

    func open() {
        guard let button = routes.subviews.compactMap({ $0 as? UIButton }).first else { return }
        button.sendActions(for: .touchUpInside)
    }

    private struct Holder: UIViewRepresentable {
        let routes: AVRoutePickerView
        func makeUIView(context: Context) -> AVRoutePickerView {
            routes.prioritizesVideoDevices = false
            return routes
        }
        func updateUIView(_ view: AVRoutePickerView, context: Context) {}
    }
}

/// Remote settings: how it looks, and the six apps at the bottom of the remote.
struct RemoteSettingsSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system
    @State private var query = ""
    @State private var target: String?
    private let pins = Pins()

    private var six: [TVConnection.App] {
        Array(pins.ids.compactMap { id in tv.apps.first { $0.id == id } }.prefix(6))
    }
    private var full: Bool { six.count >= 6 }
    private var listed: [TVConnection.App] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? tv.apps : tv.apps.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Remote").font(.title2.weight(.bold))
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.accent)
                }

                Caption("Appearance")
                HStack(spacing: 4) {
                    ForEach(Appearance.allCases) { option in
                        let on = appearance == option
                        Button {
                            haptic()
                            appearance = option
                        } label: {
                            Label(option.title, systemImage: option.symbol)
                                .font(.subheadline.weight(on ? .semibold : .medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .foregroundStyle(on ? Theme.background : Theme.ink)
                                .background(on ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(Pressable())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(Theme.key, in: RoundedRectangle(cornerRadius: 16))
                .animation(.easeOut(duration: 0.15), value: appearance)

                Caption("Your six").padding(.top, 6)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in slot(index) }
                }
                Text("Hold a slot to move it. Tap one to clear it.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    TextField("Find an app", text: $query)
                        .tint(Theme.accent)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Theme.key, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                .padding(.top, 4)

                VStack(spacing: 0) {
                    ForEach(Array(listed.enumerated()), id: \.element.id) { index, app in
                        row(app)
                        if index < listed.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 60)
                        }
                    }
                }
                .background(Theme.key, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline))
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.immediately)
        .foregroundStyle(Theme.ink)
    }

    // MARK: Slots

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if index < six.count {
            let app = six[index]
            Button {
                haptic()
                withAnimation(.easeInOut(duration: 0.2)) { pins.remove(app.id) }
            } label: {
                AppIcon(app: app, radius: 9, inset: 2).frame(width: 34, height: 34)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.key, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        // Its place on the remote, as a badge on the corner.
                        Text("\(index + 1)")
                            .font(Theme.dot(11))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 20, height: 20)
                            .background(Theme.background, in: Circle())
                            .overlay(Circle().stroke(Theme.hairline))
                            .offset(x: -4, y: -6)
                    }
                    .overlay(Capsule().stroke(Theme.accent, lineWidth: 2).opacity(target == app.id ? 1 : 0))
            }
            .buttonStyle(Pressable())
            .accessibilityLabel("\(index + 1), \(app.title). Tap to clear")
            .draggable(app.id) {
                AppIcon(app: app, radius: 25, inset: 6).frame(width: 100, height: 50).environmentObject(tv)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first else { return false }
                haptic(.medium)
                withAnimation(.easeInOut(duration: 0.25)) { pins.place(id, at: app.id, visible: six.map(\.id)) }
                return true
            } isTargeted: { over in
                target = over ? app.id : (target == app.id ? nil : target)
            }
        } else {
            let next = index == six.count
            Capsule()
                .strokeBorder(next ? Theme.accent : Theme.muted.opacity(0.4),
                              style: StrokeStyle(lineWidth: next ? 2 : 1.5, lineCap: .round, dash: next ? [6, 5] : [0.1, 6]))
                .background(next ? Theme.accent.opacity(0.06) : .clear, in: Capsule())
                .frame(height: 50)
                .overlay {
                    HStack(spacing: 6) {
                        Text("\(index + 1)").font(Theme.dot(13))
                        if next { Caption("Next").foregroundStyle(Theme.accent) }
                    }
                    .foregroundStyle(next ? Theme.accent : Theme.muted)
                }
        }
    }

    // MARK: Every app

    private func row(_ app: TVConnection.App) -> some View {
        let slot = six.firstIndex { $0.id == app.id }
        return HStack(spacing: 14) {
            AppIcon(app: app, radius: 9, inset: 3).frame(width: 32, height: 32)
            Text(app.title).font(.body.weight(.medium)).lineLimit(1)
            Spacer()
            if let slot {
                Text("\(slot + 1)")
                    .font(Theme.dot(14))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Theme.muted.opacity(0.4), lineWidth: 1.5))
            } else {
                Button {
                    haptic()
                    withAnimation(.easeInOut(duration: 0.2)) { pins.toggle(app.id) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.background)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(Pressable())
                .disabled(full)
                .opacity(full ? 0.3 : 1)
                .accessibilityLabel("Add \(app.title)")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }
}
