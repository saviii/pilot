import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var address = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Caption("Pilot")

            Text(headline)
                .font(.system(size: 34, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.body)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if tv.state == .connecting || tv.state == .waitingForApproval {
                ProgressView().tint(Theme.accent)
                Button("Cancel") { tv.cancel() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.muted)
            } else {
                TextField("TV address", text: $address)
                    .keyboardType(.numbersAndPunctuation)
                    .font(Theme.mono(18))
                    .tint(Theme.accent)
                    .padding(16)
                    .background(Theme.key, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                    .focused($focused)

                Button {
                    focused = false
                    tv.connect(to: address)
                } label: {
                    Text("Connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.background)
                }
                .disabled(address.isEmpty)
            }

            Spacer()
            Spacer()
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .background(Theme.background.ignoresSafeArea())
        .onAppear { address = tv.host ?? "" }
    }

    private var headline: String {
        switch tv.state {
        case .waitingForApproval: "Press OK on your TV"
        case .connecting: "Connecting"
        case .failed: "Didn't connect"
        default: "Find your TV"
        }
    }

    private var detail: String {
        switch tv.state {
        case .waitingForApproval:
            "Your TV is asking whether to let this phone in. You only do this once."
        case .connecting:
            "Looking for the TV on your Wi-Fi."
        case .failed(let reason):
            reason
        default:
            "Type your TV's IP address. It's in Settings → Network → Wi-Fi → Advanced."
        }
    }
}
