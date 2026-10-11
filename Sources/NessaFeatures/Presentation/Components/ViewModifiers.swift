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

  @ViewBuilder
  func nessaCredentialInput() -> some View {
    #if os(iOS)
      self.textInputAutocapitalization(.never).autocorrectionDisabled()
    #else
      self.autocorrectionDisabled()
    #endif
  }
}

extension View {
  @ViewBuilder
  func nessaHideNavigationBar() -> some View {
    #if os(iOS)
      self.toolbar(.hidden, for: .navigationBar)
    #else
      self
    #endif
  }
}
