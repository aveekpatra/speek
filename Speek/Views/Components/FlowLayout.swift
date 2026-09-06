import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let boundedProposal = ProposedViewSize(width: bounds.width, height: proposal.height)
        let result = computeLayout(proposal: boundedProposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: boundedProposal
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        // Two passes: first bucket subviews into rows, then place each row's items
        // centered on that row's tallest item — a plain top-align (single pass) left
        // shorter controls like the borderless "Add another" menu button sitting
        // noticeably higher than the taller language chips next to it.
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var rowWidth: CGFloat = 0
        var maxX: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(proposal)
            let width = min(size.width, maxWidth)

            if rowWidth > 0, rowWidth + width > maxWidth {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append((index, size))
            rowWidth += width + spacing
            maxX = max(maxX, rowWidth - spacing)
        }

        var positions = [CGPoint](repeating: .zero, count: subviews.count)
        var y: CGFloat = 0
        var totalHeight: CGFloat = 0
        for row in rows {
            guard !row.isEmpty else { continue }
            let rowHeight = row.map(\.size.height).max() ?? 0
            var x: CGFloat = 0
            for (index, size) in row {
                positions[index] = CGPoint(x: x, y: y + (rowHeight - size.height) / 2)
                x += size.width + spacing
            }
            y += rowHeight + spacing
            totalHeight = y - spacing
        }

        return (CGSize(width: maxWidth.isFinite ? maxWidth : maxX, height: max(totalHeight, 0)), positions)
    }
}
