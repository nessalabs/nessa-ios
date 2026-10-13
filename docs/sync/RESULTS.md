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

The October 12 rerun now injects a temporary disk-backed command journal and submits through `MessagesViewModel.send` with an explicit execution identity. Creation and photo submission left no pending records; the matching history turn retained the exact cached bytes, and the live model again identified all three colors/shapes. The final reviewed product integration passes 119 tests, architecture/design checks and the iOS simulator build. The isolated gateway includes the image-admission patch from open PR #779.

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

Uncertain deletion recovery, terminal reconciliation of earlier uncertain refused commands, shared retained receiver/checkpoints/native enrollment, remote artifact recovery and broader network/revocation experiments remain in PLAN.md. A display snapshot or live subscription cursor is not physical-record progress. Camera/microphone interruptions and physical-device dictation still need device checks.

## Command foundation verification

99 app tests and the iOS build pass for the prepared-command/journal foundation and shared private-file extraction. New tests cover persistence-before-dispatch, cancellation after persistence, lost ACK with exact identity recreation, resolution-save failure, unknown/attempted receipts, foreign correlation, ordered attachment references, serialized delayed saves, scope changes, corruption/size/symlink refusal, quota without eviction, stable nonblocking locks, and CAS across separate stores. Missing documents remain distinct from existing empty journals.

The scripted production socket runner adds lost create and submit ACKs: the peer accepts the command and closes the socket without its response; recreated disk state recovers its receipt, and exact retries yield one creation/turn. Foreign acknowledgment/receipt identities and dispatch across authenticated scope changes are refused. Removing CAS caused stale-write runtime failures; removing scope validation caused the native cross-scope assertion to fail. Both safeguards were restored.

The real gateway exact-command experiment passes: creation retry, one accepted submit, journal recreation before observing confirmation, receipt lookup, same-ID submission retry, exactly one turn, durable resolution and test-chat cleanup. This foundation experiment verifies native primitives and persistence; the subsequent product integration is recorded below. The shared retained core remains incomplete.

## Product command integration verification

The final create/send slice passes 119 tests, architecture/design checks and an iOS simulator build. Astra medium passed after fixes for a permanent first-attempt refusal dead end and an older dispatch entry point bypassing attempt persistence. Intentional reverts of attempt accounting and captured draft revision checks fail runtime regressions; restored source passes. Controlled tests hold Check/Retry across account/connection replacement, preserve replacement action locks, restore frozen reply context, refuse substituted payloads, keep failed pending hydration visible, and separate known acceptance from failed durable resolution.

The scripted peer cases pass through production composition boundaries: recreated view model/socket/disk journal recover lost create/send ACKs, Check makes no new effect, an absent receipt requires explicit exact-ID Retry, and rejected first creation/photo intents release their slot across disk recreation. A later typed refusal after an earlier uncertain attempt preserves the original identity. A corrupt journal leaves authenticated reads available while both presentation and repository writes fail closed. The final installed live simulator starts, opens the existing image chat, renders its cached photo/model reply and exposes Dictate message.

The final loopback run uses disk intent, attempt and resolution writes for twenty sequential messages. Authentication took 19 ms and provider-backed chat creation 644 ms. Nearest-rank samples:

| Measurement | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Durable send acknowledgment | 40.8 ms | 49.8 ms | 50.7 ms |
| First native transcript publication | 42.7 ms | 50.7 ms | 53.7 ms |
| Model completion | 9.77 s | 15.17 s | 16.10 s |

All twenty messages completed, pending storage was empty, immediate resubscription passed, and the disposable chat was deleted. These are twenty native-client observations on one local test gateway, not production or UI-render latency guarantees. The model was slower than the earlier run while acknowledgment/publication remained around 50 ms. The final scripted run passes seventeen fault cases; live generated image submission still returns the correct shapes and matching cached bytes.

## Retained enrollment library verification

