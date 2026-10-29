import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var tv: TVConnection
    @State private var address = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text("TV REMOTE")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(headline)
                .font(.system(size: 34, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if tv.state == .connecting || tv.state == .waitingForApproval {
                ProgressView().tint(.white)
            } else {
                TextField("192.168.1.20", text: $address)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(.title3, design: .monospaced))
                    .padding(16)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .focused($focused)

                Button {
                    focused = false
                    tv.connect(to: address)
                } label: {
                    Text("Connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                }
                .disabled(address.isEmpty)
            }

            Spacer()
            Spacer()
        }
        .padding(24)
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
