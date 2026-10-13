import Foundation

/// One validation owner for the generated subset of the published wire schema.
indirect enum GatewayWireRule: Sendable {
  case object([String: GatewayWireRule], required: Set<String>)
  case reference(String)
  case string(minimum: Int, maximum: Int?, allowed: Set<String>?)
  case integer(minimum: UInt64, maximum: UInt64?)
  case array(minimum: Int, maximum: Int?, item: GatewayWireRule)
  case nullable(GatewayWireRule)
  case boolean
  case any

  func validate(_ decoder: Decoder) throws {
    switch self {
    case .object(let fields, let required):
      let values = try decoder.container(keyedBy: GatewayWireKey.self)
      let keys = Set(values.allKeys.map(\.stringValue))
      guard keys.isSubset(of: Set(fields.keys)), required.isSubset(of: keys) else {
        throw NessaGatewayError.invalidFrame
      }
      for key in values.allKeys {
        try fields[key.stringValue]!.validate(values.superDecoder(forKey: key))
      }
    case .reference(let name):
      guard let rule = GatewayWireContract.rules[name] else { throw NessaGatewayError.invalidFrame }
      try rule.validate(decoder)
    case .string(let minimum, let maximum, let allowed):
      let value = try decoder.singleValueContainer().decode(String.self)
      let length = value.unicodeScalars.count
      guard length >= minimum, maximum.map({ length <= $0 }) ?? true,
        allowed.map({ $0.contains(value) }) ?? true
      else { throw NessaGatewayError.invalidFrame }
    case .integer(let minimum, let maximum):
      let value = try decoder.singleValueContainer().decode(UInt64.self)
      guard value >= minimum, maximum.map({ value <= $0 }) ?? true else {
        throw NessaGatewayError.invalidFrame
      }
    case .array(let minimum, let maximum, let item):
      var values = try decoder.unkeyedContainer()
      var count = 0
      while !values.isAtEnd {
        try item.validate(values.superDecoder())
        count += 1
        guard maximum.map({ count <= $0 }) ?? true else { throw NessaGatewayError.invalidFrame }
      }
      guard count >= minimum else { throw NessaGatewayError.invalidFrame }
    case .nullable(let value):
      if !(try decoder.singleValueContainer().decodeNil()) { try value.validate(decoder) }
    case .boolean:
      _ = try decoder.singleValueContainer().decode(Bool.self)
    case .any: break
    }
  }
}

struct GatewayWireKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

func validateGatewayWire(_ decoder: Decoder, named: String) throws {
  try GatewayWireRule.reference(named).validate(decoder)
}

extension CodingUserInfoKey {
  fileprivate static let gatewayWireName = CodingUserInfoKey(rawValue: "gatewayWireName")!
}
private struct GatewayWireValidation: Decodable {
  init(from decoder: Decoder) throws {
    guard let name = decoder.userInfo[.gatewayWireName] as? String else {
      throw NessaGatewayError.invalidFrame
    }
    try validateGatewayWire(decoder, named: name)
  }
}
func validateGatewayWire(_ data: Data, named: String) throws {
  let decoder = JSONDecoder()
  decoder.userInfo[.gatewayWireName] = named
  _ = try decoder.decode(GatewayWireValidation.self, from: data)
}
