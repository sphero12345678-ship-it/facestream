import Foundation
import CoreGraphics

struct Blend: Identifiable {
    let id: String
    let value: Float
}

struct Overlay {
    var face: [CGPoint] = []
    var handPoints: [CGPoint] = []
    var handLines: [[CGPoint]] = []
    var bodyPoints: [CGPoint] = []
    var bodyLines: [[CGPoint]] = []
}

enum ViewMode: String, CaseIterable, Identifiable {
    case video = "Video"
    case depth = "Profundidad"
    var id: String { rawValue }
}
