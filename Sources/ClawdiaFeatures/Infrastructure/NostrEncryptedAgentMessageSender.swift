import CryptoKit
import CryptoSwift
import Foundation
import Security
import secp256k1

public protocol NostrEntropySource {
    func bytes(count: Int) throws -> Data
}

public struct SystemNostrEntropySource: NostrEntropySource {
    public init() {}

    public func bytes(count: Int) throws -> Data {
        guard count >= 0 else {
            throw NostrCryptoError.invalidByteCount
        }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NostrCryptoError.randomGenerationFailed
        }
        return Data(bytes)
    }
}

public struct NostrAgentKeypair: Equatable, Sendable {
    fileprivate let privateKeyHex: String
    public let publicKeyHex: String

    public init(privateKeyHex: String) throws {
        let privateKeyData = try NostrHex.decode(privateKeyHex, expectedByteCount: 32)
        let signingKey = try secp256k1.Signing.PrivateKey(dataRepresentation: privateKeyData)
        self.privateKeyHex = privateKeyData.nostrHexString
        self.publicKeyHex = Data(signingKey.publicKey.xonly.bytes).nostrHexString
    }
}

public enum NostrCryptoError: Error, Equatable {
    case aadLengthInvalid(Int)
    case conversationKeyLengthInvalid(Int)
    case emptyPlaintext
    case invalidEnvelope
    case invalidByteCount
    case invalidEventID
    case invalidGiftWrap
    case invalidPayload
    case invalidPrivateKey
    case invalidPublicKey
    case invalidRumor
    case invalidRelayTarget
    case invalidSeal
    case invalidSignature
    case invalidSignatureInput
    case nonceLengthInvalid(Int)
    case plaintextTooLarge(Int)
    case randomGenerationFailed
    case sharedSecretComputationFailed
    case utf8EncodingFailed
    case wrapperKeyGenerationFailed
}

public struct NostrNIP44Cipher {
    private let entropy: any NostrEntropySource

    public init(entropy: any NostrEntropySource = SystemNostrEntropySource()) {
        self.entropy = entropy
    }

    public func conversationKey(privateKeyHex: String, publicKeyHex: String) throws -> Data {
        let privateKeyBytes = try NostrHex.decode(privateKeyHex, expectedByteCount: 32)
        let publicKeyBytes = try NostrHex.decode(publicKeyHex, expectedByteCount: 32)
        let compressedPublicKey = Data([2]) + publicKeyBytes

        var publicKey = secp256k1_pubkey()
        let parsed = compressedPublicKey.withUnsafeBytes { publicKeyPointer in
            secp256k1_ec_pubkey_parse(
                secp256k1.Context.rawRepresentation,
                &publicKey,
                publicKeyPointer.bindMemory(to: UInt8.self).baseAddress!,
                compressedPublicKey.count
            )
        }
        guard parsed == 1 else {
            throw NostrCryptoError.invalidPublicKey
        }

        var sharedSecret = [UInt8](repeating: 0, count: 32)
        var mutablePublicKey = publicKey
        let privateBytes = [UInt8](privateKeyBytes)
        let computed = secp256k1_ecdh(
            secp256k1.Context.rawRepresentation,
            &sharedSecret,
            &mutablePublicKey,
            privateBytes,
            { output, x32, _, _ in
                memcpy(output, x32, 32)
                return 1
            },
            nil
        )
        guard computed != 0 else {
            throw NostrCryptoError.sharedSecretComputationFailed
        }

        let extracted = CryptoKit.HKDF<CryptoKit.SHA256>.extract(
            inputKeyMaterial: CryptoKit.SymmetricKey(data: Data(sharedSecret)),
            salt: Data("nip44-v2".utf8)
        )
        return Data(extracted)
    }

    public func encrypt(plaintext: String, privateKeyHex: String, publicKeyHex: String) throws -> String {
        try encrypt(
            plaintext: plaintext,
            conversationKey: conversationKey(privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex),
            nonce: entropy.bytes(count: 32)
        )
    }

