import SwiftUI

struct RemoteView: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var trackpad = false
    @State private var typing = false

    var body: some View {
        VStack(spacing: 28) {
            header

            Picker("", selection: $trackpad) {
                Text("Buttons").tag(false)
                Text("Trackpad").tag(true)
            }
            .pickerStyle(.segmented)

            Group {
                if trackpad { Trackpad() } else { DPad() }
            }
            .frame(height: 300)

            HStack {
                RoundKey(symbol: "arrow.uturn.backward") { tv.press(.back) }
                Spacer()
                RoundKey(symbol: "house") { tv.press(.home) }
                Spacer()
                RoundKey(symbol: "keyboard") { typing = true }
                Spacer()
                VolumeRocker()
            }

            AppRow()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .sheet(isPresented: $typing) {
            Keyboard()
                .presentationDetents([.height(180)])
                .presentationBackground(.thinMaterial)
        }
    }

    private var header: some View {
        HStack {
            Circle().fill(.green).frame(width: 8, height: 8)
            Text(tv.host ?? "")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Forget this TV", role: .destructive) { tv.forget() }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(.secondary)
            RoundKey(symbol: "power", size: 44) { tv.powerOff() }
        }
    }
}

// MARK: - Pieces

private func tap() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

struct RoundKey: View {
    let symbol: String
    var size: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button {
            tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.33, weight: .medium))
                .frame(width: size, height: size)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(Pressable())
        .foregroundStyle(.white)
    }
}

struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DPad: View {
    @EnvironmentObject private var tv: TVConnection

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(.white.opacity(0.06))
                arrow("chevron.up", .up).offset(y: -side * 0.34)
                arrow("chevron.down", .down).offset(y: side * 0.34)
                arrow("chevron.left", .left).offset(x: -side * 0.34)
                arrow("chevron.right", .right).offset(x: side * 0.34)
                Button {
                    tap()
                    tv.press(.enter)
                } label: {
                    Text("OK")
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .frame(width: side * 0.36, height: side * 0.36)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(Pressable())
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
        }
    }

    private func arrow(_ symbol: String, _ button: TVConnection.Button) -> some View {
        Button {
            tap()
            tv.press(button)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 72, height: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
    }
}

/// Drag to move the TV's pointer, tap to click, drag along the right edge to scroll.
struct Trackpad: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var last: CGPoint?

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 28)
                .fill(.white.opacity(0.06))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(.white.opacity(0.04))
                        .frame(width: 44)
                        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            defer { last = value.location }
                            guard let last else { return }
                            let dx = value.location.x - last.x
                            let dy = value.location.y - last.y
                            if value.startLocation.x > geo.size.width - 44 {
                                tv.scroll(dy: -dy)
                            } else {
                                tv.move(dx: dx * 1.6, dy: dy * 1.6)
                            }
                        }
                        .onEnded { value in
                            last = nil
                            let moved = hypot(value.translation.width, value.translation.height)
                            if moved < 6 {
                                tap()
                                tv.click()
                            }
                        }
                )
        }
    }
}

struct VolumeRocker: View {
    @EnvironmentObject private var tv: TVConnection

    var body: some View {
        HStack(spacing: 0) {
            key("minus") { tv.volumeDown() }
            Button {
                tap()
                tv.toggleMute()
            } label: {
                Text(tv.muted ? "—" : tv.volume.map(String.init) ?? "")
                    .font(.system(.footnote, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 32, height: 60)
            }
            key("plus") { tv.volumeUp() }
        }
        .background(.white.opacity(0.08), in: Capsule())
        .foregroundStyle(.white)
    }

    private func key(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
    }
}

struct AppRow: View {
    @EnvironmentObject private var tv: TVConnection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(tv.apps) { app in
                    Button {
                        tap()
                        tv.launch(app)
                    } label: {
                        VStack(spacing: 8) {
                            AsyncImage(url: app.icon) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Text(app.title.prefix(1))
                                    .font(.system(.title2, design: .monospaced))
                            }
                            .frame(width: 64, height: 64)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            Text(app.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 72)
                        }
                    }
                    .buttonStyle(Pressable())
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, -24)
    }
}

/// Whatever you type here shows up in the TV's focused text box.
struct Keyboard: View {
    @EnvironmentObject private var tv: TVConnection
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            TextField("Type on your TV", text: $text)
                .font(.title3)
                .padding(16)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
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
