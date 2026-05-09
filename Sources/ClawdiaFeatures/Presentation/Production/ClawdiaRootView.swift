import SwiftUI

public struct ClawdiaRootView: View {
    private let store: DevModeStore
    private let runtimeMode: ClawdiaRuntimeMode

    public init(
        store: DevModeStore = DevModeStore(),
        runtimeMode: ClawdiaRuntimeMode = .production
    ) {
        self.store = store
        self.runtimeMode = runtimeMode
    }

    public var body: some View {
        DevModeRootView(
            store: store,
            allowsDevelopment: runtimeMode.allowsDevelopmentSurfaces
        )
    }
}
