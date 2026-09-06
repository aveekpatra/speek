import SwiftUI

struct ModeIconView: View {
    let icon: ModeIcon
    var size: CGFloat = 18
    var color: Color = .primary

    var body: some View {
        Group {
            switch icon.kind {
            case .symbol:
                Image(systemName: icon.value)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(color)
            case .emoji:
                Text(icon.value)
                    .font(.system(size: size))
            }
        }
    }
}
