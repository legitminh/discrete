import CoreGraphics
import Foundation

@main
struct WindowBrowserLayoutTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func score(sizes: [CGSize], viewport: CGSize, columns: Int) -> CGFloat {
        let rows = Int(ceil(Double(sizes.count) / Double(columns)))
        let maxWidth = viewport.width / CGFloat(columns)
        let maxHeight = viewport.height / CGFloat(rows)
        return sizes.reduce(0) { sum, size in
            let ratio = size.width / size.height
            if maxWidth / maxHeight > ratio {
                return sum + maxHeight * maxHeight * ratio
            }
            return sum + maxWidth * maxWidth / ratio
        }
    }

    static func verify(_ sizes: [CGSize], viewport: CGSize) {
        let grid = WindowBrowserLayout.optimalGrid(imageSizes: sizes, viewport: viewport)
        let selected = score(sizes: sizes, viewport: viewport, columns: grid.columns)
        let best = (1...sizes.count).map { score(sizes: sizes, viewport: viewport, columns: $0) }.max()!
        expect(abs(selected - best) < 0.001, "Optimized grid must match exhaustive search")
        expect(grid.columns * grid.rows >= sizes.count, "Grid must hold every screenshot")
        expect((grid.columns - 1) * grid.rows < sizes.count, "Grid must not have a redundant column")
    }

    static func main() {
        expect(WindowBrowserLayout.optimalGrid(imageSizes: [], viewport: CGSize(width: 100, height: 100))
            == .init(columns: 0, rows: 0), "An empty browser has no grid")
        verify([CGSize(width: 16, height: 9)], viewport: CGSize(width: 1400, height: 800))
        verify(Array(repeating: CGSize(width: 16, height: 9), count: 7),
               viewport: CGSize(width: 1400, height: 800))
        verify([
            CGSize(width: 16, height: 9), CGSize(width: 4, height: 3),
            CGSize(width: 9, height: 16), CGSize(width: 21, height: 9),
            CGSize(width: 1, height: 1), CGSize(width: 3, height: 4)
        ], viewport: CGSize(width: 1512, height: 860))
        verify([
            CGSize(width: 5, height: 1), CGSize(width: 1, height: 5),
            CGSize(width: 8, height: 5), CGSize(width: 5, height: 8),
            CGSize(width: 2, height: 1), CGSize(width: 1, height: 2),
            CGSize(width: 7, height: 3), CGSize(width: 3, height: 7)
        ], viewport: CGSize(width: 900, height: 1400))
        print("Window browser layout: 4 optimized grids passed")
    }
}
