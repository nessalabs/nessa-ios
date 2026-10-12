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
- Send includes stable request/execution IDs and uploaded image references.
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

October 11 compatibility check: fetched upstream `main` at
`fde8f6c89e96bb20bd69a2396c0c87e7a6f7c0aa`. Authentication request/challenge,
conversation list/create/read/send/answer/delete parameters, and image-upload
contracts remain unchanged from the previously inspected revision. The gateway
adds published conversation artifacts that this app does not yet consume. No TCP
gateway was listening on this Mac, including ports 7420/7421, so this is source
compatibility evidence, not a successful live connection. Debug can use the live
adapter with `NESSA_MODE=live`; an endpoint and suitable product credential are
still required for an authenticated test.

Later on October 11, the same upstream revision was built locally with an
isolated Rust installation and private test namespace. The actual gateway now
listens on `ws://127.0.0.1:18743/session`. Its configured Codex ACP harness is the
repository-pinned version. Using the iOS app's `NessaGatewayClient` compiled into
a native Swift executable, the non-admin panel credential successfully completed
authentication, conversation listing, agent discovery, conversation creation,
send, read, and a completed turn with an agent reply. This is real gateway and
provider evidence, not the synthetic fixture. Uploads and permission approval
were not retested against this live instance.

The app remains in development mock mode. To test in the simulator, launch Debug
with `NESSA_MODE=live`, use Connection settings with the endpoint above, and paste
the test panel credential from the private file (never include it in chat/logs):
`/Users/nessa/Documents/Codex/2026-10-09/create-an-image-of-4/work/gateway-live-data/dev/instances/ios-check/auth/surfaces/nessa-panel.token`.
The gateway's data and source live under this chat's `work/` directory and do not
use an existing production namespace. A physical iPhone needs a reachable TLS
endpoint; this numeric-loopback URL is for the simulator on this Mac.

The simulator was subsequently launched in live mode and authenticated with that
panel credential. Its inbox displayed the real test conversation, and opening it
showed the actual agent reply “Gateway connection confirmed.” Connection address
is persisted and the credential goes through the normal device Keychain store.
Debug supports paired `NESSA_TEST_GATEWAY_URL` / `NESSA_TEST_CREDENTIAL` launch
values only when `NESSA_MODE=live`; Release ignores this test-launch environment.
Do not log or commit the credential. The configured agent is Codex; this is an
isolated source-built Nessa gateway rather than a pre-existing personal namespace.

## Local Web search adapter fix

The live Codex turn asking which model was running failed in the gateway SDK's
`codex_acp/tools/wire.rs`, with `Protocol("tool input changed")`. Pinned
codex-acp 1.12.0's `createWebSearchRawInput` sends the Web search identity first,
then supplies query/action details on completion. The original adapter compared
the entire completion input against the initial input as if it were an immutable
command approval.

The isolated gateway is patched to accept query/action changes only for a
completed, unnamed, non-MCP Web search observation with the same tool ID, type,
and other stable fields. It does not replace the input retained for permission
reviews; those comparisons remain strict. Running updates, named commands, MCP
calls, changed identities/types, and extra stable fields remain rejected.

| Event | Result |
| --- | --- |
| Initial Web search observation | Retain original input and charge its bytes |
| Matching completion supplies query/action | Accept observation; retained review input unchanged |
| Duplicate matching completion | Accept; no additional retained-input charge |
| Changed identity, command/MCP input, or incomplete update | Reject |
| Permission request changes original input | Reject |

The regression reproduced before the fix. The SDK suite passed 1,185 tests and
had one environment failure (Node missing from PATH); that fixture passed when
rerun with Node available. Fifteen tests were ignored. Clippy with `-D warnings`
and the gateway build pass. A live test then recorded both Running and Completed
Web search observations and a completed agent reply. The simulator was relaunched
in live mode using its saved Keychain credential after the patched gateway restart.