    public func encrypt(plaintext: String, conversationKey: Data, nonce: Data) throws -> String {
        let keys = try messageKeys(conversationKey: conversationKey, nonce: nonce)
        let padded = try pad(plaintext)
        let ciphertext = try CryptoSwift.ChaCha20(key: [UInt8](keys.chachaKey), iv: [UInt8](keys.chachaNonce))
            .encrypt([UInt8](padded))
        let ciphertextData = Data(ciphertext)
        let mac = try hmacAad(key: keys.hmacKey, message: ciphertextData, aad: nonce)
        return (Data([2]) + nonce + ciphertextData + mac).base64EncodedString()
    }

    public func decrypt(payload: String, privateKeyHex: String, publicKeyHex: String) throws -> String {
        try decrypt(
            payload: payload,
            conversationKey: conversationKey(privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex)
        )
    }

    public func decrypt(payload: String, conversationKey: Data) throws -> String {
        guard 132...87_472 ~= payload.count,
              let decoded = Data(base64Encoded: payload),
              99...65_603 ~= decoded.count,
              decoded.first == 2 else {
            throw NostrCryptoError.invalidPayload
        }
        let nonce = decoded[1..<33]
        let ciphertext = decoded[33..<(decoded.count - 32)]
        let mac = decoded[(decoded.count - 32)..<decoded.count]
        let keys = try messageKeys(conversationKey: conversationKey, nonce: nonce)
        let calculatedMac = try hmacAad(key: keys.hmacKey, message: ciphertext, aad: nonce)
        guard calculatedMac.nostrConstantTimeEquals(mac) else {
            throw NostrCryptoError.invalidPayload
        }
        let paddedPlaintext = try CryptoSwift.ChaCha20(key: [UInt8](keys.chachaKey), iv: [UInt8](keys.chachaNonce))
            .decrypt([UInt8](ciphertext))
        return try unpad(Data(paddedPlaintext))
    }

    private func messageKeys(conversationKey: Data, nonce: Data) throws -> NostrMessageKeys {
        guard conversationKey.count == 32 else {
            throw NostrCryptoError.conversationKeyLengthInvalid(conversationKey.count)
        }
        guard nonce.count == 32 else {
            throw NostrCryptoError.nonceLengthInvalid(nonce.count)
        }
        let expanded = CryptoKit.HKDF<CryptoKit.SHA256>.expand(
            pseudoRandomKey: CryptoKit.SymmetricKey(data: conversationKey),
            info: nonce,
            outputByteCount: 76
        ).nostrData
        return NostrMessageKeys(
            chachaKey: expanded[0..<32],
            chachaNonce: expanded[32..<44],
            hmacKey: expanded[44..<76]
        )
    }

    private func pad(_ plaintext: String) throws -> Data {
        guard let unpadded = plaintext.data(using: .utf8) else {
            throw NostrCryptoError.utf8EncodingFailed
        }
        guard !unpadded.isEmpty else {
            throw NostrCryptoError.emptyPlaintext
        }
        guard unpadded.count <= 65_535 else {
            throw NostrCryptoError.plaintextTooLarge(unpadded.count)
        }
        var padded = Data([UInt8(unpadded.count >> 8), UInt8(unpadded.count & 0xff)])
        padded.append(unpadded)
        padded.append(Data(repeating: 0, count: try paddedLength(for: unpadded.count) - unpadded.count))
        return padded
    }

    private func unpad(_ padded: Data) throws -> String {
        guard padded.count >= 2 else {
            throw NostrCryptoError.invalidPayload
        }
        let unpaddedLength = (Int(padded[0]) << 8) | Int(padded[1])
        guard unpaddedLength > 0,
              2 + unpaddedLength <= padded.count,
              padded.count == 2 + (try paddedLength(for: unpaddedLength)) else {
            throw NostrCryptoError.invalidPayload
        }
        let unpadded = padded[2..<(2 + unpaddedLength)]
        guard let plaintext = String(data: unpadded, encoding: .utf8) else {
            throw NostrCryptoError.utf8EncodingFailed
        }
        return plaintext
    }

