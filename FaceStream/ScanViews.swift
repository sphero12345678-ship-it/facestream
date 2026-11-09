import SwiftUI

struct ModelView: View {
    @ObservedObject var m: ARManager
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var lastDrag: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1

    var body: some View {
        let pts = m.scanPreview
        let cols = m.scanColors
        let center = m.scanCenter
        let dist = Swift.max(m.scanRadius * 2.6, 0.15) / Float(zoom)
        let yw = yaw
        let pt = pitch

        return ZStack {
            Canvas { ctx, size in
                if pts.isEmpty || cols.count != pts.count { return }
                let cyw = cos(yw)
                let syw = sin(yw)
                let cpt = cos(pt)
                let spt = sin(pt)
                let f = Float(size.width) * 0.9
                let mx = Float(size.width) / 2
                let my = Float(size.height) / 2
                let cell: Float = 3
                let gw = Int(Float(size.width) / cell) + 1
                let gh = Int(Float(size.height) / cell) + 1
                var zbuf = [Float](repeating: Float.infinity, count: gw * gh)
                var best = [Int32](repeating: -1, count: gw * gh)

                for i in 0..<pts.count {
                    let p = pts[i] - center
                    let x1 = p.x * cyw + p.z * syw
                    let z1 = -p.x * syw + p.z * cyw
                    let y2 = p.y * cpt - z1 * spt
                    let z2 = p.y * spt + z1 * cpt
                    let depth = dist - z2
                    if depth < 0.03 { continue }
                    let sx = mx + x1 * f / depth
                    let sy = my - y2 * f / depth
                    let gx = Int(sx / cell)
                    let gy = Int(sy / cell)
                    if gx < 0 || gy < 0 || gx >= gw || gy >= gh { continue }
                    let gi = gy * gw + gx
                    if depth < zbuf[gi] {
                        zbuf[gi] = depth
                        best[gi] = Int32(i)
                    }
                }

                var paths: [Int: Path] = [:]
                let cs = CGFloat(cell)
                for gi in 0..<best.count {
                    let i = Int(best[gi])
                    if i < 0 { continue }
                    let c = cols[i]
                    let rr = Int((c >> 20) & 0xF)
                    let gg = Int((c >> 12) & 0xF)
                    let bb = Int((c >> 4) & 0xF)
                    let key = (rr << 8) | (gg << 4) | bb
                    let gx = gi % gw
                    let gy = gi / gw
                    let rect = CGRect(x: CGFloat(gx) * cs, y: CGFloat(gy) * cs, width: cs, height: cs)
                    paths[key, default: Path()].addRect(rect)
                }
                for (key, path) in paths {
                    let col = Color(red: Double((key >> 8) & 0xF) / 15,
                                    green: Double((key >> 4) & 0xF) / 15,
                                    blue: Double(key & 0xF) / 15)
                    ctx.fill(path, with: .color(col))
                }
            }
            if pts.isEmpty {
                Text("Sin puntos todavía. Toca Escanear.").foregroundColor(.gray)
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
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { v in zoom = Swift.min(Swift.max(baseZoom * v, 0.3), 5) }
                .onEnded { _ in baseZoom = zoom }
        )
        .onTapGesture(count: 2) {
            yaw = 0
            pitch = 0
            zoom = 1
            baseZoom = 1
        }
    }
}

struct ScanControls: View {
    @ObservedObject var m: ARManager

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { m.scanning.toggle() } label: {
                    Label(m.scanning ? "Pausar" : "Escanear",
                          systemImage: m.scanning ? "pause.fill" : "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(m.scanning ? .red : .cyan)

                Button { m.clearScan() } label: {
                    Label("Borrar", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Button { m.exportScan() } label: {
                    Label("PLY", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Toggle("Modelo", isOn: $m.scanShowModel)
                    .toggleStyle(.button)
            }
            HStack {
                Picker("Precisión", selection: $m.scanVoxelMM) {
                    Text("2 mm").tag(2)
                    Text("4 mm").tag(4)
                    Text("8 mm").tag(8)
                }
                .pickerStyle(.segmented)
                Toggle("Espejo X", isOn: $m.scanFlipX)
                    .toggleStyle(.button)
            }
            Text("PC: curl -OJ http://\(m.ip):8081")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
        }
        .tint(.cyan)
    }
}
