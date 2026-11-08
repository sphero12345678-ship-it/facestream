import SwiftUI

struct ContentView: View {
    @ObservedObject var m: ARManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                stage
                controls
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("FaceStream").font(.headline).foregroundColor(.white)
                Text("ws://\(m.ip):8080")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(m.faceTracked ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(m.faceTracked ? "Cara" : "Sin cara")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                Text("\(m.fps) fps · \(m.clients) cliente(s)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var stage: some View {
        ZStack(alignment: .bottom) {
            if let img = m.preview {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .opacity(m.mode == .video ? 1 : 0)
                    .overlay(depthLayer)
                    .overlay(skeleton)
                    .scaleEffect(x: m.mirror ? -1 : 1, y: 1)
            } else {
                Text(m.status.isEmpty ? "Esperando cámara…" : m.status)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !m.headPose.isEmpty {
                Text(m.headPose)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(6)
                    .background(Color.black.opacity(0.55))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var depthLayer: some View {
        if m.mode == .depth, let d = m.depthImage {
            Image(uiImage: d)
                .resizable()
                .scaledToFill()
                .clipped()
        }
    }

    private var skeleton: some View {
        let o = m.overlay
        let showFace = m.showFace
        let showHands = m.showHands
        let showBody = m.showBody
        return Canvas { ctx, size in
            if showFace {
                ctx.fill(ContentView.dotsPath(o.face, size, 1.2),
                         with: .color(Color.cyan.opacity(0.85)))
            }
            if showHands {
                ctx.stroke(ContentView.linesPath(o.handLines, size),
                           with: .color(Color.green), lineWidth: 2)
                ctx.fill(ContentView.dotsPath(o.handPoints, size, 3),
                         with: .color(Color.white))
            }
            if showBody {
                ctx.stroke(ContentView.linesPath(o.bodyLines, size),
                           with: .color(Color.orange), lineWidth: 3)
                ctx.fill(ContentView.dotsPath(o.bodyPoints, size, 4),
                         with: .color(Color.yellow))
            }
        }
    }

    private static func dotsPath(_ pts: [CGPoint], _ size: CGSize, _ r: CGFloat) -> Path {
        var path = Path()
        for p in pts {
            path.addEllipse(in: CGRect(x: p.x * size.width - r,
                                       y: p.y * size.height - r,
                                       width: r * 2, height: r * 2))
        }
        return path
    }

    private static func linesPath(_ lines: [[CGPoint]], _ size: CGSize) -> Path {
        var path = Path()
        for l in lines where l.count > 1 {
            path.move(to: CGPoint(x: l[0].x * size.width, y: l[0].y * size.height))
            for p in l.dropFirst() {
                path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height))
            }
        }
        return path
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if m.showBlends {
                VStack(spacing: 3) {
                    ForEach(m.blends) { b in
                        HStack(spacing: 6) {
                            Text(b.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 130, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.15))
                                    Capsule().fill(Color.cyan)
                                        .frame(width: g.size.width * CGFloat(min(max(b.value, 0), 1)))
                                }
                            }
                            .frame(height: 6)
                            Text(String(format: "%.2f", b.value))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                                .frame(width: 32)
                        }
                    }
                }
                .frame(minHeight: 110, alignment: .top)
            }
            Picker("Vista", selection: $m.mode) {
                ForEach(ViewMode.allCases) { v in
                    Text(v.rawValue).tag(v)
                }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Toggle("Malla", isOn: $m.showFace)
                    Toggle("Manos", isOn: $m.showHands)
                    Toggle("Cuerpo", isOn: $m.showBody)
                    Toggle("Blendshapes", isOn: $m.showBlends)
                    Toggle("Espejo", isOn: $m.mirror)
                    Toggle("Stream", isOn: $m.streaming)
                }
                .toggleStyle(.button)
                .tint(.cyan)
            }
        }
        .padding()
    }
}
