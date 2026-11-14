import AVFoundation
import UIKit

final class CaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "cap.queue")
    private var session: AVCaptureSession?

    func start(position: AVCaptureDevice.Position) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.session?.stopRunning()
            self.session = nil

            let s = AVCaptureSession()
            s.beginConfiguration()
            s.sessionPreset = .hd1280x720
            guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: dev),
                  s.canAddInput(input)
            else {
                s.commitConfiguration()
                self.onError?("No pude abrir la cámara")
                return
            }
            s.addInput(input)

            let out = AVCaptureVideoDataOutput()
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: self.queue)
            guard s.canAddOutput(out) else {
                s.commitConfiguration()
                self.onError?("No pude crear la salida de video")
                return
            }
            s.addOutput(out)
            if let c = out.connection(with: .video) {
                if c.isVideoOrientationSupported { c.videoOrientation = .portrait }
                if c.isVideoMirroringSupported {
                    c.automaticallyAdjustsVideoMirroring = false
                    c.isVideoMirrored = false
                }
            }
            s.commitConfiguration()
            self.session = s
            s.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session?.stopRunning()
            self?.session = nil
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pb)
    }
}
