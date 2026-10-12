import SwiftUI

// A round dot sticker stuck on the paper's corner: the note has priority.
struct PrioritySticker: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.96, green: 0.45, blue: 0.38),
                                                  Color(red: 0.84, green: 0.27, blue: 0.23)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: max(1, size * 0.07))
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-12))
        .shadow(color: .black.opacity(0.28), radius: 1.5, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}
