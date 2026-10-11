import Foundation

@main
struct GatewayVerification {
    static func main() async throws {
        let client = NessaGatewayClient()
        do {
            try await client.connect(address: "ws://192.0.2.1/session", credential: "fixture", instance: "test")
            fatalError("Remote plaintext credentials must be refused")
        } catch NessaGatewayError.invalidAddress {}
        try await client.connect(address: "ws://127.0.0.1:18742/session", credential: "fixture", instance: "test")
        let list = try await client.list()
        precondition(list.conversations.count == 1 && list.complete)
        let id = try await client.create()
        let view = try await client.read(id)
        precondition(view.messages.first?.bubbles == ["Hello there", "Second reply"])
        try await client.send("Hello Nessa", conversationID: id)
        let image = DraftAttachment(name: "pixel.png", mimeType: "image/png", data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1kAAAAASUVORK5CYII=")!)
        try await client.send("", attachments: [image], conversationID: id)
        do { try await client.send("File", attachments: [DraftAttachment(name: "notes.txt", mimeType: "text/plain", data: Data("notes".utf8))], conversationID: id); fatalError("General iPhone files must not be linked as gateway paths") }
        catch NessaGatewayError.rejected {}
        do { try await client.send(String(repeating: "é", count: 4097), conversationID: id); fatalError("UTF-8 bound missing") }
        catch NessaGatewayError.rejected {}
        try await client.answer(view.permissions[0], option: view.permissions[0].options[0], conversationID: id)
        await client.disconnect()
        do { _ = try await client.list(); fatalError("Disconnected client must reject requests") }
        catch NessaGatewayError.disconnected {}
        print("Nessa gateway verification passed: handshake, TLS policy, list, create, read, send, image upload, mobile-file rejection, approvals, byte bound, disconnect")
    }
}
