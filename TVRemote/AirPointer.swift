import CoreMotion
import Foundation

/// The Magic Remote's trick: hold the pointer key and the phone's gyroscope
/// steers the TV's pointer. Hold it like a remote, top edge toward the TV:
/// turning left and right moves it across, tilting up and down moves it up and down.
@MainActor
final class AirPointer: ObservableObject {
    @Published private(set) var active = false
    private var stopped: Date?
    private let motion = CMMotionManager()
    private var carry = (x: 0.0, y: 0.0)

    /// Pixels per radian of turn, per update. Higher moves faster.
    private let gain = 1100.0
    /// Ignore hand tremor below this many radians per second.
    private let deadzone = 0.03
    private let rate = 60.0

    /// Just used, or in use: OK should click where the pointer is.
    var recentlyUsed: Bool {
        active || (stopped.map { Date().timeIntervalSince($0) < 4 } ?? false)
    }

    func start(_ tv: TVConnection) {
        guard !active, motion.isDeviceMotionAvailable else { return }
        active = true
        carry = (0, 0)
        tv.move(dx: 0, dy: 0)  // wakes the pointer up on screen
        motion.deviceMotionUpdateInterval = 1 / rate
        motion.startDeviceMotionUpdates(to: .main) { [weak self, weak tv] data, _ in
            guard let self, let tv, let spin = data?.rotationRate else { return }
            let yaw = abs(spin.z) > self.deadzone ? -spin.z : 0
            let pitch = abs(spin.x) > self.deadzone ? -spin.x : 0
            self.carry.x += yaw / self.rate * self.gain
            self.carry.y += pitch / self.rate * self.gain
            let dx = self.carry.x.rounded(.towardZero), dy = self.carry.y.rounded(.towardZero)
            guard dx != 0 || dy != 0 else { return }
            self.carry.x -= dx
            self.carry.y -= dy
            tv.move(dx: dx, dy: dy)
        }
    }

    func stop() {
        guard active else { return }
        motion.stopDeviceMotionUpdates()
        active = false
        stopped = Date()
    }
}
