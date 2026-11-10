import SwiftUI

enum SourceMode: String, CaseIterable, Identifiable {
    case faceID = "Face ID"
    case back = "Trasera"
    case both = "Ambas"
    var id: String { rawValue }
}

struct SourcePicker: View {
    @ObservedObject var m: ARManager

    var body: some View {
        Picker("Fuente", selection: $m.source) {
            ForEach(SourceMode.allCases) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}

struct OverlayCanvas: View {
    let o: Overlay
    let showHands: Bool
    let showBodyPts: Bool

    var body: some View {
        Canvas { ctx, size in
            if showHands {
                ctx.stroke(ContentView.linesPath(o.handLines, size),
                           with: .color(Color.green), lineWidth: 2)
                ctx.fill(ContentView.dotsPath(o.handPoints, size, 3),
                         with: .color(Color.white))
            }
            if showBodyPts {
                ctx.stroke(ContentView.linesPath(o.bodyLines, size),
                           with: .color(Color.orange), lineWidth: 3)
                ctx.fill(ContentView.dotsPath(o.bodyPoints, size, 4),
                         with: .color(Color.yellow))
            }
        }
    }
}

struct SourceStage: View {
    @ObservedObject var m: ARManager

    var body: some View {
        if m.source == .both {
            VStack(spacing: 4) {
                pane(m.preview, m.overlay, mirror: m.mirror, label: "Face ID")
                pane(m.previewBack, m.overlayBack, mirror: false, label: "Trasera")
            }
        } else {
            pane(m.previewBack, m.overlayBack, mirror: false, label: "Trasera")
        }
    }

    private func pane(_ img: UIImage?, _ o: Overlay, mirror: Bool, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            if let img = img {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .overlay(OverlayCanvas(o: o, showHands: m.showHands, showBodyPts: m.showBody))
                    .scaleEffect(x: mirror ? -1 : 1, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Esperando cámara…")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(label)
                .font(.caption2)
                .padding(4)
                .background(Color.black.opacity(0.55))
                .foregroundColor(.white)
                .cornerRadius(4)
                .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct SourceControls: View {
    @ObservedObject var m: ARManager

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button { m.snapshot() } label: { Image(systemName: "camera.fill") }
                        .buttonStyle(.bordered)
                    Toggle("Manos", isOn: $m.showHands)
                    Toggle("Cuerpo", isOn: $m.showBody)
                    Toggle("Espejo", isOn: $m.mirror)
                    Toggle("Stream", isOn: $m.streaming)
                }
                .toggleStyle(.button)
                .tint(.cyan)
            }
            Text(m.status.isEmpty ? "Sin tracking facial ni profundidad en este modo" : m.status)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding()
    }
}
