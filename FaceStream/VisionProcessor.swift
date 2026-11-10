import Vision
import ImageIO
import CoreVideo
import CoreGraphics
import Foundation

struct VisionResult {
    var handPoints: [CGPoint] = []
    var handLines: [[CGPoint]] = []
    var bodyPoints: [CGPoint] = []
    var bodyLines: [[CGPoint]] = []
}

final class VisionProcessor {
    var orientation: CGImagePropertyOrientation = .right
    var tag = "front"
    var detectHands = true
    var detectBody = true
    var broadcastEnabled = true
    var onResult: ((VisionResult) -> Void)?

    private let queue = DispatchQueue(label: "vision.queue")
    private let gate = DispatchSemaphore(value: 1)
    private let server: WSServer

    private static let handChains: [[VNHumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]
    ]

    private static let bodyChains: [[VNHumanBodyPoseObservation.JointName]] = [
        [.leftWrist, .leftElbow, .leftShoulder, .neck, .rightShoulder, .rightElbow, .rightWrist],
        [.nose, .neck, .root],
        [.leftShoulder, .leftHip, .root, .rightHip, .rightShoulder],
        [.leftHip, .leftKnee, .leftAnkle],
        [.rightHip, .rightKnee, .rightAnkle],
        [.leftEar, .leftEye, .nose, .rightEye, .rightEar]
    ]

    init(server: WSServer) { self.server = server }

    private static func lines<J: Hashable>(_ chains: [[J]], _ pts: [J: CGPoint]) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        for chain in chains {
            var cur: [CGPoint] = []
            for j in chain {
                if let p = pts[j] {
                    cur.append(p)
                } else {
                    if cur.count > 1 { out.append(cur) }
                    cur = []
                }
            }
            if cur.count > 1 { out.append(cur) }
        }
        return out
    }

    func process(_ pb: CVPixelBuffer) {
        let doHands = detectHands
        let doBody = detectBody
        if !doHands && !doBody { return }
        if gate.wait(timeout: .now()) != .success { return }

        queue.async { [weak self] in
            guard let self = self else { return }
            defer { self.gate.signal() }

            let hands = VNDetectHumanHandPoseRequest()
            hands.maximumHandCount = 2
            let body = VNDetectHumanBodyPoseRequest()
            var reqs: [VNRequest] = []
            if doHands { reqs.append(hands) }
            if doBody { reqs.append(body) }

            let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: orientation, options: [:])
            try? handler.perform(reqs)

            var res = VisionResult()
            var handsJSON: [[String: Any]] = []
            var bodyJSON: [String: [Float]] = [:]

            if doHands {
                for obs in hands.results ?? [] {
                    guard let all = try? obs.recognizedPoints(.all) else { continue }
                    var js: [String: [Float]] = [:]
                    var pts: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
                    for (k, p) in all where p.confidence > 0.3 {
                        js[k.rawValue.rawValue] = [Float(p.location.x), Float(p.location.y), p.confidence]
                        let q = CGPoint(x: p.location.x, y: 1 - p.location.y)
                        pts[k] = q
                        res.handPoints.append(q)
                    }
                    res.handLines += VisionProcessor.lines(VisionProcessor.handChains, pts)
                    handsJSON.append(["chirality": obs.chirality.rawValue, "points": js])
                }
            }

            if doBody, let obs = body.results?.first,
               let all = try? obs.recognizedPoints(.all) {
                var pts: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
                for (k, p) in all where p.confidence > 0.3 {
                    bodyJSON[k.rawValue.rawValue] = [Float(p.location.x), Float(p.location.y), p.confidence]
                    let q = CGPoint(x: p.location.x, y: 1 - p.location.y)
                    pts[k] = q
                    res.bodyPoints.append(q)
                }
                res.bodyLines = VisionProcessor.lines(VisionProcessor.bodyChains, pts)
            }

            self.onResult?(res)

            if self.broadcastEnabled {
                let out: [String: Any] = ["hands": handsJSON, "body": bodyJSON, "src": self.tag]
                if let data = try? JSONSerialization.data(withJSONObject: ["vision": out]) {
                    self.server.broadcast(data, text: true)
                }
            }
        }
    }
}
