# Nessa for iPhone

A native SwiftUI Messages-style client (iOS 18 or later) for the current Nessa product gateway.
Open `App/Nessa.xcodeproj`, select the `Nessa` scheme, and run on an iPhone
simulator. The installed application is named **Nessa**, bundle ID `app.nessa.mobile`.
The app, Swift packages, scheme, and source modules are Nessa-only.

## Current behavior

Open conversations from Agents or a channel, start a conversation on the gateway's
default agent, send text, receive live list and thread updates, and answer pending
permission reviews with the exact offered options. A chat's view lists each waiting review
by its key alone; the phone reads what each one asks with `conversation.permissionReview`
once per review (`ReviewDetails`) and names that key in its answer.
Credentials are stored in this device's Keychain. The interface matches the supplied dark Messages references with glass controls,
blue outgoing bubbles, and gray incoming bubbles.
Debug builds use the injected MockRepository by default; Release builds use the real gateway.
The inherited screens, Nostr transport, and crypto dependencies have been removed.

## Connect to the current backend

See [backend connection details](docs/NESSA_BACKEND.md). In the application,
open Settings (the disc at the sidebar's foot) → Connection, enter the gateway's `/session` WebSocket URL and a
product credential, then Connect. Use the gateway's published endpoint. The
isolated verification gateway uses `ws://127.0.0.1:19743/session`; a physical
phone requires a gateway address reachable from that phone.

## Verify

```sh
./scripts/verify.sh
xcodebuild -project App/Nessa.xcodeproj -scheme Nessa \
  -destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGN_IDENTITY=- build
```

Live-feed fault and image-input experiments are reproducible through
[the native verification runner](verification/sync/README.md). See the
[sync plan](docs/sync/PLAN.md) for the durable-cache and retained-core work that remains.

Run the native adapter's scripted socket lifecycle checks with synthetic data:

```sh
./verification/sync/run-fixtures.sh
```

The runner uses a temporary loopback peer and the fixture-only credential. Real
message and image experiments accept a credential file; see the runner's guide.

Live builds with a prepared phone profile read saved conversation history through
Nessa's native retained-sync engine. The native owner controls progress, access
withdrawal and retained readability. Fresh connected native evidence is required
before sending. A private, bounded legacy cache remains available only when no
phone profile exists; it is never substituted for native history on a damaged,
unavailable or retired profile.

Live chat creation and sends save frozen request identities before dispatch. An
uncertain delivery reappears after restart with Check and Retry actions; reconnect
does not replay it. Confirmation clears only the original unchanged draft. New
intents wait for pending delivery to resolve. Known first-attempt model/photo
refusals retain the draft and release the pending slot; later uncertain refusals
remain pending until stronger confirmation is available.

## Connection settings

Settings show connection status and the connected or saved gateway endpoint,
with a separate **Disconnect** or **Connect** button. Technical pairing controls, **Conversations on this
phone**, and the per-chat **Sync this conversation** action are removed from the
normal UI. Disconnect is a local pause, not remote device revocation.

The intended phone authorization is one read/write approval for the owner's
current and future chats. The current gateway's paired-device contract still
requires per-chat grants; removing those controls does not widen its authority.
The gateway capability is tracked in [issue #811](https://github.com/nessalabs/nessa-agent/issues/811).
Existing native profiles retain their original access rules until that capability
is implemented and explicitly authorized.

## Remaining product work

Audio attachments, push notifications, agent
questions, full transcript pagination and uncertain deletion recovery remain
unfinished. Physical-device execution and broader backlog/failure experiments
are still required. Supply a real gateway credential and reachable product and
native addresses before testing a deployment.

Simulator builds need ad hoc signing for Keychain access; an unsigned build can
compile but fails credential storage with errSecMissingEntitlement (-34018).


## Archive and delete chats

In Agents, swipe a chat left for **Archive** and **Delete**. Each asks in an alert first; Delete permanently deletes that conversation through the gateway. Archived chats are listed under **Settings → Archived chats**, where a swipe unarchives one. Remote notification delivery is not implemented.

## Dependency injection and development

`App/Nessa/NessaApp.swift` is the app composition entry point. `Composition/NessaDependencies.swift` constructs either live adapters or in-memory development adapters. Pages receive a view model from that container; view models receive a `MessagingService`, credential and preferences ports, a snapshot session, and a recovery policy. They never construct infrastructure.

Debug defaults to fake data: twelve chats with scrollable message histories. Send, create, archive, and delete work in memory. Restarting resets development data. Set `NESSA_MODE=live` in the Xcode scheme environment to use your real backend during Debug. Release always selects live. Tests and previews can inject a custom repository with `NessaDependencies.development(repository:)`.

Source layout:

- `Domain/`: chat models, attachment values, and the three-pin policy.
- `Application/`: repository and persistence ports, use cases and input validation.
- `Infrastructure/`: WebSocket repository, attachment HTTP transport, mock repository, Keychain and preferences adapters.
- `Composition/`: dependency wiring and build-mode selection.
- `Presentation/ViewModels/`: observable screen state and async action coordination.
- `Presentation/Pages/`: home, Agents, channel, thread, details, connection and navigation composition.
- `Presentation/Composites/`: feature sections such as headers, permission cards, composer and attachment tray.
- `Presentation/Components/`: leaf controls, bubbles, avatars and platform picker bridges.
- `NessaDesignSystem/`: shared visual tokens, shapes, glass and scroll-dependent header blur.

The plus menu provides Camera, Photos and Add Files. Camera requires a physical iPhone; the simulator reports that it is unavailable. The system photo picker needs no broad photo-library permission. Draft attachments stay until a send succeeds. Photos retain their 5 MiB each / 10 MiB combined limits; general files use a 64 MiB message budget. Native uploads use `attachment.begin` and `attachment.write` pieces; the WebSocket verification path uses a single-use-ticket `PUT /attachments`. Tickets are never logged, and HTTP redirects and cookies are disabled. General files send original digest, media type, size and name in `uploads`. The gateway verifies and places their bytes where the selected agent runs before dispatching its prompt. Both phone journals retain those references for exact send/receipt recovery. File tiles show original metadata without inventing a local path. See gateway [#1149](https://github.com/nessalabs/nessa-agent/issues/1149).

The waveform starts Apple speech recognition and fills the message field with text. Stop dictation, review the text, and tap Send. Live mode requests microphone and speech-recognition permission; development mode injects a mocked transcript. Physical-iPhone microphone verification remains outstanding. The menu has no Clear Draft action.

New phone chats retain the gateway's default model when it supports images, otherwise selecting an image-capable model from the gateway's advertised list. Existing chats retain their model. If no offered model supports images, photo sending reports the refusal and keeps the draft. The local Codex image-input fix is tracked in [gateway PR #779](https://github.com/nessalabs/nessa-agent/pull/779); other gateways need that support before Codex photo sending will work.

## Header behavior

On iOS 26, header and composer controls use `safeAreaBar` with the system’s soft scroll-edge effect. The system supplies the gradual blur as content passes underneath; no custom material rectangle overlays it. Earlier supported versions use a scroll-dependent material fallback. The chat header uses a 44-point avatar and compact 15-point label.

References: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [safeAreaBar](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)), [soft scroll-edge effect](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle/soft). Apple documents the platform behavior; the compact dimensions are Nessa’s design choices, not published Messages internals.

## Agent platform direction

Nessa is the first live integration, not a restriction on agent identity. `AgentProfile` holds provider-independent IDs and display names. `AgentDirectory` handles discovery independently of `MessagingRepository`; the composition root can inject different adapters for each. Conversation-to-agent associations are keyed by conversation ID, so multiple conversations can retain the same agent identity.

The intended MCP bridge is a server-side integration: authenticated agents register a stable profile, then create or publish conversation messages through the gateway. The iPhone remains a client of that gateway; it does not host the MCP server or carry provider credentials. Registration will need authenticated ownership, revocation, capabilities, event delivery, and mappings between external agent IDs and conversation IDs. This describes the planned boundary; the basic standalone MCP service below is not connected to the phone gateway yet. Current development and live Nessa adapters already share the same application ports and UI.


Photos now render as rounded image bubbles and rectangular draft thumbnails, with a looping swipeable stack for multiple photos, a View all gallery, and a full-screen zoomable viewer on iPhone. ImageIO downsamples off the UI thread before sending; a bounded identity-scoped device cache retains live uploads across relaunches. The current gateway exposes upload but no retrieval endpoint, so photos uploaded on another device or removed from the OS cache display an unavailable placeholder.

Long-press text, photo stacks, or file messages for styled Tapback reactions. The chat blurs and dims while the selected message stays highlighted. A wide, horizontally scrollable reaction strip sits above it; the additional-emoji thought-bubble control sits beside it, and Reply, Copy, and More actions sit below. Custom vector pink-heart artwork, native thumbs, and shared HA/!/? lettering match the supplied style. Applied badges sit outside the bubble and reserve clearance from the preceding message. Entry uses a short spring; Reduce Motion uses a fade. Photo stack thumbnails are prepared once off the main actor; the inline stack moves and tilts the front card to reveal the cards beneath, commits selection after the exit animation, and loops in either direction. The full-screen viewer uses native page transitions. Reply adds quoted context to the draft and sends it as text through the current gateway. Reactions persist locally for this gateway/device and use stable message identities; they are not sent to the current Nessa backend. Running agent turns show animated typing dots, respecting Reduce Motion. The custom header preserves UIKit’s interactive back gestures; full-content back swipes yield to inline photo stacks and the full-screen pager.

The independent [basic agent MCP bridge](../nessa-agent-bridge/README.md) implements five chat primitives with SQLite persistence. Its phone transport and push notification delivery remain future integration work; Nessa remains the only live app integration.

### Phone file stress

The `Phone file sending` macOS workflow builds this repository's production
Swift verifier and checks out public gateway source at an exact reviewed commit.
It runs the gateway's default conversation stress plan, then raised PDF/ZIP/text
sending in Chromium and WebKit with background conversations and followers.
The Swift model sends through both the prepared-command journal and durable
outbox, including same-identity retries. The gateway driver checks placed bytes,
original history references, one turn per identity and visible filenames.

To run it locally, build `swift build --product PhoneSyncVerification`, set
`NESSA_PHONE_FILES_VERIFIER` to the absolute `.build/debug/PhoneSyncVerification`
path, then run `node scripts/verify-phone-files-stress.mjs <gateway-root> <evidence-directory>`.
The gateway must have its dependencies, browsers and `nessa`/`nessa-mcp` built.
This fixture drives the phone model and persistence; it does not operate a physical
phone's document picker.

## License

The Nessa iOS source code is licensed under [MIT](LICENSE). The bundled native
client has its own [MIT license](Vendor/NessaNative/LICENSE). Historical football
club logos in Git history are third-party marks, are not covered by either
license, and are no longer included in the current checkout.
