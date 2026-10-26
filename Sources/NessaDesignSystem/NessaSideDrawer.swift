import SwiftUI

/// The drawer's measures and timing.
public enum NessaDrawerStyle {
  /// How much of the content stays in view while the drawer is open: enough to see
  /// what a tap there will close.
  public static let peek: CGFloat = 72
  /// How far in from the leading edge a drag may start and still open the drawer.
  public static let edgeGrab: CGFloat = 28
  /// The share of the drawer's width a drag has to cover to settle the other way.
  public static let settleFraction: CGFloat = 0.35
  /// A flick this fast settles in its own direction, however short.
  public static let flickVelocity: CGFloat = 600
  /// The content's corner while it is pushed aside.
  public static let contentRadius: CGFloat = 40
  /// How far the pushed content darkens at the drawer's full width.
  public static let contentDim: Double = 0.35
  /// A drawer opening or closing: the motion guide's sheets-and-drawers band.
  public static let motion = Animation.spring(duration: 0.28, bounce: 0)
}

/// A sidebar under the content, uncovered by pushing the content aside: a drag from the
/// leading edge or `isOpen` opens it; a drag back, or a tap on the content still in view,
/// closes it.
///
/// One value, `progress` (0 closed, 1 open), places everything: the content's offset,
/// its corner and its dim. A drag only moves that value; letting go settles it.
public struct NessaSideDrawer<Sidebar: View, Content: View>: View {
  @Binding var isOpen: Bool
  /// Whether a drag from the edge may open it. Off where the edge drag means something
  /// else, such as going back in a navigation stack.
  let edgeDragEnabled: Bool
  let sidebar: Sidebar
  let content: Content
  @GestureState private var drag: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection

  public init(
    isOpen: Binding<Bool>, edgeDragEnabled: Bool = true,
    @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content
  ) {
    _isOpen = isOpen
    self.edgeDragEnabled = edgeDragEnabled
    self.sidebar = sidebar()
    self.content = content()
  }

  public var body: some View {
    // Measured inside the safe area, to learn its insets; drawn edge to edge, so the pushed
    // content is one whole card down to the screen's corners.
    GeometryReader { outer in
      let insets = outer.safeAreaInsets
      let full = CGSize(
        width: outer.size.width + insets.leading + insets.trailing,
        height: outer.size.height + insets.top + insets.bottom)
      let width = max(full.width - NessaDrawerStyle.peek, 1)
      let progress = progress(width: width)
      ZStack(alignment: .leading) {
        sidebar
          // The sidebar keeps clear of the status bar and the home indicator itself.
          .padding(.top, insets.top)
          .padding(.bottom, insets.bottom)
          .frame(width: width, height: full.height)
          // Hidden from VoiceOver while closed, so swiping through the screen reads only the
          // content.
          .accessibilityHidden(!isOpen)
          .allowsHitTesting(isOpen)
        content
          .frame(width: full.width, height: full.height)
          .overlay {
            Color.black.opacity(NessaDrawerStyle.contentDim * progress)
              .allowsHitTesting(false)
          }
          .clipShape(
            RoundedRectangle(
              cornerRadius: NessaDrawerStyle.contentRadius * min(progress * 4, 1),
              style: .continuous)
          )
          .accessibilityHidden(isOpen)
          .offset(x: width * progress)
        if isOpen {
          // Over the pushed content while open, as its own layer: a tap anywhere on what is
          // still in view closes the drawer, and nothing inside the content is pressed.
          Rectangle().fill(.clear)
            .contentShape(Rectangle())
            .frame(width: full.width - width * progress, height: full.height)
            .offset(x: width * progress)
            .onTapGesture { close() }
            .accessibilityElement()
            .accessibilityLabel("Close sidebar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { close() }
        }
      }
      .frame(width: full.width, height: full.height, alignment: .topLeading)
      .contentShape(Rectangle())
      .simultaneousGesture(dragGesture(width: width), including: .all)
      .ignoresSafeArea(.container)
    }
  }

  private func progress(width: CGFloat) -> CGFloat {
    let travel = layoutDirection == .rightToLeft ? -drag : drag
    let base: CGFloat = isOpen ? 1 : 0
    return min(max(base + travel / width, 0), 1)
  }

  private func dragGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12, coordinateSpace: .local)
      .updating($drag) { value, state, _ in
        guard accepts(value) else { return }
        state = value.translation.width
      }
      .onEnded { value in
        guard accepts(value) else { return }
        let sign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        let travel = value.translation.width * sign
        let velocity = value.velocity.width * sign
        let open: Bool
        if abs(velocity) > NessaDrawerStyle.flickVelocity {
          open = velocity > 0
        } else {
          let moved = travel / width
          open = isOpen ? moved > -NessaDrawerStyle.settleFraction
            : moved > NessaDrawerStyle.settleFraction
        }
        withAnimation(reduceMotion ? nil : NessaDrawerStyle.motion) { isOpen = open }
      }
  }

  /// A closed drawer answers only a sideways drag that starts at the edge; an open one, any
  /// sideways drag, so it can be pushed shut from anywhere.
  private func accepts(_ value: DragGesture.Value) -> Bool {
    guard abs(value.translation.width) > abs(value.translation.height) else { return false }
    if isOpen { return true }
    guard edgeDragEnabled else { return false }
    return value.startLocation.x <= NessaDrawerStyle.edgeGrab
  }

  private func close() {
    withAnimation(reduceMotion ? nil : NessaDrawerStyle.motion) { isOpen = false }
  }
}
