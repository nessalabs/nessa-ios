# Phone synchronization verification — October 12, 2026

Scope: product replacement-view subscriptions, durable display snapshots and connection recovery, not physical retained synchronization. Real checks used a loopback test namespace with Codex/Terra and the image-admission patch in draft gateway PR #779. No credential or personal photo is stored here.

## Application and lifecycle

- Architecture/design-system checks, 87 Swift tests and signed iPhone 17 Pro simulator build pass.
- Scripted peer: cancel-before-ack with inbox; rapid A→B→C latest navigation; asynchronous cancellation with delayed unsubscribe ack; foreign publication rejection; missing-first-publication deadline; old connection cleanup leaving a ready replacement usable; lost registration closing the socket and other feeds. Publication deadlines and a 75-second process watchdog bound verification failures.
- Intentional production reversions failed the right runtime checks: bypassing registration admission caused duplicate watcher refusal; removing latest-navigation fencing admitted obsolete B. Restored source passed.
- Independent Astra medium implementation review passed production ownership/buffering/correlation. Harness review identified unbounded publication waits; these were replaced with deadlines and a missing-publication experiment.
- Updated simulator build starts against the saved live gateway, loads the inbox, opens the image chat and renders the cached waterfall photo and its model reply after a device restart. Camera/microphone interruptions still require physical-device checks.

## Transport timings

Three runs, five sequential tool-free messages each. Measurements use the native Swift adapter and monotonic clock. First-view timing is receipt by the consumer, not a rendered frame. Small samples report medians and observed maxima; they do not establish a production p95.

| Run | Authentication | Provider session creation | Send ack median / max | First view median / max | Completed model reply median / max |
| --- | --- | --- | --- | --- | --- |
| Earlier | 27 ms | 621 ms | 38 / 49 ms | 40 / 51 ms | 2.4 / 4.9 s |
| Before cache/recovery | 11 ms | 274 ms | 37 / 48 ms | 39 / 51 ms | 15.5 / 21.3 s |
| After gateway restart | 18 ms | 1125 ms | 43 / 48 ms | 45 / 50 ms | 4.0 / 5.2 s |

All runs received initial views without polling, delivered inbox events, immediately resubscribed after cancellation and deleted the disposable chat. The second run's model response was substantially slower while send/publication latency stayed similar; provider generation is measured separately from phone transport.

## Image and dictation

The native `--image` runner selects the advertised image-capable model using the app's new-chat path, uploads a generated PNG, sends it, verifies its history reference and matching cached bytes, receives a completed response and deletes the disposable chat. Current response correctly identified the bright blue background, red-orange circle on the left and yellow square on the right. The actual simulator Photos picker path was also exercised with a pre-existing sample waterfall JPEG; the model identified the waterfall and the app renders it after restart.

Dictation tests cover partial replacement, stop/final result, stale callback fencing, permission failure/retry, incomplete result preservation, repeated identical transcripts and mock injection. The live adapter uses Apple Speech and AVAudioEngine; dictation fills a draft and Send submits text. No microphone recognition quality claim is made from simulator/unit tests.

## Durable display and recovery

- Private on-disk recreation preserves snapshots; another endpoint/instance/credential cannot read them. File mode is 0600, the directory is excluded from backup, encoded/decoded data is bounded to 16 MiB, and only 20 recently viewed transcripts are kept. Corrupt, oversized, mismatched and symlinked data is refused. Quota eviction drops derived transcripts rather than declaring retained progress.
- Controlled delayed writes/hydration/connection retirement cover reopening pending snapshots, scope replacement, foreground overlap and obsolete dial cleanup. Removing writer settlement or the pre-hydration generation check separately produced runtime failures in their regression tests; restored source passes.
- Complete inbox absence does not prove deletion because archived chats are omitted. A failed deletion reconciles against an exact read with typed conversation-not-found proof. Confirmed deletion evicts the snapshot and fences late frames in that session.
- The installed iPhone 17 Pro simulator retained an open chat and photo when the isolated gateway was stopped. A cold offline relaunch restored the inbox and opened the saved transcript/photo; New message was disabled. The process launch command completed in 178 ms, which is not a rendered-startup measurement.
- Restarting the same gateway restored the app connection automatically: Reconnecting disappeared and New message became enabled. The post-restart native five-message run received six inbox events, resubscribed immediately and cleaned up its chat. The post-restart generated-image run again returned the correct colors/shapes and matching cached bytes.
- Interrupted send/create regressions hold the old command through disconnect/recovery, start a replacement operation, then deliver the old failure. Recovery releases stale UI locks and the old completion cannot clear the replacement lock. A separate delayed directory test prevents an obsolete dial from writing agents into a new snapshot scope. Removing either safeguard produces runtime failures; restored source passes.
- Astra medium passed the final implementation and the interrupted-command follow-up. This approval covers cache and connection ownership, not the remaining retained-core or command-journal work.

## Remaining gates

Uncertain command identity/receipt recovery, shared retained receiver/checkpoints/native enrollment, remote artifact recovery, larger latency sampling and network/revocation experiments remain in PLAN.md. A display snapshot or live subscription cursor is not physical-record progress. Camera/microphone interruptions and physical-device dictation still need device checks.
