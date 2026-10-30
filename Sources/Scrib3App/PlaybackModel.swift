import AVFoundation
import Observation
import Scrib3Core

@MainActor
@Observable
final class PlaybackModel {
    let player: AVPlayer
    var currentTime: Double = 0

    private var timeObserver: Any?

    init(url: URL) {
        player = AVPlayer(url: url)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTime = time.seconds
            }
        }
    }

    func seek(to seconds: Double) {
        let time = CMTime(
            seconds: max(0, seconds),
            preferredTimescale: 600
        )
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }

    func isPlaying(_ cue: SubtitleCue) -> Bool {
        currentTime >= cue.start.seconds && currentTime < cue.end.seconds
    }
}
