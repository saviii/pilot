import SwiftUI

/// Typing on the TV. Most apps take text live through LG's keyboard; YouTube
/// draws its own and ignores it, so there the field becomes a YouTube search.
struct KeyboardSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool
    @AppStorage("recentSearches") private var recentRaw = ""

    private var youtube: Bool { tv.foreground == TVConnection.youtube }
    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let app = tv.foregroundApp {
                    AppIcon(app: app, radius: 7, inset: 2).frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(youtube ? "Search YouTube" : "Type on \(tv.current?.name ?? "the TV")")
                        .font(.headline)
                    Caption(youtube ? "Results open when you press search" : "Shows on the TV as you type")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 10) {
                Image(systemName: youtube ? "magnifyingglass" : "keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                TextField(youtube ? "Search" : "Type", text: $text)
                    .font(.title3)
                    .tint(Theme.accent)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(youtube ? .search : .send)
                    .onSubmit(submit)
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
        .onAppear { focused = true }
    }

    private func submit() {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        haptic(.medium)
        if youtube { tv.searchYouTube(query) } else { tv.sendEnter() }
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

/// Edit the top strip: reorder or remove what's on it, add anything else.
struct AppsSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    private let pins = Pins()

    private var pinned: [TVConnection.App] {
        pins.ids.compactMap { id in tv.apps.first { $0.id == id } }
    }
    private var others: [TVConnection.App] {
        tv.apps.filter { !pins.contains($0.id) }
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
            .padding(.bottom, 8)

            List {
                Section {
                    ForEach(pinned) { app in
                        HStack(spacing: 14) {
                            AppIcon(app: app, radius: 9, inset: 3).frame(width: 52, height: 36)
                            Text(app.title).font(.body.weight(.medium))
                        }
                        .listRowBackground(Theme.key)
                    }
                    .onMove { source, destination in
                        pins.move(visible: pinned.map(\.id), from: source, to: destination)
                    }
                    .onDelete { offsets in
                        offsets.map { pinned[$0].id }.forEach(pins.remove)
                    }
                    if pinned.isEmpty {
                        Text("Nothing on top yet. Add apps below.")
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Theme.key)
                    }
                } header: {
                    Caption("On top")
                }

                if !others.isEmpty {
                    Section {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(others) { app in
                                Button {
                                    haptic()
                                    withAnimation(.easeInOut(duration: 0.25)) { pins.toggle(app.id) }
                                } label: {
                                    VStack(spacing: 8) {
                                        AppIcon(app: app, radius: 16, inset: 7).frame(width: 64, height: 64)
                                        Text(app.title)
                                            .font(.caption)
                                            .foregroundStyle(Theme.ink.opacity(0.8))
                                            .lineLimit(1)
                                            .frame(maxWidth: 76)
                                    }
                                }
                                .buttonStyle(Pressable())
                            }
                        }
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } header: {
                        Caption("Add apps")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .tint(Theme.accent)
        }
        .foregroundStyle(Theme.ink)
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
