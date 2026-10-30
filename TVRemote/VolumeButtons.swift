import AVFoundation
import MediaPlayer
import SwiftUI

/// The iPhone's own volume buttons turn the TV up and down while Pilot is open.
/// iOS doesn't hand apps the buttons directly, so we watch the phone's volume:
/// each press nudges it, we pass that nudge on (TV or Sonos), then put the phone's
/// volume back in the middle so the buttons never run out of room.
@MainActor
final class VolumeButtons: ObservableObject {
    private var observation: NSKeyValueObservation?
    private var resetting = false
    private let middle: Float = 0.5
    private var up: () -> Void = {}
    private var down: () -> Void = {}
    /// An off-screen system volume view: having one in the window hides iOS's volume
    /// overlay, and its slider is how apps set the phone's volume.
    fileprivate let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

    func start(up: @escaping () -> Void, down: @escaping () -> Void) {
        self.up = up
        self.down = down
        guard observation == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // Ambient + mix: playing music on the phone carries on.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            guard let old = change.oldValue, let new = change.newValue else { return }
            Task { @MainActor in self?.changed(from: old, to: new) }
        }
        // The slider appears a moment after the view is in a window.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            setPhoneVolume(middle)
        }
    }

    func stop() {
        observation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func changed(from old: Float, to new: Float) {
        if resetting {
            resetting = false
            return
        }
        guard new != old else { return }
        if new > old { up() } else { down() }
        setPhoneVolume(middle)
    }

    private func setPhoneVolume(_ value: Float) {
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first,
              abs(slider.value - value) > 0.001 else { return }
        resetting = true
        slider.value = value
    }
}

/// Puts the hidden volume view in the window. Nearly transparent, off to the side.
struct HiddenVolumeView: UIViewRepresentable {
    let buttons: VolumeButtons

    func makeUIView(context: Context) -> MPVolumeView {
        buttons.view.alpha = 0.01
        buttons.view.isUserInteractionEnabled = false
        return buttons.view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
