import SwiftUI

@main
struct FaceStreamApp: App {
    @StateObject var m = ARManager()
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 14) {
                Text("FaceStream").font(.largeTitle).bold()
                Text("ws://\(m.ip):8080").font(.system(.title3, design: .monospaced))
                Text(m.status).foregroundColor(.secondary)
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                m.start()
            }
        }
    }
}
