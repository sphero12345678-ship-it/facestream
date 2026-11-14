import ARKit
import AVFoundation
import ImageIO
import UIKit

extension ARManager {
    var lidarSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    var hasDepth: Bool { source == .faceID || source == .lidar }

    var showBlendCard: Bool {
        (source == .faceID && mode != .scan) || source == .both
    }

    var availableModes: [ViewMode] {
        source == .lidar ? ViewMode.allCases.filter { $0 != .scan } : ViewMode.allCases
    }

    var sourceHint: String {
        switch source {
        case .faceID:
            return "Face ID (TrueDepth): video, profundidad, malla, blendshapes, manos, cuerpo y scan"
        case .lidar:
            return "LiDAR (trasera): video, profundidad, nube 3D, manos y cuerpo"
        case .front:
            return "Cámara frontal normal: video, manos y cuerpo"
        case .back:
            return "Cámara trasera normal: video, manos y cuerpo"
        case .both:
            return "Video de la trasera + blendshapes del Face ID"
        }
    }

    func sourceTitle(_ s: SourceMode) -> String {
        switch s {
        case .faceID: return "Face ID"
        case .lidar: return lidarSupported ? "LiDAR" : "LiDAR ✕"
        case .front: return "Cámara frontal"
        case .back: return "Cámara trasera"
        case .both: return "Face ID + Trasera"
        }
    }

    func runSession(delay: Double = 0) {
        switchGen += 1
        let gen = switchGen
        let go = { [weak self] in
            guard let self = self, gen == self.switchGen else { return }
            self.launch(self.source)
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: go)
        } else {
            go()
        }
    }

    private func launch(_ src: SourceMode) {
        let opts: ARSession.RunOptions = [.resetTracking, .removeExistingAnchors]
        switch src {
        case .front, .back:
            session.pause()
            capture.onFrame = { [weak self] pb in self?.handleCapture(pb) }
            capture.onError = { [weak self] msg in
                DispatchQueue.main.async { self?.status = msg }
            }
            capture.start(position: src == .front ? .front : .back)
        case .faceID:
            capture.stop()
            let cfg = ARFaceTrackingConfiguration()
            if mode == .scan && ARFaceTrackingConfiguration.supportsWorldTracking {
                cfg.isWorldTrackingEnabled = true
            }
            session.run(cfg, options: opts)
        case .lidar:
            capture.stop()
            let cfg = ARWorldTrackingConfiguration()
            cfg.frameSemantics = .sceneDepth
            cfg.isLightEstimationEnabled = false
            session.run(cfg, options: opts)
        case .both:
            capture.stop()
            if ARWorldTrackingConfiguration.supportsUserFaceTracking {
                let cfg = ARWorldTrackingConfiguration()
                cfg.isLightEstimationEnabled = false
                cfg.userFaceTrackingEnabled = true
                session.run(cfg, options: opts)
            } else {
                status = "Este iPhone no soporta Face ID + trasera a la vez"
                source = .faceID
            }
        }
    }

    func sourceChanged(from old: SourceMode) {
        if reverting || source == old { return }

        if source == .lidar && !lidarSupported {
            flash("Este iPhone no tiene LiDAR")
            reverting = true
            DispatchQueue.main.async {
                self.source = old
                self.reverting = false
            }
            return
        }

        scanning = false
        preview = nil
        depthImage = nil
        centerCm = nil
        cloud = []
        overlay = Overlay()
        blends = []
        headPose = ""
        faceTracked = false
        status = ""
        if source == .lidar && mode == .scan { mode = .video }

        mirror = (source == .faceID || source == .front)
        vision.orientation = (source == .front || source == .back) ? .up : .right
        vision.tag = (source == .faceID || source == .front) ? "front" : "back"

        let fromCapture = (old == .front || old == .back)
        let toCapture = (source == .front || source == .back)
        runSession(delay: (fromCapture || toCapture) ? 0.5 : 0)
    }

    func handleCapture(_ pb: CVPixelBuffer) {
        if source != .front && source != .back { return }
        let now = Date()
        tickFPS(now)
        vision.process(pb)

        if now.timeIntervalSince(lastVideo) < 1.0 / 15.0 { return }
        lastVideo = now

        let img = CIImage(cvPixelBuffer: pb)

        if streaming {
            let opts = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5]
            if let jpg = ci.jpegRepresentation(of: img, colorSpace: CGColorSpaceCreateDeviceRGB(), options: opts) {
                if source == .back {
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
        if let cg = ci.createCGImage(small, from: small.extent) {
            let ui = UIImage(cgImage: cg)
            DispatchQueue.main.async { self.preview = ui }
        }
    }
}
