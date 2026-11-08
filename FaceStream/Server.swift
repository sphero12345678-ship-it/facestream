import Network
import Foundation

final class WSServer {
    private var listener: NWListener?
    private var clients: [NWConnection] = []
    private let queue = DispatchQueue(label: "ws.server")
    var onCount: ((Int) -> Void)?

    func start(port: UInt16 = 8080) {
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] c in
            guard let self = self else { return }
            c.stateUpdateHandler = { [weak self, weak c] s in
                guard let c = c else { return }
                switch s {
                case .failed, .cancelled: self?.remove(c)
                default: break
                }
            }
            c.start(queue: self.queue)
            self.queue.async {
                self.clients.append(c)
                self.onCount?(self.clients.count)
            }
            self.receive(c)
        }
        listener?.start(queue: queue)
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] _, _, _, err in
            if err != nil { self?.remove(c); return }
            self?.receive(c)
        }
    }

    private func remove(_ c: NWConnection) {
        queue.async {
            self.clients.removeAll { $0 === c }
            c.cancel()
            self.onCount?(self.clients.count)
        }
    }

    func broadcast(_ data: Data, text: Bool) {
        let meta = NWProtocolWebSocket.Metadata(opcode: text ? .text : .binary)
        let ctx = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
        queue.async {
            for c in self.clients where c.state == .ready {
                c.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
            }
        }
    }
}
