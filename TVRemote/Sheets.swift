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

/// Every app on the TV. Tap one to put it in the top strip; tap again to take it out.
struct AppsSheet: View {
    @EnvironmentObject private var tv: TVConnection
    private let pins = Pins()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Caption("Add to the top")
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(tv.apps) { app in
                        let pinned = pins.contains(app.id)
                        Button {
                            haptic()
                            pins.toggle(app.id)
                        } label: {
                            VStack(spacing: 8) {
                                AppIcon(app: app, radius: 18, inset: 8)
                                    .frame(width: 72, height: 72)
                                    .overlay(alignment: .topTrailing) {
                                        if pinned {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(Theme.background)
                                                .frame(width: 22, height: 22)
                                                .background(Theme.accent, in: Circle())
                                                .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                                                .offset(x: 6, y: -6)
                                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                                        }
                                    }
                                    .animation(.easeOut(duration: 0.15), value: pinned)
                                Text(app.title)
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink.opacity(0.8))
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)
                            }
                        }
                        .buttonStyle(Pressable())
                    }
                }
            }
            .padding(24)
        }
    }
}
