import SwiftUI

struct Chips<T: Hashable>: View {
    let items: [T]
    let label: (T) -> String
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button { selection = item } label: {
                        Text(label(item))
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selection == item ? Color.cyan : Color.white.opacity(0.12))
                            .foregroundColor(selection == item ? Color.black : Color.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct ToggleChip: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isOn ? Color.cyan.opacity(0.9) : Color.white.opacity(0.12))
            .foregroundColor(isOn ? Color.black : Color.white)
            .clipShape(Capsule())
        }
    }
}

struct GlassButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}

struct ContentView: View {
    @ObservedObject var m: ARManager
    @State private var panelOpen = true
    @State private var big: Int? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 8) {
                topBar
                stageCard
                bottomPanel
            }
            if !m.toast.isEmpty {
                VStack {
                    Text(m.toast)
                        .font(.footnote)
                        .padding(10)
                        .background(Color.cyan.opacity(0.95))
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
        .sheet(item: $m.shareItem) { item in
            ActivityView(url: item.url)
        }
    }

    // MARK: Barra superior

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(m.clients > 0 ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text("ws://\(m.ip):8080")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
            Spacer()
            if m.source == .faceID || m.source == .both {
                Image(systemName: "faceid")
                    .foregroundColor(m.faceTracked ? Color.green : Color.red)
            }
            Text("\(m.fps) fps")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
            HStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                Text("\(m.clients)")
            }
            .font(.caption)
            .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: Escenario

    private var stageCard: some View {
        ZStack {
            Color.white.opacity(0.04)
            stageContent
            hud
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var stageContent: some View {
        if m.hasDepth {
            depthStage
        } else {
            camPane(depth: false)
        }
    }

    @ViewBuilder
    private var depthStage: some View {
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
    }

    private var hud: some View {
        ZStack {
            VStack {
                HStack {
                    if m.showBlends && m.showBlendCard && !m.blends.isEmpty {
                        blendCard
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(10)

            HStack {
                Spacer()
                VStack(spacing: 10) {
                    GlassButton(icon: "camera.fill") { m.snapshot() }
                    GlassButton(icon: "photo.on.rectangle") { m.openGallery() }
                }
            }
            .padding(10)

            VStack {
                Spacer()
                VStack(spacing: 4) {
                    if m.hasDepth {
                        if m.mode == .scan {
                            chip((m.scanning ? "● REC " : "❚❚ ") + "\(m.scanCount) pts")
                        }
                        if m.mode != .video, let c = m.centerCm {
                            chip("Centro: \(c) cm")
                        }
                    }
                    if !m.headPose.isEmpty {
                        chip(m.headPose)
                    }
                }
                .allowsHitTesting(false)
            }
            .padding(.bottom, 8)
        }
    }

    private var blendCard: some View {
        VStack(spacing: 3) {
            ForEach(m.blends) { b in
                HStack(spacing: 6) {
                    Text(b.id)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 86, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(Color.cyan)
                                .frame(width: g.size.width * CGFloat(min(max(b.value, 0), 1)))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(8)
        .frame(width: 170)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
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
        VStack(spacing: 8) {
            ProgressView().tint(.cyan)
            Text(m.status.isEmpty ? "Iniciando cámara…" : m.status)
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
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

    // MARK: Panel inferior

    private func modeTitle(_ v: ViewMode) -> String {
        switch v {
        case .video: return "Cámara"
        case .depth: return "Profundidad"
        case .blend: return "Mezcla"
        case .split: return "Dividido"
        case .cloud: return "Nube 3D"
        case .scan: return "Escáner"
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { panelOpen.toggle() } }
            Chips(items: SourceMode.allCases, label: { m.sourceTitle($0) }, selection: $m.source)
            Text(m.sourceHint)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            if panelOpen {
                if m.hasDepth {
                    Chips(items: m.availableModes, label: modeTitle, selection: $m.mode)
                    if m.mode != .video {
                        rangeSlider
                    }
                    if m.mode == .scan {
                        ScanControls(m: m)
                            .padding(.horizontal, 12)
                    }
                }
                layerChips
            }
        }
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 8)
    }

    private var rangeSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "ruler").foregroundColor(.cyan)
            Slider(value: $m.farCm, in: 20...500, step: 5)
                .tint(.cyan)
            Text("\(Int(m.farCm)) cm")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 16)
    }

    private var layerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if m.source == .faceID {
                    ToggleChip(title: "Malla", icon: "faceid", isOn: $m.showFace)
                }
                if m.source == .faceID || m.source == .both {
                    ToggleChip(title: "Blendshapes", icon: "waveform", isOn: $m.showBlends)
                }
                ToggleChip(title: "Manos", icon: "hand.raised.fill", isOn: $m.showHands)
                ToggleChip(title: "Cuerpo", icon: "person.fill", isOn: $m.showBody)
                if m.hasDepth && m.mode != .video {
                    ToggleChip(title: "Color", icon: "paintpalette.fill", isOn: $m.colorMap)
                }
                ToggleChip(title: "Espejo", icon: "arrow.left.arrow.right", isOn: $m.mirror)
                ToggleChip(title: "Stream", icon: "dot.radiowaves.left.and.right", isOn: $m.streaming)
            }
            .padding(.horizontal, 12)
        }
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
