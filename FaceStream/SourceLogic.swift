import ARKit
import UIKit

extension ARManager {
    func sourceChanged(from old: SourceMode) {
        if source == old { return }

        if source == .faceID {
            capture.stop()
            vision.orientation = .right
            vision.tag = "front"
            status = ""
            configureSession(world: mode == .scan)
            return
        }

        if old == .faceID {
            scanning = false
            session.pause()
            faceTracked = false
            blends = []
            headPose = ""
            overlay = Overlay()
            centerCm = nil
        }

        capture.stop()
        status = ""
        previewBack = nil
        overlayBack = Overlay()
        vision.orientation = .up
        vision.tag = "front"
        visionBack.orientation = .up
        visionBack.tag = "back"
        visionBack.onResult = { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.overlayBack.handPoints = r.handPoints
                self.overlayBack.handLines = r.handLines
                self.overlayBack.bodyPoints = r.bodyPoints
                self.overlayBack.bodyLines = r.bodyLines
            }
        }
        capture.onFrame = { [weak self] pb, isBack in
            self?.handleCapture(pb, isBack: isBack)
        }
        capture.onError = { [weak self] msg in
            DispatchQueue.main.async { self?.status = msg }
        }
        capture.start(front: source == .both, back: true)
    }

    func handleCapture(_ pb: CVPixelBuffer, isBack: Bool) {
        let now = Date()
        if isBack {
            visionBack.detectHands = showHands
            visionBack.detectBody = showBody
            visionBack.broadcastEnabled = streaming
            visionBack.process(pb)
            if now.timeIntervalSince(lastCapBack) < 1.0 / 15.0 { return }
            lastCapBack = now
        } else {
            vision.process(pb)
            if now.timeIntervalSince(lastCapFront) < 1.0 / 15.0 { return }
            lastCapFront = now
        }

        let img = CIImage(cvPixelBuffer: pb)

        if streaming {
            let opts = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5]
            if let jpg = capCI.jpegRepresentation(of: img, colorSpace: CGColorSpaceCreateDeviceRGB(), options: opts) {
                if isBack {
                    var d = Data("BACK".utf8)
                    d.append(jpg)
                    server.broadcast(d, text: false)
                } else {
                    server.broadcast(jpg, text: false)
                }
            }
        }

        let s = min(1, 720 / img.extent.width)
        let small = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
        if let cg = capCI.createCGImage(small, from: small.extent) {
            let ui = UIImage(cgImage: cg)
            DispatchQueue.main.async {
                if isBack { self.previewBack = ui } else { self.preview = ui }
            }
        }
    }
}
