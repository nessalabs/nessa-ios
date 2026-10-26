import Foundation

/// One page of `channel.list`, checked against the gateway's ChannelListResult before it
/// becomes an application value.
struct GatewayChannelPageDTO: Decodable {
  let page: NessaChannelPage
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ChannelListResult")
    page = try NessaChannelPage(from: decoder)
  }
}
