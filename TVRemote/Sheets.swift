import SwiftUI

/// Typing on the TV. Most apps take text live through LG's keyboard; YouTube
/// draws its own and ignores it, so there the field becomes a YouTube search.
/// On an HDMI input (the PS5) text can't get through at all: there it's a YouTube
/// search you play on the console (by casting from your phone) or on the TV.
struct KeyboardSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var text = ""
    @FocusState private var focused: Bool
    @AppStorage("recentSearches") private var recentRaw = ""

    /// An HDMI input is on screen: text can't reach it, only the TV's own apps.
    private var input: TVConnection.Input? { tv.foregroundInput }
    /// Search goes to the TV's YouTube: when it's on screen, or when you choose it over an input.
    private var youtube: Bool { tv.foreground == TVConnection.youtube || input != nil }
    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let app = tv.foregroundApp {
                    AppIcon(app: app, radius: 7, inset: 2).frame(width: 32, height: 32)
                }
                if let input {
                    Image(systemName: input.label.contains("PlayStation") ? "gamecontroller.fill" : "cable.connector")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Theme.key, in: RoundedRectangle(cornerRadius: 7))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Caption(subtitle)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.accent)
            }

            if let input {
                Text("Pilot can't type into the \(input.label). Search YouTube here and cast it from your phone, or open it on the TV's own YouTube.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Image(systemName: youtube ? "magnifyingglass" : "keyboard")
                    .font(.system(size: 15, weight: .semibold))
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
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.muted)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Theme.key, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(focused ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1))
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

            if let input {
                HStack(spacing: 10) {
                    destination(input.label, symbol: input.label.contains("PlayStation") ? "gamecontroller.fill" : "cable.connector", primary: true) {
                        submit()
                    }
                    destination("The TV", symbol: "tv", primary: false) {
                        submit(onTV: true)
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .animation(.easeOut(duration: 0.15), value: text.isEmpty)
            }

            if !recents.isEmpty {
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
        .padding(24)
        .foregroundStyle(Theme.ink)
        // On an input you're probably not typing, so don't throw the keyboard up.
        .onAppear { focused = input == nil }
    }

    private var title: String {
        if let input { return "Typing on \(input.label)" }
        return youtube ? "Search YouTube" : "Type on \(tv.current?.name ?? "the TV")"
    }

    private var subtitle: String {
        if let input { return input.port.map { "HDMI \($0)" } ?? "Input" }
        return youtube ? "Results open when you press search" : "Shows on the TV as you type"
    }

    /// "Play on" choice for an input: the console (primary) or the TV's own YouTube.
    private func destination(_ title: String, symbol: String, primary: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(primary ? Theme.background : Theme.ink)
            .background(primary ? Theme.accent : Theme.key, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(primary ? .clear : Theme.hairline))
        }
        .buttonStyle(Pressable())
    }

    /// On an input, search opens YouTube on this phone (cast it to the console from
    /// there) unless you chose the TV. Otherwise it goes to the TV.
    private func submit(onTV: Bool = false) {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        haptic(.medium)
        if input != nil && !onTV {
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
                    Caption("On top")
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
                if saved.host == tv.host { current(saved) } else { other(saved) }
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
                    Caption(status)
                }
                Spacer()
                Circle().fill(tv.state == .connected ? Theme.accent : Theme.muted).frame(width: 6, height: 6)
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
                    action("Forget", Theme.muted) { confirmForget = true }
                }
            }
            .padding(.leading, 54)
        }
        .padding(14)
        .background(Theme.key, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.5), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: editing)
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

            Caption("Netflix and other protected video come out black")

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
