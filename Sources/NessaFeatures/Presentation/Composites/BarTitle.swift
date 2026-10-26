import NessaDesignSystem
import SwiftUI

/// A pushed page's title, in the bar's leading corner beside the back button, bold and bare,
/// rather than as a large title under it, so the page's content starts higher. On iOS 26 a
/// bar item gets a glass capsule of its own, which a title should not wear. It takes the
/// principal place's job, so that place holds nothing.
struct BarTitle: ToolbarContent {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some ToolbarContent {
    #if os(iOS)
      if #available(iOS 26.0, *) {
        ToolbarItem(placement: .topBarLeading) { title }.sharedBackgroundVisibility(.hidden)
      } else {
        ToolbarItem(placement: .topBarLeading) { title }
      }
      ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
    #else
      ToolbarItem(placement: .navigation) { title }
    #endif
  }

  private var title: some View {
    // At its own width: a bar item is otherwise measured narrow and the title cut to "A…".
    Text(text).font(MessagesStyle.barTitle).fixedSize().accessibilityAddTraits(.isHeader)
  }
}