    private func paddedLength(for unpaddedLength: Int) throws -> Int {
        guard unpaddedLength > 0 else {
            throw NostrCryptoError.emptyPlaintext
        }
        if unpaddedLength <= 32 {
            return 32
        }
        let nextPower = 1 << (Int(floor(log2(Double(unpaddedLength) - 1))) + 1)
        let chunk = nextPower <= 256 ? 32 : nextPower / 8
        return chunk * (Int(floor((Double(unpaddedLength) - 1) / Double(chunk))) + 1)
    }

    private func hmacAad(key: Data, message: Data, aad: Data) throws -> Data {
        guard aad.count == 32 else {
            throw NostrCryptoError.aadLengthInvalid(aad.count)
        }
        return Data(
            CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(
                for: aad + message,
                using: CryptoKit.SymmetricKey(data: key)
            )
        )
    }
}

public struct NostrEncryptedAgentMessageSender: NostrAgentMessageSending {
    private let signingKeypair: NostrAgentKeypair
    private let cipher: NostrNIP44Cipher
    private let entropy: any NostrEntropySource

    public init(
        phonePrivateKeyHex: String,
        entropy: any NostrEntropySource = SystemNostrEntropySource()
    ) throws {
        self.signingKeypair = try NostrAgentKeypair(privateKeyHex: phonePrivateKeyHex)
        self.entropy = entropy
        self.cipher = NostrNIP44Cipher(entropy: entropy)
    }

    public func send(_ event: NostrOutboxEvent) throws -> NostrPreparedRelayEvent {
        guard event.delivery == .requiresEncryptedGiftWrap else {
            throw NostrCryptoError.invalidRelayTarget
        }
        let recipientPublicKey = try recipientPublicKey(from: event)
        let rumor = try NostrWireEvent.unsigned(
            pubkey: signingKeypair.publicKeyHex,
            createdAt: event.draft.createdAt,
            kind: event.draft.kind,
            tags: event.draft.tags,
            content: event.draft.content
        )
        let seal = try sealedEvent(from: rumor, recipientPublicKey: recipientPublicKey)
        let wrapperKeypair = try randomWrapperKeypair()
        let giftWrap = try giftWrappedEvent(from: seal, wrapperKeypair: wrapperKeypair, recipientPublicKey: recipientPublicKey)
        guard let signature = giftWrap.signature else {
            throw NostrCryptoError.invalidSignatureInput
        }

        return NostrPreparedRelayEvent(
            id: giftWrap.id,
            pubkey: giftWrap.pubkey,
            createdAt: giftWrap.createdAt,
            kind: giftWrap.kind,
            tags: giftWrap.tags,
            content: giftWrap.content,
            signature: signature,
            relayURLs: event.relayURLs
        )
    }

    private func recipientPublicKey(from event: NostrOutboxEvent) throws -> String {
        guard event.draft.pubkey.lowercased() == signingKeypair.publicKeyHex else {
            throw NostrCryptoError.invalidRelayTarget
        }
        guard let tag = event.draft.tags.first(where: { $0.first == "p" }),
              tag.count >= 2 else {
            throw NostrCryptoError.invalidRelayTarget
        }
        _ = try NostrHex.decode(tag[1], expectedByteCount: 32)
        return tag[1].lowercased()
    }

    private func sealedEvent(from rumor: NostrWireEvent, recipientPublicKey: String) throws -> NostrWireEvent {
        let rumorJSON = try rumor.jsonString()
        let encryptedRumor = try cipher.encrypt(
            plaintext: rumorJSON,
            privateKeyHex: signingKeypair.privateKeyHex,
            publicKeyHex: recipientPublicKey
        )
        return try NostrWireEvent.signed(
            pubkey: signingKeypair.publicKeyHex,
            privateKeyHex: signingKeypair.privateKeyHex,
            createdAt: shiftedTimestamp(from: rumor.createdAt, by: 1),
            kind: 13,
            tags: [],
            content: encryptedRumor
        )
    }

