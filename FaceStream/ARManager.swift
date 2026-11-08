import ARKit
import AVFoundation
import SceneKit
import CoreImage
import UIKit

final class ARManager: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    let server = WSServer()
    private let ci = CIContext()
    private let work = DispatchQueue(label: "ar.work")
    private lazy var vision = VisionProcessor(server: server)
    private let poseNode = SCNNode()
    private var started = false
    private var lastVideo = Date.distantPast
    private var lastUI = Date.distantPast
    private var lastDepth = Date.distantPast
    private var frames = 0
    private var fpsStart = Date()

    @Published var ip = "..."
    @Published var status = ""
    @Published var clients = 0
    @Published var fps = 0
    @Published var preview: UIImage?
    @Published var depthImage: UIImage?
    @Published var overlay = Overlay()
    @Published var blends: [Blend] = []
    @Published var headPose = ""
    @Published var faceTracked = false

    @Published var mode: ViewMode = .video
    @Published var showFace = true
    @Published var showBlends = true
    @Published var mirror = true
    @Published var showHands = true { didSet { vision.detectHands = showHands } }
    @Published var showBody = true { didSet { vision.detectBody = showBody } }
    @Published var streaming = true { didSet { vision.broadcastEnabled = streaming } }

    func start() {
        if started { return }
        started = true
        guard ARFaceTrackingConfiguration.isSupported else {
            status = "Face tracking no soportado"
            return
        }
        server.onCount = { [weak self] n in
            DispatchQueue.main.async { self?.clients = n }
        }
        server.start()

        vision.onResult = { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.overlay.handPoints = r.handPoints
                self.overlay.handLines = r.handLines
                self.overlay.bodyPoints = r.bodyPoints
                self.overlay.bodyLines = r.bodyLines
            }
        }

        session.delegate = self
        session.delegateQueue = work
        session.run(ARFaceTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        ip = Self.localIP() ?? "sin WiFi"
        status = "Iniciando cámara…"
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()
        frames += 1
        if now.timeIntervalSince(fpsStart) >= 1 {
            let f = frames
            frames = 0
            fpsStart = now
            DispatchQueue.main.async { self.fps = f }
        }

        let pb = frame.capturedImage
        vision.process(pb)

        let face = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first

        if streaming {
            var dict: [String: Any] = ["t": frame.timestamp]
            if let face = face {
                var bs: [String: Float] = [:]
                for (k, v) in face.blendShapes { bs[k.rawValue] = v.floatValue }
                dict["blendshapes"] = bs
                dict["transform"] = (0..<4).flatMap { c in (0..<4).map { r in face.transform[c][r] } }
            }
            if let d = try? JSONSerialization.data(withJSONObject: dict) {
                server.broadcast(d, text: true)
            }
        }

        let wantVideo = streaming && now.timeIntervalSince(lastVideo) > 1.0 / 15.0
        let wantUI = now.timeIntervalSince(lastUI) > 1.0 / 20.0

        if wantVideo || wantUI {
            let img = CIImage(cvPixelBuffer: pb).oriented(.right)

            if wantVideo {
                lastVideo = now
                let opts = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5]
                if let jpg = ci.jpegRepresentation(of: img, colorSpace: CGColorSpaceCreateDeviceRGB(), options: opts) {
                    server.broadcast(jpg, text: false)
                }
            }

            if wantUI {
                lastUI = now
                buildUI(frame: frame, face: face, pb: pb, image: img)
            }
        }

        if mode == .depth, now.timeIntervalSince(lastDepth) > 1.0 / 10.0,
           let dd = frame.capturedDepthData {
            lastDepth = now
            if let ui = Self.makeDepthImage(dd) {
                DispatchQueue.main.async { self.depthImage = ui }
            }
        }
    }

    private func buildUI(frame: ARFrame, face: ARFaceAnchor?, pb: CVPixelBuffer, image: CIImage) {
        var previewImg: UIImage?
        let s = min(1, 720 / image.extent.width)
        let small = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        if let cg = ci.createCGImage(small, from: small.extent) {
            previewImg = UIImage(cgImage: cg)
        }

        var pts: [CGPoint] = []
        var top: [Blend] = []
        var pose = ""
        let tracked = face?.isTracked ?? false

        if let face = face, face.isTracked {
            if showFace {
                let size = CGSize(width: CGFloat(CVPixelBufferGetHeight(pb)),
                                  height: CGFloat(CVPixelBufferGetWidth(pb)))
                let verts = face.geometry.vertices
                var i = 0
                while i < verts.count {
                    let v = verts[i]
                    let w = face.transform * SIMD4<Float>(v.x, v.y, v.z, 1)
                    let p = frame.camera.projectPoint(SIMD3<Float>(w.x, w.y, w.z),
                                                      orientation: .portrait,
                                                      viewportSize: size)
                    pts.append(CGPoint(x: p.x / size.width, y: p.y / size.height))
                    i += 2
                }
            }
            if showBlends {
                let all = face.blendShapes.map { Blend(id: $0.key.rawValue, value: $0.value.floatValue) }
                top = Array(all.sorted { $0.value > $1.value }.prefix(8))
            }
            poseNode.simdTransform = frame.camera.transform.inverse * face.transform
            let e = poseNode.simdEulerAngles
            let k: Float = 180 / Float.pi
            pose = String(format: "Yaw %.0f°  Pitch %.0f°  Roll %.0f°", e.y * k, e.x * k, e.z * k)
        }

        DispatchQueue.main.async {
            if let p = previewImg { self.preview = p }
            self.overlay.face = pts
            self.blends = top
            self.headPose = pose
            self.faceTracked = tracked
        }
    }

    static func makeDepthImage(_ data: AVDepthData) -> UIImage? {
        let d = data.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = d.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(map)
        var out = [UInt8](repeating: 0, count: w * h)
        let near: Float = 0.15
        let far: Float = 1.0
        for y in 0..<h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let z = row[x]
                if z.isFinite && z > 0 {
                    let t = 1 - min(max((z - near) / (far - near), 0), 1)
                    out[y * w + x] = UInt8(t * 255)
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                               bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                               decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }

    static func localIP() -> String? {
        var result: String?
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0, let first = ifa else { return nil }
        defer { freeifaddrs(ifa) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_INET),
                  String(cString: i.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            result = String(cString: host)
        }
        return result
    }
}
