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
    case video = "Cam"
    case depth = "Prof"
    case blend = "Mezcla"
    case split = "Split"
    case cloud = "3D"
    case scan = "Scan"
    var id: String { rawValue }
}