    private func giftWrappedEvent(
        from seal: NostrWireEvent,
        wrapperKeypair: NostrAgentKeypair,
        recipientPublicKey: String
    ) throws -> NostrWireEvent {
        let sealJSON = try seal.jsonString()
        let encryptedSeal = try cipher.encrypt(
            plaintext: sealJSON,
            privateKeyHex: wrapperKeypair.privateKeyHex,
            publicKeyHex: recipientPublicKey
        )
        return try NostrWireEvent.signed(
            pubkey: wrapperKeypair.publicKeyHex,
            privateKeyHex: wrapperKeypair.privateKeyHex,
            createdAt: shiftedTimestamp(from: seal.createdAt, by: 1),
            kind: 1059,
            tags: [["p", recipientPublicKey]],
            content: encryptedSeal
        )
    }

    private func shiftedTimestamp(from timestamp: Int, by seconds: Int) -> Int {
        max(0, timestamp - seconds)
    }

    private func randomWrapperKeypair() throws -> NostrAgentKeypair {
        for _ in 0..<16 {
            let privateKeyHex = try entropy.bytes(count: 32).nostrHexString
            if let keypair = try? NostrAgentKeypair(privateKeyHex: privateKeyHex) {
                return keypair
            }
        }
        throw NostrCryptoError.wrapperKeyGenerationFailed
    }
}

public struct NostrEncryptedAgentMessageReceiver {
    private let receivingKeypair: NostrAgentKeypair
    private let expectedSenderPublicKeyHex: String?
    private let cipher: NostrNIP44Cipher

    public init(
        phonePrivateKeyHex: String,
        expectedSenderPublicKeyHex: String? = nil
    ) throws {
        self.receivingKeypair = try NostrAgentKeypair(privateKeyHex: phonePrivateKeyHex)
        self.expectedSenderPublicKeyHex = expectedSenderPublicKeyHex?.lowercased()
        self.cipher = NostrNIP44Cipher()
    }

    public func receive(_ event: NostrPreparedRelayEvent) throws -> AgentMessageEnvelope {
        guard event.kind == 1059,
              event.tags.contains(["p", receivingKeypair.publicKeyHex]) else {
            throw NostrCryptoError.invalidGiftWrap
        }

        let giftWrap = NostrWireEvent(prepared: event)
        try giftWrap.validateSigned()

        let sealJSON = try cipher.decrypt(
            payload: event.content,
            privateKeyHex: receivingKeypair.privateKeyHex,
            publicKeyHex: event.pubkey
        )
        let seal = try NostrWireEvent(jsonString: sealJSON)
        guard seal.kind == 13, seal.tags.isEmpty else {
            throw NostrCryptoError.invalidSeal
        }
        try seal.validateSigned()
        if let expectedSenderPublicKeyHex, seal.pubkey != expectedSenderPublicKeyHex {
            throw NostrCryptoError.invalidSeal
        }

        let rumorJSON = try cipher.decrypt(
            payload: seal.content,
            privateKeyHex: receivingKeypair.privateKeyHex,
            publicKeyHex: seal.pubkey
        )
        let rumor = try NostrWireEvent(jsonString: rumorJSON)
        guard rumor.signature == nil, rumor.pubkey == seal.pubkey else {
            throw NostrCryptoError.invalidRumor
        }
        try rumor.validateID()

        guard let contentData = rumor.content.data(using: .utf8) else {
            throw NostrCryptoError.utf8EncodingFailed
        }
        do {
            return try JSONDecoder().decode(AgentMessageEnvelope.self, from: contentData)
        } catch {
            throw NostrCryptoError.invalidEnvelope
        }
    }
}

private struct NostrMessageKeys {
    let chachaKey: Data
    let chachaNonce: Data
    let hmacKey: Data
}

