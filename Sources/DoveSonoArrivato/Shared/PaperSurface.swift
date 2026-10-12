import SwiftUI
import ImageIO

extension PaperColor {
    var paper: Color {
        switch self {
        case .yellow: return Color(red: 0.98, green: 0.91, blue: 0.65)
        case .peach: return Color(red: 0.98, green: 0.81, blue: 0.72)
        case .mint: return Color(red: 0.79, green: 0.89, blue: 0.78)
        case .blue: return Color(red: 0.78, green: 0.87, blue: 0.95)
        case .lilac: return Color(red: 0.88, green: 0.81, blue: 0.97)
        }
    }
}

struct PaperSurface: View {
    let color: PaperColor
    var body: some View {
        // A resizable image already fills the proposed background size; no GeometryReader needed.
        Group {
            if let image = Self.images[color] {
                Image(decorative: image, scale: 1).resizable()
            } else {
                Rectangle().fill(color.paper)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    // Decode every texture once, up front, so the first draw of each colour never stalls.
    private static let images: [PaperColor: CGImage] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        var images: [PaperColor: CGImage] = [:]
        for color in PaperColor.allCases {
            guard let url = bundle.url(forResource: "paper-\(color.rawValue)", withExtension: "png"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0,
                      [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { continue }
            images[color] = image
        }
        return images
    }()
}
