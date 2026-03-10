import AppKit
import AVFoundation

class SoundFeedback {
    private static var startPlayer: AVAudioPlayer?
    private static var stopPlayer: AVAudioPlayer?

    static func playStart() {
        play(resource: "start", player: &startPlayer)
    }

    static func playDone() {
        play(resource: "stop", player: &stopPlayer)
    }

    static func playError() {
        NSSound.beep()
    }

    private static func play(resource: String, player: inout AVAudioPlayer?) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 0.15
            p.play()
            player = p // retain until playback finishes
        } catch {
            // Sound is non-critical
        }
    }
}
