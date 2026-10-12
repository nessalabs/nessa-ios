# Nessa for iPhone

A native SwiftUI Messages-style client (iOS 18 or later) for the current Nessa product gateway.
Open `App/Nessa.xcodeproj`, select the `Nessa` scheme, and run on an iPhone
simulator. The installed application is named **Nessa**, bundle ID `app.nessa.mobile`.
The app, Swift packages, scheme, and source modules are Nessa-only.

## Current behavior

Search and open conversations, start a conversation on the gateway's default
agent, send text, receive live inbox and thread updates, and answer pending
permission reviews with the exact offered options.
Credentials are stored in this device's Keychain. The interface matches the supplied dark Messages references with glass controls,
circular pinned-chat avatars, blue outgoing bubbles, and gray incoming bubbles.
Debug builds use the injected MockRepository by default; Release builds use the real gateway.
The inherited screens, Nostr transport, and crypto dependencies have been removed.

## Connect to the current backend

See [backend connection details](docs/NESSA_BACKEND.md). In the application,
open Messages options → Connection settings, enter the gateway's `/session` WebSocket URL and a
product credential, then Connect. Simulator loopback defaults to port 7420
(production); development normally uses 7421. Prefer the gateway's actual
published endpoint when its port is configured differently.

## Verify

```sh
./scripts/verify.sh
xcodebuild -project App/Nessa.xcodeproj -scheme Nessa \
  -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=- build
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

Live builds retain a private, bounded cache of the inbox, agent metadata and the
20 most recently viewed chats for offline display. Cache identities include the
gateway, instance and credential fingerprint. Reconnecting replaces live feeds;
offline display does not enable sending or establish retained-sync checkpoints.

Live chat creation and sends save frozen request identities before dispatch. An
uncertain delivery reappears after restart with Check and Retry actions; reconnect
does not replay it. Confirmation clears only the original unchanged draft. New
intents wait for pending delivery to resolve. Known first-attempt model/photo
refusals retain the draft and release the pending slot; later uncertain refusals
remain pending until stronger confirmation is available.

## Remaining product work

General mobile file uploads, audio, push notifications, full offline history, device pairing UI,
agent questions, full transcript pagination, uncertain deletion recovery, and
shared retained-sync integration are not yet implemented in the new surface. Live gateway credential and network
setup must be supplied before testing against a real Nessa deployment.

Simulator builds need ad hoc signing for Keychain access; an unsigned build can
compile but fails credential storage with errSecMissingEntitlement (-34018).


## Pin chats and open details

Pin up to three existing chats. Tap **Edit** to pin or unpin a chat, or long-press a conversation and choose **Pin**. Pinned chats appear as circular avatars above the inbox; there is no agent catalog or agent picker. Long-press a pinned chat for a conversation preview, Unpin, Mark as Unread, Hide Alerts, and Delete. Delete confirms before permanently deleting that conversation through the gateway. Unread and mute preferences are saved on this device; remote notification delivery is not implemented.

## Dependency injection and development

`App/Nessa/NessaApp.swift` is the app composition entry point. `Composition/NessaDependencies.swift` constructs either live adapters or in-memory development adapters. Pages receive a view model from that container; view models receive a `MessagingService`, credential and preferences ports, a snapshot session, and a recovery policy. They never construct infrastructure.

Debug defaults to fake data: twelve chats with scrollable message histories. Send, create, pin, preview, and delete work in memory. Restarting resets development data. Set `NESSA_MODE=live` in the Xcode scheme environment to use your real backend during Debug. Release always selects live. Tests and previews can inject a custom repository with `NessaDependencies.development(repository:)`.

Source layout:

- `Domain/`: chat models, attachment values, and the three-pin policy.
- `Application/`: repository and persistence ports, use cases and input validation.
- `Infrastructure/`: WebSocket repository, attachment HTTP transport, mock repository, Keychain and preferences adapters.
- `Composition/`: dependency wiring and build-mode selection.
- `Presentation/ViewModels/`: observable screen state and async action coordination.
- `Presentation/Pages/`: inbox, thread, details, connection and navigation composition.
- `Presentation/Composites/`: feature sections such as headers, pinned chats, preview, composer and attachment tray.
- `Presentation/Components/`: leaf controls, bubbles, avatars and platform picker bridges.
- `NessaDesignSystem/`: shared visual tokens, shapes, glass and scroll-dependent header blur.

The plus menu provides Camera, Photos and Add Files. Camera requires a physical iPhone; the simulator reports that it is unavailable. The system photo picker needs no broad photo-library permission. Draft attachments stay until a send succeeds. Live image sending uses `attachment.begin` and a single-use-ticket `PUT /attachments`; tickets are never logged, and redirects and cookies are disabled. General files can be selected and sent in mock mode. The current live protocol only links general files already on the gateway machine, so it cannot send general iPhone files yet; the app reports this and retains the draft.

## Header behavior

On iOS 26, header and composer controls use `safeAreaBar` with the system’s soft scroll-edge effect. The system supplies the gradual blur as content passes underneath; no custom material rectangle overlays it. Earlier supported versions use a scroll-dependent material fallback. The chat header uses a 44-point avatar and compact 15-point label. Inbox rows are 84 points tall, providing a little extra vertical space.

References: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [safeAreaBar](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)), [soft scroll-edge effect](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle/soft). Apple documents the platform behavior; the compact dimensions are Nessa’s design choices, not published Messages internals.

## Agent platform direction

Nessa is the first live integration, not a restriction on agent identity. `AgentProfile` holds provider-independent IDs and display names. `AgentDirectory` handles discovery independently of `MessagingRepository`; the composition root can inject different adapters for each. Conversation-to-agent associations are keyed by conversation ID, so multiple conversations can retain the same agent identity.

The intended MCP bridge is a server-side integration: authenticated agents register a stable profile, then create or publish conversation messages through the gateway. The iPhone remains a client of that gateway; it does not host the MCP server or carry provider credentials. Registration will need authenticated ownership, revocation, capabilities, event delivery, and mappings between external agent IDs and conversation IDs. This describes the planned boundary; the basic standalone MCP service below is not connected to the phone gateway yet. Current development and live Nessa adapters already share the same application ports and UI.


Photos now render as rounded image bubbles and rectangular draft thumbnails, with a looping swipeable stack for multiple photos, a View all gallery, and a full-screen zoomable viewer on iPhone. ImageIO downsamples off the UI thread before sending; a bounded identity-scoped device cache retains live uploads across relaunches. The current gateway exposes upload but no retrieval endpoint, so photos uploaded on another device or removed from the OS cache display an unavailable placeholder.

Long-press text, photo stacks, or file messages for styled Tapback reactions. The chat blurs and dims while the selected message stays highlighted. A wide, horizontally scrollable reaction strip sits above it; the additional-emoji thought-bubble control sits beside it, and Reply, Copy, and More actions sit below. Custom vector pink-heart artwork, native thumbs, and shared HA/!/? lettering match the supplied style. Applied badges sit outside the bubble and reserve clearance from the preceding message. Entry uses a short spring; Reduce Motion uses a fade. Photo stack thumbnails are prepared once off the main actor; the inline stack moves and tilts the front card to reveal the cards beneath, commits selection after the exit animation, and loops in either direction. The full-screen viewer uses native page transitions. Reply adds quoted context to the draft and sends it as text through the current gateway. Reactions persist locally for this gateway/device and use stable message identities; they are not sent to the current Nessa backend. Running agent turns show animated typing dots, respecting Reduce Motion. The custom header preserves UIKit’s interactive back gestures; full-content back swipes yield to inline photo stacks and the full-screen pager.

The independent [basic agent MCP bridge](../nessa-agent-bridge/README.md) implements five chat primitives with SQLite persistence. Its phone transport and push notification delivery remain future integration work; Nessa remains the only live app integration.
