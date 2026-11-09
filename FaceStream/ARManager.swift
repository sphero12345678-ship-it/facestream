import ARKit
import AVFoundation
import SceneKit
import CoreImage
import UIKit
import simd

final class ARManager: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    let server = WSServer()
    private let ci = CIContext()
    let work = DispatchQueue(label: "ar.work")
    private lazy var vision = VisionProcessor(server: server)
    private let poseNode = SCNNode()
    private var started = false
    private var lastVideo = Date.distantPast
    private var lastUI = Date.distantPast
    private var lastDepth = Date.distantPast
    private var frames = 0
    private var fpsStart = Date()

    static let lut: [UInt8] = (0..<256).flatMap { i in ARManager.hsv(Float(i) / 255 * 0.7) }

    static func hsv(_ h: Float) -> [UInt8] {
        let i = Int(h * 6) % 6
        let f = h * 6 - Float(Int(h * 6))
        let q = 1 - f
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        switch i {
        case 0: r = 1; g = f
        case 1: r = q; g = 1
        case 2: g = 1; b = f
        case 3: g = q; b = 1
        case 4: r = f; b = 1
        default: r = 1; b = q
        }
        return [UInt8(r * 255), UInt8(g * 255), UInt8(b * 255)]
    }

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
    @Published var centerCm: Int?
    @Published var cloud: [SIMD3<Float>] = []
    @Published var cloudPivot: Float = 0.5
    @Published var toast = ""
    let store = ScanStore()
    let files = FileServer()
    var lastScanDepthTs: TimeInterval = 0
    var lastScanPublish = Date.distantPast
    var lastHaptic = Date.distantPast
    @Published var scanning = false
    @Published var scanCount = 0
    @Published var scanPreview: [SIMD3<Float>] = []
    @Published var scanColors: [UInt32] = []
    @Published var scanCenter = SIMD3<Float>(0, 0, 0)
    @Published var scanRadius: Float = 0.3
    @Published var scanShowModel = false
    @Published var scanFlipX = false
    @Published var scanVoxelMM = 4 { didSet { store.voxel = Float(scanVoxelMM) / 1000 } }
    @Published var shareItem: ShareItem?

    @Published var mode: ViewMode = .video { didSet { modeChanged(from: oldValue) } }
    @Published var nearCm: Double = 10
    @Published var farCm: Double = 100
    @Published var colorMap = true
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
        files.start()

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

    func snapshot() {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first,
                  let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            else { return }
            let img = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            self.toast = "Captura guardada en Fotos"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.toast = "" }
        }
    }

    func openGallery() {
        if let u = URL(string: "photos-redirect://") {
            UIApplication.shared.open(u)
        }
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
        if scanning { scanTick(frame) } else { vision.process(pb) }

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

        if mode != .video, now.timeIntervalSince(lastDepth) > 1.0 / 12.0,
           let dd = frame.capturedDepthData {
            lastDepth = now
            processDepth(dd)
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

    private func processDepth(_ data: AVDepthData) {
        let d = data.depthDataType == kCVPixelFormatType_DepthFloat32
            ? data
            : data.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = d.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return }
        let stride = CVPixelBufferGetBytesPerRow(map)

        let near = Float(nearCm / 100)
        let far = Float(max(farCm, nearCm + 10) / 100)
        let useColor = colorMap
        let wantCloud = mode == .cloud

        var fx = Float(w) * 0.87
        var fy = fx
        var cx = Float(w) / 2
        var cy = Float(h) / 2
        if wantCloud, let cal = d.cameraCalibrationData {
            let k = cal.intrinsicMatrix
            let ref = cal.intrinsicMatrixReferenceDimensions
            let sx = Float(w) / Float(ref.width)
            let sy = Float(h) / Float(ref.height)
            fx = k[0][0] * sx
            fy = k[1][1] * sy
            cx = k[2][0] * sx
            cy = k[2][1] * sy
        }

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        var pts: [SIMD3<Float>] = []
        var sumZ: Float = 0
        let step = 5
        let lut = ARManager.lut

        for y in 0..<h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let z = row[x]
                if !(z.isFinite && z > 0 && z >= near && z <= far) { continue }
                let n = (z - near) / (far - near)
                let o = (y * w + x) * 4
                if useColor {
                    let li = Int(n * 255) * 3
                    rgba[o] = lut[li]
                    rgba[o + 1] = lut[li + 1]
                    rgba[o + 2] = lut[li + 2]
                } else {
                    let g = UInt8((1 - n) * 255)
                    rgba[o] = g
                    rgba[o + 1] = g
                    rgba[o + 2] = g
                }
                rgba[o + 3] = 255
                if wantCloud && x % step == 0 && y % step == 0 {
                    pts.append(SIMD3<Float>(-(Float(y) - cy) * z / fy,
                                            (Float(x) - cx) * z / fx,
                                            z))
                    sumZ += z
                }
            }
        }

        var vals: [Float] = []
        for yy in (h / 2 - 3)...(h / 2 + 3) {
            let row = base.advanced(by: yy * stride).assumingMemoryBound(to: Float32.self)
            for xx in (w / 2 - 3)...(w / 2 + 3) {
                let z = row[xx]
                if z.isFinite && z > 0 { vals.append(z) }
            }
        }
        var center: Int?
        if !vals.isEmpty {
            center = Int((vals.sorted()[vals.count / 2] * 100).rounded())
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent)
        else { return }
        let ui = UIImage(cgImage: cg, scale: 1, orientation: .right)
        let pivot = pts.isEmpty ? (near + far) / 2 : sumZ / Float(pts.count)

        DispatchQueue.main.async {
            self.depthImage = ui
            self.centerCm = center
            if wantCloud {
                self.cloud = pts
                self.cloudPivot = pivot
            }
        }
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
