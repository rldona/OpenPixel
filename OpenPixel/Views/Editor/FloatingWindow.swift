import SwiftUI

/// A small window like Aseprite's dialogs: it floats over the editor (at first at
/// the canvas's top right) and can be dragged by its title. Where it was dragged
/// to is kept between uses, under its own key.
struct FloatingWindow<Accessory: View, Content: View>: View {
    let title: Text
    /// The space it can be dragged in.
    let area: CGSize
    /// How far its starting place is from the area's right edge.
    let trailingInset: CGFloat
    /// Roughly how tall it is, to keep it inside the area.
    let approximateHeight: CGFloat
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content
    @AppStorage private var offsetX: Double
    @AppStorage private var offsetY: Double
    @GestureState private var drag = CGSize.zero
    static var width: CGFloat { EditorView.panelWidth - 16 }

    init(_ title: Text, id: String, area: CGSize, trailingInset: CGFloat, approximateHeight: CGFloat,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.area = area
        self.trailingInset = trailingInset
        self.approximateHeight = approximateHeight
        self.accessory = accessory()
        self.content = content()
        _offsetX = AppStorage(wrappedValue: 0, "\(id)WindowX")
        _offsetY = AppStorage(wrappedValue: 0, "\(id)WindowY")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    title.font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
                // Double tap the title to put it back at the canvas's top right; kept
                // off the buttons so their taps aren't held back waiting for a second one.
                .onTapGesture(count: 2) { withAnimation(.snappy) { offsetX = 0; offsetY = 0 } }
                accessory
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .accessibilityHint(Text("Drag to move the window"))

            content
        }
        .padding(14)
        .frame(width: Self.width)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .offset(clamped(CGSize(width: offsetX + drag.width, height: offsetY + drag.height)))
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let end = clamped(CGSize(width: offsetX + value.translation.width, height: offsetY + value.translation.height))
                offsetX = end.width
                offsetY = end.height
            }
    }

    /// Keeps it inside the editor.
    private func clamped(_ offset: CGSize) -> CGSize {
        let maxLeft = max(0, area.width - Self.width - trailingInset - 8), maxRight = max(0, trailingInset - 8)
        let maxDown = max(0, area.height - approximateHeight - 24)
        return CGSize(width: min(maxRight, max(-maxLeft, offset.width)), height: min(maxDown, max(-8, offset.height)))
    }
}
