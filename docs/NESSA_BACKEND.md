# Current Nessa backend integration

Inspected `nessalabs/nessa-agent` at the source revision recorded below. The
production app uses native `URLSessionWebSocketTask`; the former Nostr transport
is not compatible with this gateway and is not used by the new app entry point.

## Wire contract

- Connect to `/session`, not `/health` or `/browser/session`.
- Await `session.challenge`: `minVersion`, `maxVersion`, `nonce`, `expiresAt`.
- Send `session.authenticate` with protocol range 1–1, nonce, opaque credential,
  `client: {id: "nessa-ios"}`, and `surface: {kind: "panel", instance: UUID}`.
  The protocol currently has panel/web/desktop/cli kinds; it has no mobile kind.
  Surface metadata does not grant authorization.
- Requests are `{type:"req", id, method, params}`; responses use `ok` and `payload`.
- Use `conversation.list`, `.create`, `.read`, `.send`, and `.answer`.
- Send includes stable request/execution IDs and empty attachment/file arrays.
  Text is bounded to 8192 UTF-8 bytes. Sent commands are never automatically replayed.
- Read is a bounded projection. Text fragments are combined only when adjacent
  and carrying the same provider message ID. Thoughts are not shown as replies.
- Permission options use the exact gateway IDs and labels. The full reviewed
  JSON is shown before answering. Omitted history and interaction errors are surfaced.

The initial implementation polls `conversation.read` every two seconds while the
thread is visible. The backend also offers `conversation.subscribe` and
`conversation.subscribeList` for a later event-driven implementation.

## Credentials and conversation ownership

The gateway authorizes every command. Use a credential with access to the
intended principal's conversations. `nessa auth token --ttl 12h` can mint a
restricted credential for a new member principal; this starts a separate set of
conversations and does not automatically expose desktop conversations.
For continuity, issue a least-privilege credential for the existing owner through
the authenticated `credential.issue` flow. Do not put an administrative owner
credential into a shipping phone app. Existing device pairing is designed for
read-only conversation replication and is not sufficient for a writable chat
client without additional backend consent/permission work.

This checkout does not mint credentials, provision namespaces, or alter a running
gateway. The application accepts a provided product credential and saves it to
Keychain with `WhenUnlockedThisDeviceOnly` accessibility.

## Reachability

The simulator can reach a Mac gateway at numeric loopback. A physical phone needs
a reachable trusted `wss://HOST/session` endpoint forwarding to the gateway.
Nessa's TypeScript client requires TLS for every non-loopback endpoint, and the
Swift client follows that policy. The default production/development ports are
7420/7421, but configured ports and published endpoints take precedence. Avoid
exposing a plaintext gateway or transmitting a credential through a public tunnel
without TLS. No server network configuration was changed by this work.

## Source references

- `crates/nessa-server/src/server/entrypoint/http.rs`: `/session` route.
- `packages/nessa-client/src/application/product-connect-flow.ts`: handshake.
- `packages/nessa-client/src/application/resolve-options.ts`: TLS policy.
- `protocol/product/v1.json` and `manifest.json`: product RPC contract.
- `packages/nessa-client/src/generated/product.ts`: conversation projections.
- `docs/guides/local-auth.md`: issuance and principal ownership.
- `src-tauri/src/stage_port.rs`: default ports.
14314fe343825630c0be00e9e4d459c5d038e63b


## Verification on this Mac

- Architecture and design-system checks passed.
- Nessa Swift Testing suite passed: pin persistence, gateway scoping, and agent conversation reuse.
- Ad hoc signed iPhone 17 Pro simulator build passed on iOS 26.5.
- Native integration fixture passed authentication, TLS refusal for remote
  plaintext addresses, list/create/read/send, permission answers, UTF-8 limits,
  and disconnect refusal.
- Simulator UI verified connection settings, Keychain persistence, conversation
  list, blue/gray bubbles, multiline composer, and full inline permission review.
- No live gateway responded on default production port 7420 during this work.
  The simulator preview uses synthetic data on local test port 18742.


## Messages reference implementation

The Nessa-only application now has no inherited Nostr, Health, location,
calendar, mock onboarding, or crypto package functionality. Native iOS controls
remain responsible for status-bar and keyboard rendering. The supplied Messages
references guide spacing, fonts, pinned-circle dimensions, bubble backgrounds and
tails, glass controls, the avatar header, and the floating composer. Personal
contacts and SMS content in the screenshots are not copied into the app.

Pinned agents come from `agents.list`, persist per gateway/surface, and pass the
exact agent ID to `conversation.create`. Existing agent/thread associations are
reused; reading a conversation also learns its agent from `runtime.agent` when
available. Long-press exposes Unpin. The circular thread-header avatar opens a
Nessa agent details sheet with an intentionally empty Info section and a pin control.

Simulator verification covered the nine-pin grid, opening a pinned agent,
opening/closing details, and message bubble layout. All nine demonstration agents
and their messages are synthetic test-gateway data.
