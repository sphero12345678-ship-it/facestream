import SwiftUI

struct ContentView: View {
    @ObservedObject var m: ARManager
    @State private var big: Int? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                stage
                controls
            }
        }
        .sheet(item: $m.shareItem) { item in
            ActivityView(url: item.url)
        }
        .overlay(alignment: .top) {
            if !m.toast.isEmpty {
                Text(m.toast)
                    .font(.footnote)
                    .padding(10)
                    .background(Color.cyan.opacity(0.9))
                    .foregroundColor(.black)
                    .cornerRadius(10)
                    .padding(.top, 60)
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

    private func chip(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, design: .monospaced))
            .padding(6)
            .background(Color.black.opacity(0.55))
            .foregroundColor(.white)
            .cornerRadius(6)
    }

    private var placeholder: some View {
        Text(m.status.isEmpty ? "Esperando cámara…" : m.status)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stage: some View {
        ZStack(alignment: .bottom) {
            switch m.mode {
            case .video:
                camPane(depth: false)
            case .depth:
                depthPane
            case .blend:
                camPane(depth: true)
            case .split:
                splitPane
            case .cloud:
                CloudView(m: m)
            case .scan:
                if m.scanShowModel {
                    ModelView(m: m)
                } else {
                    camPane(depth: true)
                }
            }
            VStack(spacing: 4) {
                if m.mode == .scan {
                    chip((m.scanning ? "● REC " : "❚❚ ") + "\(m.scanCount) pts")
                }
                if m.mode != .video, let c = m.centerCm {
                    chip("Centro: \(c) cm")
                }
                if !m.headPose.isEmpty {
                    chip(m.headPose)
                }
            }
            .padding(.bottom, 6)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func camPane(depth: Bool) -> some View {
        Group {
            if let img = m.preview {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .overlay(depthOverlay(show: depth, opacity: 0.6))
                    .overlay(skeleton)
                    .overlay(crosshair(show: depth))
                    .scaleEffect(x: m.mirror ? -1 : 1, y: 1)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var depthPane: some View {
        ZStack {
            if let d = m.depthImage {
                Image(uiImage: d)
                    .resizable()
                    .scaledToFit()
                    .overlay(crosshair(show: true))
                    .scaleEffect(x: m.mirror ? -1 : 1, y: 1)
            } else {
                Text("Esperando profundidad…").foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var splitPane: some View {
        VStack(spacing: 4) {
            if big != 1 {
                camPane(depth: false)
                    .contentShape(Rectangle())
                    .onTapGesture { big = (big == 0) ? nil : 0 }
            }
            if big != 0 {
                depthPane
                    .contentShape(Rectangle())
                    .onTapGesture { big = (big == 1) ? nil : 1 }
            }
        }
    }

    @ViewBuilder
    private func depthOverlay(show: Bool, opacity: Double) -> some View {
        if show, let d = m.depthImage {
            GeometryReader { g in
                Image(uiImage: d)
                    .resizable()
                    .scaledToFill()
                    .frame(width: g.size.width, height: g.size.height)
                    .clipped()
            }
            .opacity(opacity)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func crosshair(show: Bool) -> some View {
        if show {
            ZStack {
                Rectangle().fill(Color.white).frame(width: 18, height: 1.5)
                Rectangle().fill(Color.white).frame(width: 1.5, height: 18)
            }
            .shadow(radius: 1)
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

    static func dotsPath(_ pts: [CGPoint], _ size: CGSize, _ r: CGFloat) -> Path {
        var path = Path()
        for p in pts {
            path.addEllipse(in: CGRect(x: p.x * size.width - r,
                                       y: p.y * size.height - r,
                                       width: r * 2, height: r * 2))
        }
        return path
    }

    static func linesPath(_ lines: [[CGPoint]], _ size: CGSize) -> Path {
        var path = Path()
        for l in lines where l.count > 1 {
            path.move(to: CGPoint(x: l[0].x * size.width, y: l[0].y * size.height))
            for p in l.dropFirst() {
                path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height))
            }
        }
        return path
    }

    private var depthControls: some View {
        HStack {
            Text("Rango \(Int(m.farCm)) cm")
                .font(.caption2).foregroundColor(.white)
                .frame(width: 90, alignment: .leading)
            Slider(value: $m.farCm, in: 20...400, step: 5)
        }
        .tint(.cyan)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if m.showBlends && m.mode != .scan {
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
            if m.mode != .video {
                depthControls
            }
            if m.mode == .scan {
                ScanControls(m: m)
            }
            Picker("Vista", selection: $m.mode) {
                ForEach(ViewMode.allCases) { v in
                    Text(v.rawValue).tag(v)
                }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button { m.snapshot() } label: { Image(systemName: "camera.fill") }
                        .buttonStyle(.bordered)
                    Button { m.openGallery() } label: { Image(systemName: "photo.on.rectangle") }
                        .buttonStyle(.bordered)
                    Toggle("Color", isOn: $m.colorMap)
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

struct CloudView: View {
    @ObservedObject var m: ARManager
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var lastDrag: CGSize = .zero

    var body: some View {
        let pts = m.cloud
        let pivot = m.cloudPivot
        let near = Float(m.nearCm / 100)
        let far = Float(max(m.farCm, m.nearCm + 10) / 100)
        let useColor = m.colorMap
        let yw = yaw
        let pt = pitch

        return ZStack {
            Canvas { ctx, size in
                let cyw = cos(yw)
                let syw = sin(yw)
                let cpt = cos(pt)
                let spt = sin(pt)
                let f = Float(size.width) * 0.9
                let mx = Float(size.width) / 2
                let my = Float(size.height) / 2
                var paths = [Path](repeating: Path(), count: 8)
                for p in pts {
                    let z = p.z - pivot
                    let x1 = p.x * cyw + z * syw
                    let z1 = -p.x * syw + z * cyw
                    let y2 = p.y * cpt - z1 * spt
                    let z2 = p.y * spt + z1 * cpt
                    let depth = pivot + z2
                    if depth < 0.05 { continue }
                    let sx = mx + x1 * f / depth
                    let sy = my + y2 * f / depth
                    let n = min(max((p.z - near) / (far - near), 0), 0.999)
                    paths[Int(n * 8)].addRect(CGRect(x: CGFloat(sx), y: CGFloat(sy),
                                                     width: 2.2, height: 2.2))
                }
                for i in 0..<8 {
                    let t = Double(i) / 8
                    let c: Color = useColor
                        ? Color(hue: t * 0.7, saturation: 1, brightness: 1)
                        : Color(white: 1 - t)
                    ctx.fill(paths[i], with: .color(c))
                }
            }
            .scaleEffect(x: m.mirror ? -1 : 1, y: 1)
            if pts.isEmpty {
                Text("Esperando profundidad…").foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { v in
                    let dx = v.translation.width - lastDrag.width
                    let dy = v.translation.height - lastDrag.height
                    yaw += Float(dx) * 0.01
                    pitch += Float(dy) * 0.01
                    lastDrag = v.translation
                }
                .onEnded { _ in lastDrag = .zero }
        )
        .onTapGesture(count: 2) {
            yaw = 0
            pitch = 0
        }
    }
}
