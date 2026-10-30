import SwiftUI

/// Whatever you type here shows up in the TV's focused text box.
struct KeyboardSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Caption("Type on TV")
            TextField("", text: $text)
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .padding(16)
                .background(Theme.key, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    tv.sendEnter()
                    dismiss()
                }
                .onChange(of: text) { old, new in
                    if new.hasPrefix(old) {
                        tv.type(String(new.dropFirst(old.count)))
                    } else if old.hasPrefix(new) {
                        tv.deleteCharacters(old.count - new.count)
                    } else {
                        tv.deleteCharacters(old.count)
                        tv.type(new)
                    }
                }
        }
        .padding(24)
        .onAppear { focused = true }
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
