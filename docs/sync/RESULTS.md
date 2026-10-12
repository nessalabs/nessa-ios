# Phone live-feed verification — October 12, 2026

Scope: product replacement-view subscriptions, not physical retained synchronization. Real checks used a loopback test namespace with Codex/Terra and the image-admission patch in draft gateway PR #779. No credential or personal photo is stored here.

## Application and lifecycle

- Architecture/design-system checks, 63 Swift tests and signed iPhone 17 Pro simulator build pass.
- Scripted peer: cancel-before-ack with inbox; rapid A→B→C latest navigation; asynchronous cancellation with delayed unsubscribe ack; foreign publication rejection; missing-first-publication deadline; lost registration closing the socket and other feeds. Publication deadlines and a 75-second process watchdog bound verification failures.
- Intentional production reversions failed the right runtime checks: bypassing registration admission caused duplicate watcher refusal; removing latest-navigation fencing admitted obsolete B. Restored source passed.
- Independent Astra medium implementation review passed production ownership/buffering/correlation. Harness review identified unbounded publication waits; these were replaced with deadlines and a missing-publication experiment.
- Updated simulator build starts against the saved live gateway, loads the inbox, opens the image chat and renders the cached waterfall photo and its model reply after a device restart. Camera/microphone interruptions still require physical-device checks.

## Transport timings

Two runs, five sequential tool-free messages each. Measurements use the native Swift adapter and monotonic clock. First-view timing is receipt by the consumer, not a rendered frame. Small samples report medians and observed maxima; they do not establish a production p95.

| Run | Authentication | Provider session creation | Send ack median / max | First view median / max | Completed model reply median / max |
| --- | --- | --- | --- | --- | --- |
| Earlier | 27 ms | 621 ms | 38 / 49 ms | 40 / 51 ms | 2.4 / 4.9 s |
| Current | 11 ms | 274 ms | 37 / 48 ms | 39 / 51 ms | 15.5 / 21.3 s |

Both runs received initial views without polling, delivered inbox events, immediately resubscribed after cancellation and deleted the disposable chat. The current run's model response was substantially slower while send/publication latency stayed similar; provider generation is measured separately from phone transport.

## Image and dictation

The native `--image` runner selects the advertised image-capable model using the app's new-chat path, uploads a generated PNG, sends it, verifies its history reference and matching cached bytes, receives a completed response and deletes the disposable chat. Current response correctly identified the bright blue background, red-orange circle on the left and yellow square on the right. The actual simulator Photos picker path was also exercised with a pre-existing sample waterfall JPEG; the model identified the waterfall and the app renders it after restart.

Dictation tests cover partial replacement, stop/final result, stale callback fencing, permission failure/retry, incomplete result preservation, repeated identical transcripts and mock injection. The live adapter uses Apple Speech and AVAudioEngine; dictation fills a draft and Send submits text. No microphone recognition quality claim is made from simulator/unit tests.

## Remaining gates

Private durable conversation cache, cold/offline startup, reconnect/background coordination, uncertain command recovery, shared retained receiver/checkpoints/native enrollment, remote artifact recovery, larger latency sampling and network/revocation/cache-failure experiments remain in PLAN.md. A live subscription cursor is not physical-record progress.
