def patch(path, pairs):
    s = open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, "%s: no encontre (o hay varios): %r" % (path, old[:70])
        s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)

m = open('FaceStream/Models.swift', encoding='utf-8').read()
if 'case scan' not in m:
    patch('FaceStream/Models.swift', [
        ('    case cloud = "3D"\n', '    case cloud = "3D"\n    case scan = "Scan"\n'),
    ])

v = open('FaceStream/VisionProcessor.swift', encoding='utf-8').read()
if 'var tag' not in v:
    patch('FaceStream/VisionProcessor.swift', [
        ('import Vision\n', 'import Vision\nimport ImageIO\n'),
        ('    var detectHands = true\n',
         '    var orientation: CGImagePropertyOrientation = .right\n    var tag = "front"\n    var detectHands = true\n'),
        ('VNImageRequestHandler(cvPixelBuffer: pb, orientation: .right, options: [:])',
         'VNImageRequestHandler(cvPixelBuffer: pb, orientation: orientation, options: [:])'),
        ('["hands": handsJSON, "body": bodyJSON]',
         '["hands": handsJSON, "body": bodyJSON, "src": self.tag]'),
    ])

patch('FaceStream/ContentView.swift', [
    ('            SourceStage(m: m)\n',
     '            camPane(depth: false)\n'),
    (r'''            if m.source == .faceID {
                Image(systemName: "faceid")
                    .foregroundColor(m.faceTracked ? Color.green : Color.red)
                Text("\(m.fps) fps")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
            }
''', r'''            if m.source != .back {
                Image(systemName: "faceid")
                    .foregroundColor(m.faceTracked ? Color.green : Color.red)
            }
            Text("\(m.fps) fps")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.gray)
'''),
    ('                    if m.source == .faceID && m.showBlends && m.mode != .scan && !m.blends.isEmpty {\n',
     '                    if m.showBlends && m.showBlendCard && !m.blends.isEmpty {\n'),
    (r'''                if m.source == .faceID {
                    ToggleChip(title: "Malla", icon: "faceid", isOn: $m.showFace)
                    ToggleChip(title: "Blendshapes", icon: "waveform", isOn: $m.showBlends)
                }
''', r'''                if m.source == .faceID {
                    ToggleChip(title: "Malla", icon: "faceid", isOn: $m.showFace)
                }
                if m.source != .back {
                    ToggleChip(title: "Blendshapes", icon: "waveform", isOn: $m.showBlends)
                }
'''),
    ('            Chips(items: SourceMode.allCases, label: { $0.rawValue }, selection: $m.source)\n',
     r'''            Chips(items: SourceMode.allCases, label: { $0.rawValue }, selection: $m.source)
            Text(m.sourceHint)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
'''),
])
print("Fuentes rehechas OK")
