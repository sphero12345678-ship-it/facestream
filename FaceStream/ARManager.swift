import ARKit
import CoreImage
import UIKit

final class ARManager: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    let server = WSServer()
    private let ci = CIContext()
    private lazy var vision = VisionProcessor(server: server)
    private var lastVideo = Date.distantPast
    @Published var ip = "..."
    @Published var status = ""

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else {
            status = "Face tracking no soportado"; return
        }
        server.start()
        session.delegate = self
        session.run(ARFaceTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        ip = Self.localIP() ?? "sin WiFi"
        status = "Conecta tu cliente a la URL de arriba"
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        var dict: [String: Any] = ["t": frame.timestamp]
        vision.process(frame.capturedImage)
        if let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first {
            var bs: [String: Float] = [:]
            for (k, v) in face.blendShapes { bs[k.rawValue] = v.floatValue }
            dict["blendshapes"] = bs
            dict["transform"] = (0..<4).flatMap { c in (0..<4).map { r in face.transform[c][r] } }
        }
        if let d = try? JSONSerialization.data(withJSONObject: dict) {
            server.broadcast(d, text: true)
        }
        if Date().timeIntervalSince(lastVideo) > 1.0 / 15.0 {
            lastVideo = Date()
            let img = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
            let opts = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5]
            if let jpg = ci.jpegRepresentation(of: img, colorSpace: CGColorSpaceCreateDeviceRGB(), options: opts) {
                server.broadcast(jpg, text: false)
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
