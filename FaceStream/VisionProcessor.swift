import Vision
import CoreVideo
import Foundation

final class VisionProcessor {
    private let queue = DispatchQueue(label: "vision.queue")
    private let gate = DispatchSemaphore(value: 1)
    private let server: WSServer

    init(server: WSServer) { self.server = server }

    func process(_ pb: CVPixelBuffer) {
        if gate.wait(timeout: .now()) != .success { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            defer { self.gate.signal() }

            let hands = VNDetectHumanHandPoseRequest()
            hands.maximumHandCount = 2
            let body = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .right, options: [:])
            try? handler.perform([hands, body])

            var out: [String: Any] = [:]

            out["hands"] = (hands.results ?? []).map { obs -> [String: Any] in
                var pts: [String: [Float]] = [:]
                if let all = try? obs.recognizedPoints(.all) {
                    for (k, p) in all where p.confidence > 0.3 {
                        pts[k.rawValue.rawValue] = [Float(p.location.x), Float(p.location.y), p.confidence]
                    }
                }
                return ["chirality": obs.chirality.rawValue, "points": pts]
            }

            var bodyPts: [String: [Float]] = [:]
            if let obs = body.results?.first, let all = try? obs.recognizedPoints(.all) {
                for (k, p) in all where p.confidence > 0.3 {
                    bodyPts[k.rawValue.rawValue] = [Float(p.location.x), Float(p.location.y), p.confidence]
                }
            }
            out["body"] = bodyPts

            if let data = try? JSONSerialization.data(withJSONObject: ["vision": out]) {
                self.server.broadcast(data, text: true)
            }
        }
    }
}
