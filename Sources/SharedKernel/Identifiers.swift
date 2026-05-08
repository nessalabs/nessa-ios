import Foundation

public struct EntityID<Tag>: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct NonEmptyString: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let value: String

    public init(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmed.isEmpty, "NonEmptyString cannot be empty")
        self.value = trimmed
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

public struct UserFacingError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}
