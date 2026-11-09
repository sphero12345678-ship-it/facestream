import ARKit
import AVFoundation
import SwiftUI
import UIKit
import Network
import simd

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

final class ScanStore {
    private var map: [Int64: Int] = [:]
    private var pts: [SIMD3<Float>] = []
    private var cols: [UInt32] = []
    var voxel: Float = 0.004
    let maxPoints = 700_000

    var count: Int { pts.count }
    var isFull: Bool { pts.count >= maxPoints }

    func reset() {
        map.removeAll(keepingCapacity: true)
        pts.removeAll(keepingCapacity: true)
        cols.removeAll(keepingCapacity: true)
    }

    func add(_ p: SIMD3<Float>, _ c: UInt32) {
        if pts.count >= maxPoints { return }
        let ix = Int64((p.x / voxel).rounded(.down))
        let iy = Int64((p.y / voxel).rounded(.down))
        let iz = Int64((p.z / voxel).rounded(.down))
        let key = ((ix & 0x1FFFFF) << 42) | ((iy & 0x1FFFFF) << 21) | (iz & 0x1FFFFF)
        if map[key] == nil {
            map[key] = pts.count
            pts.append(p)
            cols.append(c)
        }
    }

    func sample(limit: Int) -> (points: [SIMD3<Float>], colors: [UInt32], center: SIMD3<Float>, radius: Float) {
        let total = pts.count
        if total == 0 { return ([], [], SIMD3<Float>(0, 0, 0), 0.3) }
        let stepN = Swift.max(1, total / limit)
        var ps: [SIMD3<Float>] = []
        var cs: [UInt32] = []
        var sum = SIMD3<Float>(0, 0, 0)
        for i in stride(from: 0, to: total, by: stepN) {
            ps.append(pts[i])
            cs.append(cols[i])
            sum += pts[i]
        }
        let c = sum / Float(ps.count)
        var r: Float = 0.05
        for p in ps { r = Swift.max(r, simd_length(p - c)) }
        return (ps, cs, c, r)
    }

    private func put(_ f: Float, _ d: inout Data) {
        var v = f.bitPattern.littleEndian
        withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
    }

    func plyData() -> Data {
        let n = pts.count
        let header = "ply\nformat binary_little_endian 1.0\nelement vertex \(n)\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"
        var d = Data(header.utf8)
        d.reserveCapacity(d.count + n * 15)
        for i in 0..<n {
            let p = pts[i]
            put(p.x, &d)
            put(p.y, &d)
            put(p.z, &d)
            let c = cols[i]
            d.append(UInt8((c >> 16) & 0xFF))
            d.append(UInt8((c >> 8) & 0xFF))
            d.append(UInt8(c & 0xFF))
        }
        return d
    }
}

final class FileServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "http.server")
    var fileURL: URL?

    func start(port: UInt16 = 8081) {
        guard listener == nil else { return }
        listener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] c in
            c.start(queue: DispatchQueue.global())
            c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                var out: Data
                if let url = self?.fileURL, let body = try? Data(contentsOf: url) {
                    let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"\(url.lastPathComponent)\"\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                    out = Data(head.utf8)
                    out.append(body)
                } else {
                    let msg = "Aun no hay un escaneo exportado"
                    out = Data("HTTP/1.1 404 Not Found\r\nContent-Length: \(msg.utf8.count)\r\nConnection: close\r\n\r\n\(msg)".utf8)
                }
                c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
            }
        }
        listener?.start(queue: queue)
    }
}

extension ARManager {
    func modeChanged(from old: ViewMode) {
        if (mode == .scan) != (old == .scan) {
            configureSession(world: mode == .scan)
        }
        if mode != .scan { scanning = false }
    }

    func configureSession(world: Bool) {
        let cfg = ARFaceTrackingConfiguration()
        if world && ARFaceTrackingConfiguration.supportsWorldTracking {
            cfg.isWorldTrackingEnabled = true
        }
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }

