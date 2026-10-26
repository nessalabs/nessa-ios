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
  /// How long a closed drawer keeps its sidebar: past the close's motion, so the sidebar is
  /// there behind the content until it has slid home. Timed rather than taken from an
  /// animation's completion, because a drag let go short of the threshold springs back on
  /// the gesture's own reset, which reports no completion.
  public static let linger: Duration = .milliseconds(400)
}

/// A sidebar under the content, uncovered by pushing the content aside: a drag from the
/// leading edge or `isOpen` opens it; a drag back, or a tap on the content still in view,
/// closes it.
///
/// One value, `progress` (0 closed, 1 open), places everything: the content's offset,
/// its corner and its dim. A drag only moves that value; letting go settles it.
///
/// The sidebar is in the view tree only while some of it can be seen. Laid under a closed
/// drawer, it still took taps meant for the content above it, so a closed drawer drops it
/// rather than trusting it to stay out of the way.
public struct NessaSideDrawer<Sidebar: View, Content: View>: View {
  @Binding var isOpen: Bool
  /// Whether a drag from the edge may open it. Off where the edge drag means something
  /// else, such as going back in a navigation stack.
  let edgeDragEnabled: Bool
  let sidebar: Sidebar
  let content: Content
  /// How far the finger has moved the drawer while it is down. Let go without crossing
  /// over, it springs back rather than jumping.
  @GestureState(resetTransaction: Transaction(animation: NessaDrawerStyle.motion))
  private var drag: CGFloat = 0
  /// Where the drawer rests, 0 or 1. Every move to rest goes through `settle`.
  @State private var settled: CGFloat
  /// Whether the sidebar is in the tree: from the moment the drawer starts to open (by a drag
  /// or by `isOpen`) until it has been closed for `NessaDrawerStyle.linger`.
  @State private var live: Bool
  /// Counts settles at closed; each one starts the wait that takes the sidebar out.
  @State private var closings = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection

  public init(
    isOpen: Binding<Bool>, edgeDragEnabled: Bool = true,
    @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content
  ) {
    _isOpen = isOpen
    _settled = State(initialValue: isOpen.wrappedValue ? 1 : 0)
    _live = State(initialValue: isOpen.wrappedValue)
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
        if live {
          sidebar
            // The sidebar keeps clear of the status bar and the home indicator itself.
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            .frame(width: width, height: full.height)
            // Mid-drag or mid-close it is drawn but not pressed, and VoiceOver reads only
            // the content.
            .accessibilityHidden(!isOpen)
            .allowsHitTesting(isOpen)
        }
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
    // Opened or closed from outside; a drag that let go has already settled to match.
    .onChange(of: isOpen) { _, open in
      if settled != (open ? 1 : 0) { settle(open: open) }
    }
    // A drag that ends with the drawer still closed (let go short, turned vertical, or taken
    // by the system) uncovered the sidebar without settling: the same wait takes it out.
    .onChange(of: drag == 0) { _, idle in
      if idle, !isOpen { closings += 1 }
    }
    .task(id: closings) {
      guard closings > 0 else { return }
      try? await Task.sleep(for: NessaDrawerStyle.linger)
      // Opened again, or picked up by a new drag, while it waited: the sidebar stays.
      guard !Task.isCancelled, !isOpen, drag == 0 else { return }
      live = false
    }
  }

  /// Carries the drawer to rest, open or closed: the one place `settled` and `live` move.
  private func settle(open: Bool) {
    if open { live = true }
    withAnimation(reduceMotion ? nil : NessaDrawerStyle.motion) { settled = open ? 1 : 0 }
    if !open { closings += 1 }
  }

  private func progress(width: CGFloat) -> CGFloat {
    let travel = layoutDirection == .rightToLeft ? -drag : drag
    return min(max(settled + travel / width, 0), 1)
  }

  private func dragGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12, coordinateSpace: .local)
      .updating($drag) { value, state, _ in
        guard accepts(value) else { return }
        state = value.translation.width
      }
      .onChanged { value in
        // The sidebar comes into the tree as soon as a drag can uncover it.
        if accepts(value), !live { live = true }
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
        // Settled in the same update the drag resets in, so the drawer carries on from where
        // it was let go.
        settle(open: open)
        isOpen = open
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

  private func close() { isOpen = false }
}
