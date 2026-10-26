import Foundation
import Testing

@testable import NessaFeatures

@Suite struct HomeGreetingTests {
  @Test func eachPartOfTheDayStartsOnItsHour() {
    #expect(HomeGreeting.text(hour: 4) == "Good evening")
    #expect(HomeGreeting.text(hour: 5) == "Good morning")
    #expect(HomeGreeting.text(hour: 11) == "Good morning")
    #expect(HomeGreeting.text(hour: 12) == "Good afternoon")
    #expect(HomeGreeting.text(hour: 16) == "Good afternoon")
    #expect(HomeGreeting.text(hour: 17) == "Good evening")
    #expect(HomeGreeting.text(hour: 23) == "Good evening")
  }

  @Test func aNameFollowsTheGreetingOnlyWhenThereIsOne() {
    #expect(HomeGreeting.text(hour: 9, name: "Saurav") == "Good morning, Saurav")
    #expect(HomeGreeting.text(hour: 9, name: "  ") == "Good morning")
    #expect(HomeGreeting.text(hour: 9, name: nil) == "Good morning")
  }
}
