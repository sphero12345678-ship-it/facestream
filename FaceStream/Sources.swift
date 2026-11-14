import SwiftUI

enum SourceMode: String, CaseIterable, Identifiable {
    case faceID = "Face ID"
    case lidar = "LiDAR"
    case front = "Frontal"
    case back = "Trasera"
    case both = "Face ID + Trasera"
    var id: String { rawValue }
}
