import AVFoundation
import UIKit

/// Small original notification cues, distinct from Apple's built-in tones.
/// Playback is user initiated or follows a successful send/contact action.
/// Ambient audio respects the hardware silent switch and other audio.
@MainActor
final class SpyderSonicPlayer {
    static let shared = SpyderSonicPlayer()
    private var player: AVAudioPlayer?
    private init() {}

    func preview(_ name: String) { play(name, respectPreference: false) }

    func playSent() {
        guard UserDefaults.standard.object(forKey: "spyder.chat.sound.sent.enabled") as? Bool ?? true else { return }
        play("spyder_sent", respectPreference: false)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func playConnect() {
        guard UserDefaults.standard.object(forKey: "spyder.chat.sound.sent.enabled") as? Bool ?? true else { return }
        play("spyder_connect", respectPreference: false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func play(_ name: String, respectPreference: Bool) {
        if respectPreference, UserDefaults.standard.string(forKey: "spyder.chat.sound.preference") == "mute" { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 0.8
            player?.prepareToPlay()
            player?.play()
        } catch {
            // Audio is optional: failures must never block a message or connection.
        }
    }
}
