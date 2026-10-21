// Red Pen · words wrapped the way a paragraph wraps them, worked out once
// for both of a flow layout's passes (NarrateWordFlow's FlowLayout).
//
// The layout measured its lines against the width it was offered, said it
// was as wide as its widest line, and then placed the words against the
// width it was given: that same widest line, rounded to the screen's
// pixels. A hair of rounding sent that line's last word down onto a line
// no room had been made for, over the next paragraph ("pH." on "Three
// systems do the", Audio at XXL, 15 Oct). Both passes now break the lines
// here, against the width offered; and a point of give keeps the lines
// when a parent offers the layout back its own width, rounded down.
import Foundation

enum FlowLines {
    /// A word may run this far past the width and still fit: more than a
    /// pixel's rounding on any screen, less than anyone can see.
    static let give: Double = 1

    /// Which line each item goes on (0, 1, ...), for items this wide, laid
    /// `spacing` apart in lines `width` wide; an infinite width is one
    /// line. An item wider than a line has a line of its own.
    static func lines(widths: [Double], spacing: Double, width: Double) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(widths.count)
        var x: Double = 0
        var line: Int = 0
        for w in widths {
            if x > 0 && x + w > width + give {
                line += 1
                x = 0
            }
            out.append(line)
            x += w + spacing
        }
        return out
    }

    /// Each line's width, for items on `lines` (as `lines(widths:...)`
    /// gives them).
    static func lineWidths(widths: [Double], spacing: Double, lines: [Int]) -> [Double] {
        var out: [Double] = []
        for (w, line) in zip(widths, lines) {
            if line < out.count {
                out[line] += spacing + w
            } else {
                out.append(w)
            }
        }
        return out
    }
}
