import AVFoundation
import UIKit

final class CaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer, Bool) -> Void)?
    var onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "cap.queue")
    private var single: AVCaptureSession?
    private var multi: AVCaptureMultiCamSession?
    private var frontOut: AVCaptureVideoDataOutput?
    private var backOut: AVCaptureVideoDataOutput?

    func start(front: Bool, back: Bool) {
        stop()
        queue.async { [weak self] in
            guard let self = self else { return }
            if front && back {
                self.startMulti()
            } else {
                self.startSingle(position: back ? .back : .front)
            }
        }
    }

    func stop() {
        queue.sync {
            single?.stopRunning()
            multi?.stopRunning()
            single = nil
            multi = nil
            frontOut = nil
            backOut = nil
        }
    }

    private func makeOutput() -> AVCaptureVideoDataOutput {
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        return out
    }

    private func setup(_ conn: AVCaptureConnection) {
        if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = false
        }
    }

    private func startSingle(position: AVCaptureDevice.Position) {
        let s = AVCaptureSession()
        s.beginConfiguration()
        s.sessionPreset = .hd1280x720
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: dev),
              s.canAddInput(input)
        else {
            s.commitConfiguration()
            onError?("No pude abrir la cámara")
            return
        }
        s.addInput(input)
        let out = makeOutput()
        guard s.canAddOutput(out) else {
            s.commitConfiguration()
            onError?("No pude crear la salida de video")
            return
        }
        s.addOutput(out)
        if let c = out.connection(with: .video) { setup(c) }
        s.commitConfiguration()
        if position == .back { backOut = out } else { frontOut = out }
        single = s
        s.startRunning()
    }

    private func configureFormat(_ dev: AVCaptureDevice) {
        let candidates = dev.formats.filter { $0.isMultiCamSupported }
        let target: Int32 = 1280
        let best = candidates.min { a, b in
            let da = abs(CMVideoFormatDescriptionGetDimensions(a.formatDescription).width - target)
            let db = abs(CMVideoFormatDescriptionGetDimensions(b.formatDescription).width - target)
            return da < db
        }
        guard let f = best else { return }
        do {
            try dev.lockForConfiguration()
            dev.activeFormat = f
            let ok = f.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 15 && 15 <= $0.maxFrameRate }
            if ok {
                dev.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
                dev.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            }
            dev.unlockForConfiguration()
        } catch {}
    }

    private func startMulti() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            onError?("Este iPhone no soporta usar ambas cámaras a la vez")
            return
        }
        let s = AVCaptureMultiCamSession()
        s.beginConfiguration()
        var ok = 0
        for pos in [AVCaptureDevice.Position.front, AVCaptureDevice.Position.back] {
            guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos) else { continue }
            configureFormat(dev)
            guard let input = try? AVCaptureDeviceInput(device: dev), s.canAddInput(input) else { continue }
            s.addInputWithNoConnections(input)
            let out = makeOutput()
            guard s.canAddOutput(out) else { continue }
            s.addOutputWithNoConnections(out)
            guard let port = input.ports(for: .video,
                                         sourceDeviceType: dev.deviceType,
                                         sourceDevicePosition: pos).first else { continue }
            let conn = AVCaptureConnection(inputPorts: [port], output: out)
            guard s.canAddConnection(conn) else { continue }
            s.addConnection(conn)
            setup(conn)
            if pos == .front { frontOut = out } else { backOut = out }
            ok += 1
        }
        s.commitConfiguration()
        if ok < 2 || s.hardwareCost > 1.0 {
            onError?("No se pudieron abrir las dos cámaras a la vez (costo \(s.hardwareCost))")
            return
        }
        multi = s
        s.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pb, output === backOut)
    }
}
