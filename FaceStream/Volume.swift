import AVFoundation
import MediaPlayer
import UIKit

final class VolumeButtons: NSObject {
    var onPress: (() -> Void)?
    private var obs: NSKeyValueObservation?
    private var volumeView: MPVolumeView?
    private var resetting = false
    private var base: Float = 0.5

    func start() {
        if obs != nil { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, options: [.mixWithOthers])
        try? s.setActive(true)
        DispatchQueue.main.async {
            let vv = MPVolumeView(frame: CGRect(x: -3000, y: -3000, width: 10, height: 10))
            self.volumeView = vv
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            scenes.first?.windows.first?.addSubview(vv)
        }
        base = s.outputVolume
        if base < 0.15 || base > 0.85 {
            base = 0.5
            setVolume(0.5)
        }
        obs = s.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            guard let self = self, !self.resetting else { return }
            self.resetting = true
            self.onPress?()
            self.setVolume(self.base)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.resetting = false }
        }
    }

    private func setVolume(_ v: Float) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let slider = self.volumeView?.subviews.compactMap { $0 as? UISlider }.first
            slider?.value = v
        }
    }

    func stop() {
        obs?.invalidate()
        obs = nil
        DispatchQueue.main.async {
            self.volumeView?.removeFromSuperview()
            self.volumeView = nil
        }
    }
}
