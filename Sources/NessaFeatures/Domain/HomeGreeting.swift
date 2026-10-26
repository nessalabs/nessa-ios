import Foundation

/// The line the home screen opens with, from the time of day where the reader is.
public enum HomeGreeting {
  /// Morning from 5:00, afternoon from 12:00, evening from 17:00; the small hours count as
  /// evening, as someone still up at 2:00 is.
  public static func text(hour: Int, name: String? = nil) -> String {
    let part: String
    switch hour {
    case 5..<12: part = "Good morning"
    case 12..<17: part = "Good afternoon"
    default: part = "Good evening"
    }
    guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
    else { return part }
    return "\(part), \(name)"
  }

  public static func text(at date: Date, calendar: Calendar = .current, name: String? = nil)
    -> String
  {
    text(hour: calendar.component(.hour, from: date), name: name)
  }
}
