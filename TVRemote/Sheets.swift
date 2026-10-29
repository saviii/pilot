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
                    HStack {
                        Text(input.label).font(.body.weight(.medium))
                        Spacer()
                        Circle()
                            .fill(input.connected ? Theme.accent : Theme.hairline)
                            .frame(width: 6, height: 6)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 56)
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

/// The rarely used keys: numbers, the four color keys, guide and info.
struct NumberPadSheet: View {
    @EnvironmentObject private var tv: TVConnection

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9], id: \.self) { digit($0) }
                text("Guide") { tv.press(.guide) }
                digit(0)
                text("Info") { tv.press(.info) }
            }

            HStack(spacing: 10) {
                color(.red, Color(red: 0.93, green: 0.27, blue: 0.24))
                color(.green, Color(red: 0.30, green: 0.75, blue: 0.40))
                color(.yellow, Color(red: 0.98, green: 0.80, blue: 0.25))
                color(.blue, Color(red: 0.30, green: 0.55, blue: 0.95))
            }
        }
        .padding(24)
        .padding(.top, 12)
    }

    private func digit(_ n: Int) -> some View {
        Key(shape: RoundedRectangle(cornerRadius: 16), action: { tv.pressDigit(n) }) {
            Text("\(n)")
                .font(Theme.dot(30))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
        }
    }

    private func text(_ label: String, _ action: @escaping () -> Void) -> some View {
        Key(shape: RoundedRectangle(cornerRadius: 16), action: action) {
            Text(label.uppercased())
                .font(Theme.mono(10))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
        }
    }

    private func color(_ button: TVConnection.Button, _ fill: Color) -> some View {
        Key(shape: Capsule(), action: { tv.press(button) }) {
            Capsule().fill(fill)
                .frame(width: 26, height: 6)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
}

struct AppsSheet: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Caption("Apps")
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(tv.apps) { app in
                        VStack(spacing: 8) {
                            Key(shape: RoundedRectangle(cornerRadius: 18), action: {
                                tv.launch(app)
                                dismiss()
                            }) {
                                AppIcon(app: app, size: 30)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                            Text(app.title)
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