The gateway fix and canonical lifecycle/verification documentation were merged
upstream in [PR #774](https://github.com/nessalabs/nessa-agent/pull/774), commit
`bed880894074549c141adf24310f7f413b3dee6a`, after all cross-platform CI passed.
Fresh-main validation passed 1,187 SDK unit tests (15 ignored), all-target Clippy,
formatting, and SDK documentation checks. Both automated documentation findings
were addressed and a fresh independent review passed. Issue #773 closed on merge.
Project-board updates were unavailable because the CLI token lacked project scope.

## Deletion responsiveness

A disposable live Codex conversation was created, sent one tool-free text turn,
and deleted after the turn completed. The native Swift client's measured
`conversation.delete` round trip was **4,288 ms** on localhost. This is one
sample, not a latency distribution. The gateway's deletion service replies only
after shutdown, provider-session erasure, audit recording, and local-history/upload
cleanup; per-step timings were not collected.

The phone now hides pending deletions from its visible inbox and pinned grid
before awaiting that acknowledgement. Bulk deletion hides all chosen rows before
the first request finishes. Pending state is transient, scoped to the connection,
and does not prematurely erase preferences/history. Success finalizes cleanup;
failure refreshes the authoritative list, preserves a confirmed deletion, or
restores a still-present chat and shows the error. Stale reads and list snapshots
cannot expose pending rows. This is a pending-command projection, not an
implementation of the sync-engine receiver protocol. Direct replication/offline
sync remains unwired in the phone. The live adapter now follows bounded product
replacement-view/list subscriptions; durable retained progress is a separate
integration described in [the sync plan](sync/PLAN.md).

The agent prompt section now appears only for a nonempty prompt supplied by the
selected agent's profile. The current gateway `AgentOption` contract exposes
identity/model choices, not a prompt, so live profiles show no prompt placeholder.

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

### Replies and new-chat readiness

Reply context still travels as quoted text through the current `conversation.send` contract. The application saves only the source message ID for each acknowledged execution, scoped by gateway and device instance; the UI separates that context from the displayed reply body. These links are local until the gateway exposes structured reply metadata. Unambiguous replies sent by the older UI can also be reconstructed from loaded history. Text, photos, and files share the same reply-thread model.

The native send adapter now returns its lowercase execution ID, matching the gateway's UUID serialization. A live adapter/view-model check confirmed the receipt identity, exact reply parent, clean body, and reply count. Its disposable conversation was deleted after verification.

`conversation.create` waits for the configured provider session to attach and reach readiness. One local measurement was 1,390 ms for creation, 2 ms for the empty read, and under 1 ms for the list request. The app now seeds an empty view after acknowledgement and navigates without waiting for that read or list; the inbox refresh runs separately. The compose button shows progress while creation is pending. New Chat creates a separate conversation/session but does not send a prompt.


## Dictation and phone image input

The composer menu contains Camera, Photos and Add Files. The waveform uses an injected Apple `SFSpeechRecognizer` / microphone adapter in live mode and a speech mock in development. Partial results replace the draft; stopping waits for final recognition, with an explicit incomplete/error outcome if it cannot finish. The transcript is sent as ordinary text only when Send is pressed. Recording is canceled on dismissal/backgrounding; repeated identical transcripts use delivery revisions. Apple permissions and physical-device interruptions still need a device check.

New phone conversations consume the gateway's advertised model list, retaining an image-capable default or selecting an offered vision model for the chosen agent. With one configured agent, the default-chat path also applies that choice. Multiple agents with no selection retain the gateway's default because the directory does not identify the default agent. Existing conversations retain their model.

October 12 image verification found two gateway refusals: the Codex binding offered text-only input, and the OpenAI model catalog omitted image admission limits. The isolated test gateway now runs the fix in [PR #779](https://github.com/nessalabs/nessa-agent/pull/779), based on upstream `a2084194743e41cd9b0ffd62c6a7cb93494cc77f`. Terra publishes a conservative PNG/JPEG profile (5,000,000 encoded bytes / 3,750,000 raw bytes, 2048 pixels per edge). The real Swift client selected Terra, uploaded a synthetic photo, sent/read its reference, loaded its local image cache, and received the correct blue-background/red-circle/yellow-square description from the model. No personal image was sent. The full SDK suite, Clippy, docs, gateway build and independent review passed. The gateway change is a draft PR, not yet merged upstream.

The simulator Photos picker subsequently recovered. A pre-existing simulator sample waterfall photo was selected, displayed in the draft tray, sent as an image-only message through the live app, and rendered as a rounded image attachment. The real model replied “What would you like me to do with this waterfall image?”, confirming the actual picker/preparation/upload/reference/read/render path. Synthetic import via `simctl addmedia` remained stalled and was canceled; the native-client synthetic PNG check and app sample JPEG check both succeeded.
