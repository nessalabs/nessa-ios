import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

extension View {
  /// A tap here puts the keyboard away, wherever its field is: the field's own focus lives in
  /// the composer, which this view can't reach. Simultaneous, so whatever was tapped (a button,
  /// a bubble) still answers it too.
  @ViewBuilder
  func nessaTapDismissesKeyboard() -> some View {
    #if os(iOS)
      self.simultaneousGesture(TapGesture().onEnded {
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      })
    #else
      self
    #endif
  }

  @ViewBuilder
  func nessaInlineNavigationTitle() -> some View {
    #if os(iOS)
      self.navigationBarTitleDisplayMode(.inline)
    #else
      self
    #endif
  }

  /// A pairing code: capitals, nothing corrected.
  @ViewBuilder
  func nessaCodeInput() -> some View {
    #if os(iOS)
      self.textInputAutocapitalization(.characters).autocorrectionDisabled()
    #else
      self.autocorrectionDisabled()
    #endif
  }

  @ViewBuilder
  func nessaCredentialInput() -> some View {
    #if os(iOS)
      self.textInputAutocapitalization(.never).autocorrectionDisabled()
    #else
      self.autocorrectionDisabled()
    #endif
  }
}
