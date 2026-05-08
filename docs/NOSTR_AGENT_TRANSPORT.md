# Nostr Agent Transport

This app should treat Nostr as a transport and routing layer, not as the source of truth for user data. Messages, file references, diffs, and image references belong in the phone's local app state first; Nostr relay traffic is only a way for a trusted desktop client or another personal agent product to exchange those events.

## Protocol Notes

- NIP-01 defines the wire event shape: `id`, `pubkey`, `created_at`, `kind`, `tags`, `content`, and `sig`. Clients publish to relays with a WebSocket message shaped like `["EVENT", <event JSON>]`.
- NIP-01 also defines event kind ranges. Kinds `20000..<30000` are ephemeral and are not expected to be stored by relays. That matches the online-only "do not store app data in Nostr" path.
- Secure direct messages should use the NIP-17 model when interoperable DMs are needed. NIP-17 uses NIP-44 encryption and NIP-59 seals/gift wraps, so plaintext app payloads are not relay-published.
- NIP-59 gift wraps put the routeable recipient `p` tag on a `kind:1059` wrapper and keep the inner event encrypted. That is the production shape for desktop-to-phone and phone-to-desktop private traffic.

Primary sources:

- https://github.com/nostr-protocol/nips/blob/master/01.md
- https://github.com/nostr-protocol/nips/blob/master/17.md
- https://github.com/nostr-protocol/nips/blob/master/44.md
- https://github.com/nostr-protocol/nips/blob/master/59.md
- https://github.com/21-DOT-DEV/swift-secp256k1
- https://github.com/nostr-sdk/nostr-sdk-ios

## App Contract

- Domain owns `AgentMessageEnvelope`, a product-neutral payload for chat text plus optional local references for files, diffs, and images.
- Application owns `NostrAgentEventFactory`, which maps a domain envelope into a Nostr outbox draft tagged with the desktop recipient, app namespace, schema, conversation, and area.
- Presentation only calls the store when a user sends a chat message. The store queues the outbox item in phone memory and can hand it to an injected sender that returns a prepared relay event.
- `NostrPreparedRelayEvent` encodes to the NIP-01 `["EVENT", <event>]` client frame while keeping relay URLs local to the phone.
- Infrastructure will own actual relay publication, signing, encryption, and WebSocket handling.

The current implementation queues local outbox drafts, marks them as `requiresEncryptedGiftWrap`, and exposes the sender seam used to store prepared relay events in phone memory. It is not a production relay publisher yet because secure publication still needs audited secp256k1 Schnorr signing, NIP-44 encryption, and NIP-59 gift wrapping.

## Production Path

1. Store phone and desktop identity keys in Keychain or an equivalent secure enclave-backed flow.
2. Add a crypto adapter for NIP-01 event signing and NIP-44 encryption. `nostr-sdk-ios` is the best API fit on paper because it includes NIP-17, NIP-44, NIP-59, and relay primitives, but version `0.3.0` currently fails to compile in this Xcode/SDK setup because its deprecated legacy DM code has a `Data.bytes` ambiguity. Re-check it before adopting; otherwise use `swift-secp256k1`/`P256K` plus a small audited NIP-44 adapter. Do not hand-roll cryptographic primitives.
3. Wrap every agent payload with NIP-17/NIP-59 before publishing to any external relay.
4. Prefer ephemeral custom events for online peer traffic when both devices are connected.
5. If offline delivery is required, use encrypted gift wraps and treat relay persistence as untrusted encrypted transport, not app storage.
6. Persist accepted messages and context references in local phone storage, then add iCloud/iMessage sync as a separate persistence/sync layer.