    func flash(_ s: String) {
        DispatchQueue.main.async {
            self.toast = s
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.toast = "" }
        }
    }

    func clearScan() {
        work.async {
            self.store.reset()
            DispatchQueue.main.async {
                self.scanCount = 0
                self.scanPreview = []
                self.scanColors = []
            }
        }
    }

    func exportScan() {
        work.async {
            let n = self.store.count
            if n == 0 {
                self.flash("No hay puntos para exportar")
                return
            }
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd-HHmmss"
            let name = "scan-\(df.string(from: Date())).ply"
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(name)
            do {
                try self.store.plyData().write(to: url)
            } catch {
                self.flash("Error al guardar el PLY")
                return
            }
            self.files.fileURL = url
            DispatchQueue.main.async { self.shareItem = ShareItem(url: url) }
            self.flash("PLY guardado: \(n) puntos")
        }
    }

    func scanTick(_ frame: ARFrame) {
        let now = Date()
        guard let depth = frame.capturedDepthData else { return }
        let ts = frame.capturedDepthDataTimestamp
        if ts == lastScanDepthTs { return }
        lastScanDepthTs = ts

        if case .normal = frame.camera.trackingState {
            ingest(frame: frame, depth: depth)
        } else if now.timeIntervalSince(lastHaptic) > 1.5 {
            lastHaptic = now
            DispatchQueue.main.async {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }

        if store.isFull {
            DispatchQueue.main.async { self.scanning = false }
            flash("Límite de puntos alcanzado")
        }

        if now.timeIntervalSince(lastScanPublish) > 0.4 {
            lastScanPublish = now
            let s = store.sample(limit: 20000)
            let count = store.count
            DispatchQueue.main.async {
                self.scanCount = count
                self.scanPreview = s.points
                self.scanColors = s.colors
                self.scanCenter = s.center
                self.scanRadius = s.radius
            }
        }
    }

    func ingest(frame: ARFrame, depth: AVDepthData) {
        let d = depth.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depth
            : depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = d.depthDataMap
        let cbuf = frame.capturedImage
        CVPixelBufferLockBaseAddress(map, .readOnly)
        CVPixelBufferLockBaseAddress(cbuf, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(cbuf, .readOnly)
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
        }
        guard let base = CVPixelBufferGetBaseAddress(map),
              CVPixelBufferGetPlaneCount(cbuf) >= 2,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(cbuf, 0),
              let cBase = CVPixelBufferGetBaseAddressOfPlane(cbuf, 1)
        else { return }

        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        let cw = CVPixelBufferGetWidthOfPlane(cbuf, 0)
        let ch = CVPixelBufferGetHeightOfPlane(cbuf, 0)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(cbuf, 0)
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(cbuf, 1)
        let yPtr = yBase.assumingMemoryBound(to: UInt8.self)
        let cPtr = cBase.assumingMemoryBound(to: UInt8.self)

        var fx = Float(w) * 0.87
        var fy = fx
        var cx = Float(w) / 2
        var cy = Float(h) / 2
        if let cal = d.cameraCalibrationData {
            let k = cal.intrinsicMatrix
            let ref = cal.intrinsicMatrixReferenceDimensions
            if ref.width > 0 && ref.height > 0 {
                let sx = Float(w) / Float(ref.width)
                let sy = Float(h) / Float(ref.height)
                fx = k[0][0] * sx
                fy = k[1][1] * sy
                cx = k[2][0] * sx
                cy = k[2][1] * sy
            }
        }

        let near = Float(nearCm / 100)
        let far = Float(Swift.max(farCm, nearCm + 10) / 100)
        let T = frame.camera.transform
        let flip: Float = scanFlipX ? -1 : 1
        let fw = Float(w)
        let fh = Float(h)
        let colW = Float(ch) * 4 / 3
        let step = 3

        for y in stride(from: 0, to: h - 1, by: step) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in stride(from: 0, to: w - 1, by: step) {
                let z = row[x]
                if !(z.isFinite && z >= near && z <= far) { continue }
                if abs(z - row[x + 1]) > 0.015 { continue }

                let px = flip * (Float(x) - cx) * z / fx
                let py = -(Float(y) - cy) * z / fy
                let wp = T * SIMD4<Float>(px, py, -z, 1)

                let uf = Float(cw) / 2 + (Float(x) / fw - 0.5) * colW
                let vf = Float(y) / fh * Float(ch)
                let uc = Swift.min(cw - 1, Swift.max(0, Int(uf)))
                let vc = Swift.min(ch - 1, Swift.max(0, Int(vf)))
                let yv = Float(yPtr[vc * yStride + uc])
                let ci = (vc / 2) * cStride + (uc / 2) * 2
                let cbv = Float(cPtr[ci]) - 128
                let crv = Float(cPtr[ci + 1]) - 128
                let yy = 1.164 * (yv - 16)
                let r = UInt32(Swift.min(Swift.max(yy + 1.596 * crv, 0), 255))
                let g = UInt32(Swift.min(Swift.max(yy - 0.813 * crv - 0.392 * cbv, 0), 255))
                let b = UInt32(Swift.min(Swift.max(yy + 2.017 * cbv, 0), 255))
                store.add(SIMD3<Float>(wp.x, wp.y, wp.z), (r << 16) | (g << 8) | b)
            }
        }
    }
}