[Gateway PR #785](https://github.com/nessalabs/nessa-agent/pull/785) is stacked on #783 at `7212d6c199385002686a3622c71225ec9ded18a3`. The public enrollment facade preserves the existing physical worker and purge policy; tests cover exact-intent rejection before cache open, current issued receiver selection, cancellation/admission-scoped effect capture and last-handle ownership. Actual paired-gateway lifecycle tests preserve independent purge/removal facts through uncertain unlink and worker fault, recover the original durable receipt offline, fence the receiver and prevent a later NoPending from inheriting an earlier transient effect.

185 isolated core tests plus five doctests pass. Exact CI package selection passes 216 core, 2,489 server (11 ignored) and 1,197 SDK (15 ignored) tests; affected Clippy, strict docs, architecture, format/diff and device/simulator no-CLI compile checks pass. Five intentional runtime reverts fail, then restored gates pass. Astra medium round two has no actionable findings. Remote CI is running separately. These checks do not establish C/Swift linking or actual native retained sync in the phone; those remain unfinished.

## Profile coordinator recovery verification

The restored suite now passes 200 tests. The new coordinator verifies durable
creation uncertainty, exact account/claim correlation, receiver-before-terminal
ordering, legacy-snapshot withdrawal and cancellation-independent native drain.
Tests include actual atomic-file publication/readback faults and actual Rust handle
reopen. Five compiling rule reversals fail their intended assertions. Signed
simulator and generic Release device builds pass. Production setup/history wiring
and actual native-enabled gateway experiments remain open; the earlier transport
measurements above are not measurements of this coordinator.

## Application runtime and history verification

The runtime/history application slice passes 213 tests and independent review.
Held credential work, canceled suspension waiters, failed physical drain, changed
registry and preparing/retired profiles cannot hand off an obsolete connection.
The actual native library closes and reopens the same private profile directory.
History tests preserve full observations while rejecting mixed pagination scope,
revision/generation, duplicate or cyclic keys, unavailable transcripts and quota
overflow. Identical facts skip incidental metadata writes; cold restore still
confirms durability. Seven compiling reversals fail assertions and restored gates
pass. These are application-boundary results; production UI composition and
native-enabled app/gateway experiments remain unfinished.

The signed simulator build installs and starts in live mode with the original two
chats present. Its UIKit context menu opens with a 600 ms hold; no custom hold
delay is added. The generic Release device build passes without signing. This
machine lacks the app's development provisioning profile, so the device result
is compile/link evidence, not an install or physical-device execution result.

## Production display wiring verification

227 tests and independent review pass for actual production startup/history wiring.
Public-port tests verify offline history, absent versus corrupt/preparing/retired
profiles, original saved connection, changed manual input before ready, coalesced
mid-read targets, stale bootstrap, foreground restore, returned native failures and
access withdrawal/regrant versus deletion. Cached messages remain readable when
fresh command admission fails. Positive successful/partial reads use the actual
driver's optional-recheck ordering. Aggregate registry change preserves captured
evidence while refusing publication.

Eight compiling reversals fail assertions; restored architecture/design checks and
the full suite pass. Signed simulator and unsigned generic Release builds pass;
the installed live app still shows Web Search and Image and opens the original
image conversation. Explicit pairing controls, native-enabled phone/gateway runs,
backlog and fresh paired timings remain unfinished. Existing latency measurements
above are not results for this new display path.

## Gateway 763574a and attachment previews

The gateway was fetched to frozen main `763574af653194f91076579fac9132cddf1ca527`.
Its disposable product/native listeners run on 19743/19744 with the existing test
surface identity and grants; the original gateway on 18743 is unchanged. Protocol
145, retained-reader 35, SDK deadline 95, server deadline 75 serial, view-clock 1,
and published-schema checks pass. An unchanged logging assertion failed in a
parallel server test batch; isolated and serial reruns pass, so the initial
failure remains recorded rather than being treated as a clean parallel result.

Twenty actual product submissions pass: authentication 17.54 ms, creation 489.47
ms, acknowledgment p50/p95/max 31.14/37.53/38.03 ms, first publication
32.27/38.53/40.24 ms, model completion 1630.86/4200.24/6597.91 ms. Exact command
retry/disk recreation and image upload/history/cache/model recognition also pass;
test conversations are removed. These are transport measurements, not native
retained display or physical-device render timings. Concurrent creates using one
principal reproduce a temporary `conversation_storage_unavailable` refusal;
retrying the exact failed command after the other creation settles succeeds.
Existing principal-reservation regressions expect this contention behavior.

The phone's native package and generated pairing provenance now pin the same
763574a source. All platform libraries and their manifest hashes are verified;
generated Swift API, worker, and FFI headers remain byte-identical. Both old and
updated native readers pass the latest gateway's five-stage paired lifecycle:
first read, offline reopen, restarted gateway, terminal purge recovery, and
epoch refusal with retained partial progress. That fixture does not exercise
the new deadline/grant observation variants; the source update and upstream
deadline/projection tests cover those contracts without claiming this fixture
proved them. No relay fallback is activated in phone composition.

The read-only chat preview now uses the shared message renderer and canonical
message projection, including photos, files, and reply quotes. The signed live
simulator shows the original waterfall photo in the preview; a 600 ms native
hold opens it and tapping it opens the conversation. App architecture/design
checks and 235 tests pass; four compiling setup-facade reversals fail semantic
assertions. Signed simulator and unsigned generic Release compile/link pass.

Public application setup actions preserve exact leased identity, original resumed
profile, explicit selected recovery invitation and displayed approval key, and
captured failure evidence. Their presentation admission/controls and actual
normal-app enrollment remain pending, alongside the broader backlog, artifact,
deletion-failure and physical-device gates.


## Explicit phone setup and per-conversation sharing

The normal live app's isolated simulator now completes Prepare, native claim and
user-approved exact-key approval against product/native ports 19743/19744. The
original simulator and gateway on 18743 are unchanged. Public owner and actual
native receipts both show Active. The native cached catalogue is empty and the
unshared newly created transcript is `notLoaded`; no default chat sharing is
inferred from activation. The product list also omits empty sessions that have
no summary.

The reviewed sharing slice adds an explicit owner picker and a sync action on a
new chat. The owner picker never supplies native history or command readiness.
Requests persist their original owner credential namespace, selected profile,
device and conversation before dispatch. Current grants and historical replies
remain distinct; exact retry cannot undo a later unshare. No reconnect dispatch
or automatic grant is added.

Independent reviews pass; all 272 tests, architecture/design-system gates,
published-schema generation/provenance and formatting pass. Four setup VM, six
sharing action/storage and two sharing VM compiling reversals fail their intended
semantic assertions; restored tests pass. One initial pending-publication probe
exposed a weak test rather than a product failure. The strengthened test checks
after the physical held load settles in the suspended model; the same reversal
now fails at that final assertion.

The signed arm64 simulator build installs and starts, and the unsigned generic
Release iPhone compile/link passes. This is not physical-device execution.
The user approved granting one selected test chat Read access. The UI attempt
instead dismissed the chat before creating a share intent or grant. Admission
had changed the navigation/feed revision before settlement; that ordering and
preservation of uncertain sends were corrected and covered by two more sharing
VM tests. No successful post-share projection or Send/reply is claimed from that
attempt. The user subsequently requested removal of the per-chat controls and
one owner-wide phone authorization instead. That capability is tracked in gateway
issue #811. Artifact integration, deletion recovery in the app, paired timings,
and physical-device experiments remain unfinished.

## Gateway b4d9e90 compatibility

The matching native package and generated product rules now pin gateway main
`b4d9e9083956459fab38bd71b677a910561758b8`. Its ready handshake advertises 67
methods; the older 763574a client accepted at most 65. Two real paired runs of
that old client failed their first refresh with a typed protocol refusal. A
disposable diagnostic gateway with the same b4 implementation advertising only
the prior 65 methods passed all five paired lifecycle stages with the unchanged
old client, identifying the handshake boundary. No production method list or
decoder was relaxed.

The freshly built matching b4 package passes the normal 67-method five-stage
lifecycle and a separate five-stage run carrying actual Note records through
snapshot reload. Generated Swift/worker/FFI interfaces remain byte-identical;
all three platform libraries, signatures and provenance pass verification.
This proves record decoding and lifecycle behavior, not rendering notes in the
phone UI. The existing running gateways were preserved during these fixtures.

The first consolidated app test run reported 294 passes and one recovery failure
in `canceledRecoveryCannotPrepareCacheAfterDelayedRetirement`. The original
failure log is retained. Final recovery correction and restored app/platform
results are recorded separately below; the failed run is not counted as passing.

## Simple connection settings and persistent local pause

Final independent source review passes and all 300 app tests pass. Seven compiled
semantic reversals fail their intended assertions and are restored. These cover
automatic reconnect after a local pause, physical close ownership, accidental
native contact, common native scope mismatch, incorrectly equating catalogue
and transcript streams, protected profile replacement, and purge evidence after
local enrollment was unlinked. The original delayed-retirement recovery test
remains unchanged and passes.

Signed arm64 simulator and unsigned Release iPhone compile/link both pass on the
reviewed source. The isolated Nessa Sync Verification simulator connects to the
verified b4 gateway on 19743/19744. CUA observes only Connected + Disconnect in
Settings, then Disconnected + Connect after the action. A cold process restart
remains disconnected with New message disabled; explicit Connect restores the
saved connection. The technical pairing and Conversations on this phone sections
are absent. No new conversation grant or remote revocation was performed.

The disposable gateway restart preserves its exact identity, pairing receipt,
device key, receiver, access epoch, and existing credential grants. The original
gateway on 18743 remains unchanged. The isolated device has no shared catalogue
entries, so this UI check does not prove cached-message rendering or first Send;
public-port tests cover passive history and the owner-wide capability still
requires the implementation tracked in #811. Physical-iPhone execution remains
outstanding.

## Owner-phone preparation storage foundations

The Application-only original preparation journal and concrete private-file
adapter pass independent review. Fifteen public-port tests cover original
reservation/proof ownership, durable publication, source replacement and
cancellation-independent close; six storage tests cover real cold reopening,
canonical-byte compare-and-swap, concurrent lock contention, corruption,
permissions, quota and symlink refusals. Four Application and three storage
semantic reversals compile and fail their intended assertions, then are restored.
The restored full Swift suite passes 322 tests.

These foundations do not select a profile, grant access, contact the gateway,
or enable Send. Production composition still needs the reviewed native signer,
owner-phone RPC contract and protected product child from #811. Public saved
proof is revalidated against the original native private scope before reuse;
visible bytes after failed durability cannot skip a successful republish.

## Endpoint and unavailable-Send feedback

The final Settings polish shows the actual connected gateway endpoint and a
separate Disconnect button. When disconnected, its saved endpoint follows the
same selection used by Connect, including recovery after a failed replacement.
The final signed simulator build was installed in Nessa Sync Verification;
CUA confirms the endpoint and standalone button without an extra Form-row card.

In a newly created isolated empty Codex chat, entering `Hey` leaves Send disabled
and muted, with the visible and accessible explanation “This chat isn’t available
on this phone.” This makes the existing refusal understandable; it does not fix
owner-wide authorization. No Send or grant was performed. The existing DeviceRead
pairing cannot yet admit that unshared chat. Issue #811 tracks the gateway and
native integration needed to admit fresh empty chats and their first message.

Independent review passes for these changes, and the final full app suite passes
301 tests. Simulator and Release device compilation pass for the endpoint and
Send changes. These checks do not establish owner-wide Read/Write, physical-phone
execution, or the first-Send path.
