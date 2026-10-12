import SwiftUI

enum PostItType {
    static func title(_ size: CGFloat = 21) -> Font {
        .custom("Noteworthy-Bold", size: size, relativeTo: .headline)
    }

    static func body(_ size: CGFloat = 18) -> Font {
        .custom("Noteworthy-Light", size: size, relativeTo: .body)
    }
}
