import SwiftUI

extension View {
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
