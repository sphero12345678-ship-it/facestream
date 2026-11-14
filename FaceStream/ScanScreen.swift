import SwiftUI

struct ScanScreen: View {
    @ObservedObject var m: ARManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            live
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            HStack {
                Spacer()
                sideButtons
            }
            .padding(.trailing, 10)
        }
    }

    // MARK: Vista en vivo

    @ViewBuilder
    private var live: some View {
        if m.scanShowModel {
            ModelView(m: m)
        } else if m.nightVision {
            nightPane
        } else {
            cameraPane
        }
    }

    private var cameraPane: some View {
        GeometryReader { g in
            ZStack {
                if let img = m.preview {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                    if let d = m.depthImage {
                        Image(uiImage: d)
                            .resizable()
                            .scaledToFill()
                            .frame(width: g.size.width, height: g.size.height)
                            .clipped()
                            .opacity(0.5)
                    }
                } else {
                    ProgressView().tint(.green)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .scaleEffect(x: m.mirror ? -1 : 1, y: 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var nightPane: some View {
        GeometryReader { g in
            ZStack {
                if let d = m.depthImage {
                    Image(uiImage: d)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                } else {
                    Text("Esperando profundidad…").foregroundColor(.gray)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .scaleEffect(x: m.mirror ? -1 : 1, y: 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Barra superior

    private var counterText: String {
        (m.scanning ? "● REC  " : "❚❚  ") + "\(m.scanCount) pts"
    }

    private var rangeText: String {
        var s = "\(m.scanVoxelMM) mm · \(Int(m.farCm)) cm"
        if let c = m.centerCm { s += " · centro \(c)" }
        return s
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            GlassButton(icon: "xmark") {
                m.scanning = false
                m.mode = .video
            }
            Spacer()
            Text(counterText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(m.scanning ? Color.red : Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            Spacer()
            Text(rangeText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    // MARK: Botones laterales

    private var sideButtons: some View {
        VStack(spacing: 12) {
            GlassButton(icon: m.scanShowModel ? "video.fill" : "cube.transparent") {
                m.scanShowModel.toggle()
            }
            GlassButton(icon: m.nightVision ? "moon.fill" : "moon") {
                m.nightVision.toggle()
            }
            GlassButton(icon: "arrow.left.arrow.right") {
                m.mirror.toggle()
            }
            GlassButton(icon: "square.and.arrow.up") {
                m.exportScan()
            }
            GlassButton(icon: "trash") {
                m.clearScan()
            }
        }
    }

    // MARK: Barra inferior

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "ruler").foregroundColor(.white)
                Slider(value: $m.farCm, in: 20...300, step: 5)
                    .tint(.green)
                Text("\(Int(m.farCm)) cm")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 8) {
                ForEach([1, 2, 4, 8], id: \.self) { v in
                    Button { m.scanVoxelMM = v } label: {
                        Text("\(v) mm")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(m.scanVoxelMM == v ? Color.green : Color.white.opacity(0.15))
                            .foregroundColor(m.scanVoxelMM == v ? Color.black : Color.white)
                            .clipShape(Capsule())
                    }
                }
                ToggleChip(title: "Espejo X", icon: "arrow.left.arrow.right", isOn: $m.scanFlipX)
            }

            Button { m.scanning.toggle() } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 74, height: 74)
                    if m.scanning {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 58, height: 58)
                    }
                }
            }

            Text("Botones de volumen: iniciar o pausar")
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}