private struct NostrWireEvent: Codable, Equatable {
    let id: String
    let pubkey: String
    let createdAt: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    let signature: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case pubkey
        case createdAt = "created_at"
        case kind
        case tags
        case content
        case signature = "sig"
    }

    init(
        id: String,
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String,
        signature: String?
    ) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
        self.signature = signature
    }

    init(prepared: NostrPreparedRelayEvent) {
        self.init(
            id: prepared.id,
            pubkey: prepared.pubkey,
            createdAt: prepared.createdAt,
            kind: prepared.kind,
            tags: prepared.tags,
            content: prepared.content,
            signature: prepared.signature
        )
    }

    init(jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw NostrCryptoError.utf8EncodingFailed
        }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    static func unsigned(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) throws -> Self {
        let id = try NostrEventIdentity.id(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        return NostrWireEvent(id: id, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content, signature: nil)
    }

    static func signed(
        pubkey: String,
        privateKeyHex: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> Self {
        let id = try NostrEventIdentity.id(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        let signature = try NostrEventIdentity.signature(id: id, privateKeyHex: privateKeyHex)
        return NostrWireEvent(id: id, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content, signature: signature)
    }

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NostrCryptoError.utf8EncodingFailed
        }
        return json
    }

    func validateID() throws {
        let calculatedID = try NostrEventIdentity.id(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        guard calculatedID == id else {
            throw NostrCryptoError.invalidEventID
        }
    }

    func validateSigned() throws {
        try validateID()
        guard let signature else {
            throw NostrCryptoError.invalidSignature
        }
        guard try NostrEventIdentity.isSignatureValid(signature: signature, id: id, publicKeyHex: pubkey) else {
            throw NostrCryptoError.invalidSignature
        }
    }
}

private enum NostrEventIdentity {
    static func id(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) throws -> String {
        let serialized = try serializedEvent(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        return Data(CryptoKit.SHA256.hash(data: Data(serialized.utf8))).nostrHexString
    }

    static func signature(id: String, privateKeyHex: String) throws -> String {
        var message = [UInt8](try NostrHex.decode(id, expectedByteCount: 32))
        let signingKey = try secp256k1.Schnorr.PrivateKey(
            dataRepresentation: try NostrHex.decode(privateKeyHex, expectedByteCount: 32)
        )
        let signature = try signingKey.signature(message: &message, auxiliaryRand: nil)
        return signature.dataRepresentation.nostrHexString
    }

    static func isSignatureValid(signature: String, id: String, publicKeyHex: String) throws -> Bool {
        let signatureData = try NostrHex.decode(signature, expectedByteCount: 64)
        let publicKeyData = try NostrHex.decode(publicKeyHex, expectedByteCount: 32)
        let signature = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: signatureData)
        let publicKey = secp256k1.Schnorr.XonlyKey(dataRepresentation: publicKeyData)
        var message = [UInt8](try NostrHex.decode(id, expectedByteCount: 32))
        return publicKey.isValid(signature, for: &message)
    }

    private static func serializedEvent(
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let tagsData = try encoder.encode(tags)
        let contentData = try encoder.encode(content)
        guard let tagsJSON = String(data: tagsData, encoding: .utf8),
              let contentJSON = String(data: contentData, encoding: .utf8) else {
            throw NostrCryptoError.utf8EncodingFailed
        }
        return "[0,\"\(pubkey.lowercased())\",\(createdAt),\(kind),\(tagsJSON),\(contentJSON)]"
    }
}

private enum NostrHex {
    static func decode(_ hex: String, expectedByteCount: Int? = nil) throws -> Data {
        let normalized = hex.lowercased()
        guard normalized.count.isMultiple(of: 2) else {
            throw NostrCryptoError.invalidSignatureInput
        }
        var data = Data()
        data.reserveCapacity(normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<nextIndex], radix: 16) else {
                throw NostrCryptoError.invalidSignatureInput
            }
            data.append(byte)
            index = nextIndex
        }
        if let expectedByteCount, data.count != expectedByteCount {
            throw NostrCryptoError.invalidSignatureInput
        }
        return data
    }
}

private extension Data {
    var nostrHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    func nostrConstantTimeEquals(_ other: Data) -> Bool {
        guard count == other.count else {
            return false
        }
        return zip(self, other).reduce(UInt8(0)) { partialResult, pair in
            partialResult | (pair.0 ^ pair.1)
        } == 0
    }
}

private extension CryptoKit.SymmetricKey {
    var nostrData: Data {
        withUnsafeBytes { pointer in
            Data(pointer)
        }
    }
}
