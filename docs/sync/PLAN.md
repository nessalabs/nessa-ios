# Phone synchronization

Goal: publish the native app, integrate the gateway sync engine on the phone, measure startup and message delivery, and exercise failure recovery against both scripted peers and the real gateway. A fast live feed alone is not completion of retained synchronization.

## Current evidence

Baseline app committed and pushed to nessalabs/nessa-ios main at a662165. Its 53 tests and iOS build pass. The first synchronization slice replaces the two-second phone polling loop with live inbox and visible-thread subscriptions. The expanded 63-test suite and iOS build pass; scripted lifecycle and live transport experiments are recorded in [RESULTS.md](RESULTS.md). The app does not yet retain a conversation cache or durable command identity. The gateway has separate replacement-view subscriptions and retained physical/catalogue replication. The shared Rust receiver is nessalabs/sync-engine (gateway pin f2a05ef); native enrollment/SQLite consumption lives in nessa-client-core. Its current public composition is a read-only CLI with a protected native connection, not an iOS SDK.

## Work and completion gates

1. Publish the current app. Done: verify remote main matches local baseline and private repository exists.
2. Build typed replacement-view/list feeds with bounded buffering and lifecycle ownership. Done after independent review: wire frames reach the phone on events, with acknowledgement/first-frame races, cancellation before/after registration, rapid navigation, wrong target, terminal refusal and socket failure covered. Actual gateway latency measured separately from model generation; see RESULTS.md. Custom injected repositories without feeds retain a snapshot fallback.
3. Add a scoped private durable phone cache and reconnect/background/foreground coordination. Validate cold/offline startup, interrupted updates, lost response, stale connection fencing, and deletion reconciliation. Preserve uncertain write identity; never silently retry a possibly accepted command with a new identity.
4. Integrate the shared retained-sync core and its catalogue/record checkpoints through a mobile-facing library boundary, including native device enrollment/authority, retained tombstones and artifact recovery. Reuse its validation/checkpoint rules rather than reimplementing them in the UI. A persisted replacement-view cache is not a physical retained checkpoint. Review the required gateway/client-core API slice before editing it.
5. Run scripted fault experiments and real iOS/gateway experiments, record p50/p95 transport/application latency independently of model generation, and fix failures. Include restart during send, network cut/reconnect, duplicate/stale frames, subscription lag, refusal/revocation, cache corruption/quota, deletion while offline, and image recovery. Run app architecture/design/tests and device/simulator builds; commit/push verified slices. Keep the overall goal active until every gate has current evidence.

## Live-feed ordering (first implementation slice)

| State/order | Owner and result |
| --- | --- |
| Subscribe pending, response followed immediately by first event | Transport installs server ID synchronously while decoding response, before resuming caller; first replacement stays in bounded stream |
| Cancel before subscribe response | Retain pending registration identity until response/failure; unsubscribe acknowledged server ID without delivering |
| Rapid replacement requests B then C during A admission | Latest slot version owns admission; wake obsolete waiters so B cannot reopen after C or accumulate behind A |
| Replacement while old registration is pending | Wait for its bounded registration settlement and unsubscribe acknowledgement before admitting the replacement; cancellation tombstones do not cause a permanent replacement refusal |
| Cancel after registration | Retire that local stream and track unsubscribe through its acknowledgement, including asynchronous termination callbacks; replacement waits for cleanup on the same connection generation, late events ignored |
| Full replacement updates burst faster than UI consumes | Keep newest replacement per subscription, bounded to one frame |
| Foreign conversation or malformed cursor | Finish only that stream with typed invalid-frame error; request cleanup |
| Subscription terminal frame | Finish with typed reason; retry only lag/source closure under reconnect policy, never refusal/oversize |
| Socket failure/replacement | Fail pending requests and streams; old connection events cannot mutate new registration |

Review: first-frame installation precedes waiter resumption; stream correlation uses connection-local subscription identity, not conversation title; list/view frames are complete replacement publications, so newest-only buffering is valid. Domain/application own values and ports; the transport adapter owns wire correlation and cleanup. Durable replay and native paired authority stay explicit later gates.
