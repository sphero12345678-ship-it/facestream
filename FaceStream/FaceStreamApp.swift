import SwiftUI

@main
struct FaceStreamApp: App {
    @StateObject var m = ARManager()
    var body: some Scene {
        WindowGroup {
            ContentView(m: m)
                .preferredColorScheme(.dark)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    m.start()
                }
        }
    }
}
