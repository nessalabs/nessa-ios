import Testing

@testable import NessaFeatures

/// A main lens that cannot focus nearer than 20 cm, with a 70° field of view,
/// zooms so the orb fills the preview from 20 cm instead of from 7 cm.
@Test func orbCameraZoomsFromTheLensClosestSharpDistance() {
  let zoom = OrbCameraZoom.factor(minimumFocusDistance: 200, fieldOfView: 70, maximum: 100)
  #expect(zoom > 2.6 && zoom < 2.8)
}

@Test func orbCameraKeepsZoomWhenItCannotHelp() {
  #expect(OrbCameraZoom.factor(minimumFocusDistance: -1, fieldOfView: 70, maximum: 100) == 1)
  #expect(OrbCameraZoom.factor(minimumFocusDistance: 30, fieldOfView: 70, maximum: 100) == 1)
  #expect(OrbCameraZoom.factor(minimumFocusDistance: 200, fieldOfView: 0, maximum: 100) == 1)
}

@Test func orbCameraZoomStaysWithinTheCeilingAndTheFormat() {
  #expect(OrbCameraZoom.factor(minimumFocusDistance: 1000, fieldOfView: 70, maximum: 100) == 4)
  #expect(OrbCameraZoom.factor(minimumFocusDistance: 200, fieldOfView: 70, maximum: 2) == 2)
}
