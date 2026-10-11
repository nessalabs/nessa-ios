import Testing

@testable import NessaFeatures

@Test func smallPhotoDragReturnsToCurrentCard() {
  #expect(PhotoCardSwipe.direction(distance: 20, velocity: 100, width: 270) == nil)
}

@Test func photoFlickFollowsFinalDirectionAfterReversal() {
  #expect(PhotoCardSwipe.direction(distance: 30, velocity: -800, width: 270) == 1)
  #expect(PhotoCardSwipe.direction(distance: -30, velocity: 800, width: 270) == -1)
}

@Test func deliberatePhotoDragAdvancesWithoutFlick() {
  #expect(PhotoCardSwipe.direction(distance: -100, velocity: 0, width: 270) == 1)
  #expect(PhotoCardSwipe.direction(distance: 100, velocity: 0, width: 270) == -1)
}
