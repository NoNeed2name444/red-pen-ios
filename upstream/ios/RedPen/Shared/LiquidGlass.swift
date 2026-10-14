import SwiftUI

// MARK: - Chrome, shaped from the base
//
// The app was glass once; now its chrome is soft UI like everything else:
// a floating bar or a small chip is the matte base raised off itself, lit
// from the top left (WardSurfaces draws it). The names stay so the screens
// that float a bar or a chip keep saying what they mean.

extension View {
    /// A floating bottom control bar: a soft slab raised high off the base.
    /// `tint` is accepted for older callers; the bar is the base's colour.
    func liquidGlassPanel(cornerRadius: CGFloat = 22, tint: Color = .clear) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return wardRaised(in: shape, lift: .high)
    }

    /// A small capsule raised just off the base: the score / progress chips
    /// in a mode's header. `tint` is accepted for older callers; a chip's
    /// colour is in its label.
    func liquidGlassChip(tint: Color? = nil) -> some View {
        wardRaised(in: Capsule(), lift: .low)
    }

    /// The bar, standing out of the screen at `plane` (see PopOut.swift):
    /// the plane's relief is its face, so it is never shaped twice.
    func liquidGlassPanel(cornerRadius: CGFloat = 22, tint: Color = .clear, plane: PopOutPlane) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return popOut(max(plane, .raised), in: shape)
    }

    /// The chip, standing out of the screen at `plane`.
    func liquidGlassChip(tint: Color? = nil, plane: PopOutPlane) -> some View {
        popOut(max(plane, .raised), in: Capsule())
    }
}
