import CoreGraphics

/// The area-maximizing fixed grid from algo.fill.image. Every window keeps
/// its aspect ratio and receives one equal grid cell; the selected column /
/// row count maximizes the sum of rendered screenshot areas.
enum WindowBrowserLayout {
    struct Grid: Equatable {
        let columns: Int
        let rows: Int
    }

    static func optimalGrid(imageSizes: [CGSize], viewport: CGSize) -> Grid {
        let ratios = imageSizes.compactMap { size -> CGFloat? in
            guard size.width > 0, size.height > 0 else { return nil }
            return size.width / size.height
        }.sorted()
        let count = ratios.count
        guard count > 0, viewport.width > 0, viewport.height > 0 else {
            return Grid(columns: 0, rows: 0)
        }

        var ratioPrefix = Array(repeating: CGFloat.zero, count: count + 1)
        var inversePrefix = Array(repeating: CGFloat.zero, count: count + 1)
        for index in ratios.indices {
            ratioPrefix[index + 1] = ratioPrefix[index] + ratios[index]
            inversePrefix[index + 1] = inversePrefix[index] + 1 / ratios[index]
        }

        var best = Grid(columns: 1, rows: count)
        var bestScore = -CGFloat.infinity
        var columns = 1
        while columns <= count {
            let quotient = (count - 1) / columns
            let rows = quotient + 1
            let maxWidth = viewport.width / CGFloat(columns)
            let maxHeight = viewport.height / CGFloat(rows)
            let limitingRatio = maxWidth / maxHeight
            let split = upperBound(of: limitingRatio, in: ratios)
            let score = maxHeight * maxHeight * ratioPrefix[split]
                + maxWidth * maxWidth * (inversePrefix[count] - inversePrefix[split])
            if score > bestScore {
                bestScore = score
                best = Grid(columns: columns, rows: rows)
            }
            guard quotient > 0 else { break }
            columns = (count - 1) / quotient + 1
        }
        return best
    }

    private static func upperBound(of value: CGFloat, in values: [CGFloat]) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if values[middle] <= value {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}
