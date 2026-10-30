import SwiftUI

/// Setup: finds the LG TVs on your Wi-Fi and pairs with the one you tap.
/// Typing an address is the fallback.
struct ConnectView: View {
    @EnvironmentObject private var tv: TVConnection
    @StateObject private var finder = TVFinder()
    @State private var address = ""
    @State private var typing = false
    @FocusState private var focused: Bool

    private var busy: Bool { tv.state == .connecting || tv.state == .waitingForApproval }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer()
                if tv.adding {
                    Button("Cancel") { tv.stopAdding() }
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 44)

            Spacer(minLength: 0)

            // The icon, then the name in Doto.
            Image("PilotMark")
                .resizable()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.hairline))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .accessibilityHidden(true)

            Text("PILOT")
                .font(Theme.dot(22))
                .tracking(1)
                .foregroundStyle(Theme.accent)
                .padding(.bottom, -12)

            Text(headline)
                .font(.system(size: 38, weight: .bold))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.body)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if busy {
                ProgressView().tint(Theme.accent)
                Button("Cancel") { tv.cancel() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.muted)
            } else {
                found
                manual
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .background(Theme.background.ignoresSafeArea())
        .task { await finder.scan(with: tv) }
    }

    // MARK: Found TVs

    private var found: some View {
        VStack(spacing: 10) {
            ForEach(finder.found, id: \.self) { address in
                let known = tv.saved.first { $0.host == address }
                Key(shape: RoundedRectangle(cornerRadius: 16), action: { tv.connect(to: address) }) {
                    HStack(spacing: 14) {
                        Image(systemName: "tv")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(known?.name ?? "LG TV").font(.body.weight(.medium))
                            Caption(known != nil && address == tv.host ? "\(address) · Current" : address)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 64)
                }
            }

            if finder.scanning {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accent)
                    Caption("Looking on your Wi-Fi")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 44)
            } else if finder.found.isEmpty {
                Button {
                    Task { await finder.scan(with: tv) }
                } label: {
                    Label("Look again", systemImage: "arrow.clockwise")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.accent)
                }
                .frame(height: 44)
            }
        }
        .animation(.easeOut(duration: 0.2), value: finder.found)
    }

    // MARK: Typing an address

    @ViewBuilder
    private var manual: some View {
        if typing {
            HStack(spacing: 10) {
                TextField("192.168.…", text: $address)
                    .keyboardType(.numbersAndPunctuation)
                    .font(Theme.mono(16))
                    .tint(Theme.accent)
                    .padding(14)
                    .background(Theme.key, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                    .focused($focused)
                    .onSubmit(connectTyped)
                Button(action: connectTyped) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 50, height: 50)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.background)
                }
                .disabled(address.isEmpty)
            }
        } else {
            Button("Enter an address instead") {
                typing = true
                focused = true
            }
            .font(Theme.mono(12))
            .foregroundStyle(Theme.muted)
        }
    }

    private func connectTyped() {
        focused = false
        tv.connect(to: address)
    }

    // MARK: Copy

    private var headline: String {
        switch tv.state {
        case .waitingForApproval: "Press OK on your TV"
        case .connecting: "Connecting"
        case .failed where !tv.adding: "Didn't connect"
        default: tv.adding ? "Add a TV" : "Find your TV"
        }
    }

    private var detail: String {
        switch tv.state {
        case .waitingForApproval:
            "Your TV is asking whether to let this phone in. You only do this once per TV."
        case .connecting:
            "Reaching the TV on your Wi-Fi."
        case .failed(let reason) where !tv.adding:
            reason
        default:
            "Make sure the TV is on and on the same Wi-Fi as this phone."
        }
    }
}
