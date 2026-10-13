# Native receiver in the phone

The gateway bridge is published in
[#789](https://github.com/nessalabs/nessa-agent/pull/789). The native API at
`82d143804a8b923840fa3f9608dc4b01453dcbae` passed independent review of its passive
correlation/cursor and admitted capture extension, following the reviewed bridge
at `69499fe7890f4d2ee6f2d358e3db4a2a9bf76347`. Its library
and Swift worker have run against paired records, offline reopen, restart and
revocation; a release library also runs in a disposable simulator app. These
checks establish the library boundary. Production startup/history wiring is
recorded below; explicit setup and native-enabled phone experiments remain open.

## Ownership and delivery

Link the reviewed `nessa-device-client` exports into one native Swift adapter.
The shared core remains the owner of enrollment, current binding validation,
record/catalogue progress, fold, tombstones, purge and artifact transfer. Swift
maps immutable publications into existing presentation values. It does not save
another physical checkpoint or derive one from a live-feed cursor/view revision.

The existing product socket remains the command/live-view transport, with its
durable create/send journal. Native records supply cold/offline history and
deletion evidence. A product list's absence remains insufficient deletion proof.
Live view publications may improve responsiveness without becoming retained facts.

One immutable profile ID is minted when setup begins and persisted before pairing.
Its private native directory and credential-store reference outlive callbacks.
Endpoints select transport only. No native port offset, record origin, receiver,
epoch or grant is inferred from the WebSocket URL or chat title. Changing the
profile fences publications and drains the old native worker before replacement.

The static release archives are too large to vendor individually into ordinary
GitHub Git storage. The same release exports also produce roughly 5.6 MiB Apple
dylibs. Evaluate packaging them as signed/embedded framework slices, with generated
headers and Swift declarations from the same reviewed revision. A local package
must build without an absolute path into this task's work directory. Verify the
actual distributed binaries through linking and simulator execution; a successful
host static-library probe is not evidence for a new dynamic packaging layout.

## Setup and cross-transport identity

The product ready frame already reports authenticated gateway, principal,
organization, membership, credential and audience identities. The phone captures
the complete ready snapshot through `GatewayReadyDTO` and publishes it only for
the exact current `GatewayConnectionLease`. Correlate that authenticated identity
with native setup; strings in UI configuration are not authenticated identity.

Native disclosure contains audience and gateway grant/resource/organization. It
intentionally omits the owner principal and membership. In local composition,
the ready gateway/audience and the disclosed grant resource identify the gateway,
not the human principal. Comparing only organization and host would mix accounts.

Setup must capture an invitation created/read by the authenticated product owner
through existing `pairing.create/status/approve` operations, correlate the native
attempt with that exact invitation and claimed key, and persist its binding to
the original authenticated principal/membership. Owner status includes exact
invitation/consent/generation/class, claimed key, credential and receiver. The
native API exports phase/credential/receiver/disclosed scope and exact public
invitation/attempt/consent/generation/expiry/class correlation. Claimed-key
correlation is exported through its admitted local owner. Do not reconstruct these selectors in
Swift or treat a manually supplied code as proof of a product-owner relationship.

Only the existing gateway policy decides whether a credential may manage pairing
or write messages. If pairing management is unavailable, show the required setup
step; do not replace the credential or escalate its grants. Approval is explicit
in the setup flow. Scripted/local experiments use disposable enrollment records.

On reopening, compare the captured profile identity with the authenticated ready
identity before publishing across transports. Native reads still ask the existing
fresh status/binding/read owner. Native terminal status retires the product socket,
live feeds and commands, fences escaped historical snapshots, and clears derived
publications. Failed/offline status does not authorize purge. A completed purge
and uncertain credential removal remain separate facts; durable receipt recovery
uses the prior captured receiver independently.

## Application seams

- An application-owned native session/retained-reading port returns Nessa-owned
  immutable status, catalogue, transcript and purge publications. Infrastructure
  maps generated foreign objects and dispatches blocking work through the reviewed
  worker. Tests substitute that one boundary, not a separate fold or permission rule.
- Profile/enrollment coordination owns one generation and actual close task.
  Cancellation does not free admitted work or release a private directory early.
- The repository/composition selects native saved history and the authenticated
  product transport together. A native receiver is required for retained mode;
  a product display-cache fallback does not claim successful retained sync.
- Messages hydrate matching native history before dialing. Existing agent metadata,
  preferences, replies and fast live views remain presentation data. Purge/refusal
  notices reach the view model even if the affected chat is not open.
- The command transport checks the matching current profile/ready/native binding
  before handoff. Native refusal preserves frozen pending intent and delivery
  uncertainty; it does not silently retry with another identity.

## Ordering and evidence

| Input/order | Required behavior and direct evidence |
| --- | --- |
| Fresh setup, invitation created, native claim, owner approval | Exact invitation/key correlation; actual gateway issues one receiver; phone reads records |
| Reopen offline with issued state | Native catalogue/progress/transcript from disk, no network; product cache cannot advance progress |
| Credential/profile changed before hydration or late publication | Retire old generation and close/drain before reuse; no old user data in replacement |
| Product credential changed, same profile ID, startup offline | Fence the old binding before saved hydration; do not wait for a later ready mismatch to hide the previous account |
| Same organization/gateway, different product principal or membership | Reject cross-transport publication/dispatch before effects; no host-derived authority |
| Native Pending/Claimed/Staging/outer failure | Preserve actual phase/recovery evidence; no invented Active and no generic-failure purge |
| Native Active then product ready mismatch | Retire only the newly owned socket; saved data stays scoped and historical |
| Read in flight then background/close/caller cancellation | Stop/wake actual owner, retain worker/private scope through physical completion; no replacement race |
| Terminal status while live view/photo/command result is pending | Purge result independent of removal; retire feeds/commands and reject late old-generation publications |
| Revoke, reopen after credential is gone | Recover original durable purge receipt by captured receiver; old display caches cannot resurrect history |
| Lost delete answer, offline, recreate app | Persist exact deletion target; remove optimistically, keep uncertainty; resolve only with exact tombstone/not-found proof |
| Catalogue page changes generation/scope between pages | Restart/reject mixed publication; each immutable page has its own actual core progress |
| Artifact partly transferred then interrupted/reopened/revoked | Existing file/range/digest owner resumes or refuses; private bytes and withdrawal accounting survive |
| Corrupt/quota/private locked state or projection too large | Typed error, no false NotLoaded and no fabricated checkpoint or legacy-authority fallback |
| New distributed framework | Matching generated ABI/platform metadata, device link, actual simulator use and off-UI close/reopen |

Implementation proceeds in reviewed slices: distribution and injected adapter;
profile/enrollment/identity coordination; retained repository and lifecycle;
shared artifact exposure and durable deletion; then actual Nessa/gateway failure
experiments and latency measurements. All remain part of the full sync goal.

## Design review decisions for the first slice

The independent one-round review found coherent ownership and required concrete
distribution, factory and mapping contracts before implementation. These are the
accepted constraints; they do not claim that the slice is implemented.

Distribute an arm64 dynamic XCFramework inside `Vendor/NessaNative`, with iOS 18,
iOS Simulator 18 and macOS 15 slices. Its C module/framework is
`nessa_device_clientFFI`; the local Swift package exports `NessaNative`, containing
the generated declarations and the production worker. The app package uses a
relative local dependency. Intel/simulator x86_64 binaries are not supplied by
this first package. The developer update script accepts an explicit frozen gateway
checkout/revision, invokes its existing build/generation owner, and wraps those
same release dylibs in frameworks. It does not generate an alternate ABI.

Use the install name
`@rpath/nessa_device_clientFFI.framework/nessa_device_clientFFI`. Record the source
revision, Cargo lock digest, generated-source/header/worker digests and each
distributed slice's digest. Inspect linked runtime dependencies for build-directory
paths. Xcode/SPM owns embedding and final app signing; package creation signs its
local frameworks as needed for local verification. The app verification gate must
inspect the embedded framework and actual signature, link a device build, and
launch Nessa in the simulator. A fresh app-checkout build must not require a path
into the gateway checkout. This follows Apple's
[binary Swift-package distribution](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)
and [XCFramework packaging](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
contracts; successful embedding remains an experiment to run.

The application factory receives an immutable explicit descriptor: trusted absolute
private root, existing relative private directory, and numeric native socket
address. Infrastructure prepares private directories through an injected boundary;
the native opener remains the validation owner. It does not resolve a hostname.
Production opening waits for the persisted profile coordinator; disposable
verification supplies its own explicit descriptor, without changing the user's
live profile or inventing a native port from WebSocket configuration.

All blocking getters and translation run off UI as well as the native method:
`NativeTranscript.view_json()` serializes synchronously after `transcript()`
returns. The adapter must keep the foreign object on its worker for serialization
and decode the resulting passive view off UI. Its application publications retain
exact UInt64 progress, all six scope fields, and the full immutable initial
status/selection/read/withdrawal/recheck evidence. Completion capture, original
enrollment failure, purge and private removal/publication failure remain distinct;
neither an Active Boolean nor one success/error can substitute for them.

Before enabling retained publication, add the existing owner's claimed-key
correlation API and persist the product principal/membership binding. Product
bearer and native issued credential IDs are distinct; their enrollment relationship
is checked rather than requiring equal credential IDs. Native terminal evidence
must durably suppress derived snapshots/preferences and fence late writers, not
merely clear view-model arrays. Artifact transfer remains unavailable until its
existing crate-private owner is exported. Durable deletion keeps exact
request/target/profile evidence and does not infer removal from list absence.

## Distribution implementation evidence

`Vendor/NessaNative` packages the reviewed native API above as three arm64 dynamic
framework slices, about 18 MB total, with matching generated declarations and
worker. `SOURCE.json` records the revision, Cargo lock digest, distributed bytes
and symlinks. The update tool calls the gateway's existing compilation/generation
owner, refuses an unmatched/dirty source or an existing output, and publishes only
after its source is still frozen. Publication reserves the destination exclusively
after compilation, preserving a competing producer's output. The checker requires
the complete file/symlink inventory and rejects entries outside the package root;
the vendored package root must itself be a directory, not an external symlink.
It validates recorded content, not a cryptographic source-trust policy. Seven real
filesystem regressions pass, and removing either the inventory or exclusive
publication protection makes those regressions fail.

The app's relative package dependency builds without gateway-worktree paths.
All 126 app tests pass; the actual-library test opens a private scope,
captures unreachable status off UI and restores an exact UInt64-max cursor,
receives native NoCredential, receives the worker's post-close refusal, and
reopens the same scope after physical drain. Removing close or making the probe
a no-op fails it; changed distributed header bytes fail the provenance check.
Nessa's simulator and device builds link the framework. The normally signed
simulator app passes the same explicit disposable-scope runtime probe and restores
its existing connection and both saved chats. Nested signatures verify.

Two verification mistakes were repaired rather than treated as successful runs:
the first probe expected a native closed error instead of the worker's earlier
typed refusal; the first unsigned simulator launch lacked the normal simulated
application entitlement and therefore could not read the existing Keychain item.
Normal project signing restores that access. Simulator reinstall also changed the
data-container path, so a previously absolute disposable path was correctly
refused. The runtime check supplies a new current-container path after install.
Production profile identity must persist a relative directory and resolve the
current sandbox root on each launch, not retain a container UUID as identity.

This completes packaging/runtime evidence only. Application factory/result mapping
is described below. Production enrollment/profile coordination, retained repository,
artifacts, durable deletion and performance/failure experiments remain open.
The debug probe uses a disposable loopback endpoint for unreachable status;
it does not pair or replace product history.

## Application native session boundary

`RetainedSessionFactory`/`RetainedSession` expose immutable application values,
without foreign handles. Live composition injects `NativeRetainedSessionFactory`;
development has no native factory by default. The persisted profile coordinator
must supply the explicit trusted root, existing relative directory and numeric
socket address before production opening. This prerequisite does not mean the
chat repository consumes native history yet.

All 17 passive native publications and 18 enums have complete field mappings.
The application preserves exact UInt64 values, all six scope fields, optional
status/selection/read/recheck/withdrawal/purge/private-publication evidence and
original/retried public intents. Native constructors validate restored catalogue
keys. Worker capture covers successful getters, view serialization and decoding
before releasing physical admission. Immutable thrown error getters are mapped
off UI without touching the private owner. Cancellation, worker busy/closed,
native session/view failures and unknown bridge failure remain distinct; cancelled
callers retain a physically captured native outcome. Close awaits actual drain.

The conversation publication retains complete native-produced UTF-8 bytes alongside
today's limited display projection. Those bytes preserve pending interactions,
questions, tools, capabilities, lifecycle, completeness, title, lease, artifacts,
unknown fields and exact numeric tokens. Serialization/decoding failure preserves
transcript state/scope/progress independently, and retains complete bytes if they
were produced. There is no partial-data fallback or second saved checkpoint.

The paired experiment corrected two assumptions: catalogue and transcript have
different physical stream scopes, and the display revision is
`epoch:counter[:suffix]`, not a UUID alone. The application supplies a UUID epoch,
correlates its canonical prefix, and preserves the owner's complete revision text
separately from physical progress.

137 app tests pass. Off-UI NoHandle fixtures compare every nested mapped field and
enum, including UInt64-max values and independent error/purge evidence. Actual
library tests open/status/NoCredential/close/reopen from a MainActor caller;
cancellation tests cover dispatch relay, preserving admitted outcomes and cancelled
close, and cancellation after actual native construction before publication.
Opaque native text equality compares UTF-8 bytes rather than Swift canonical
Unicode equivalence, including scope/cursor/receipt/purge/withdrawal identities
and root target correlation. Actual regressions detect reverting this equality
and removing post-construction cancellation cleanup. The ordinary-import
verification executable also compiles substitute ports.
The existing real paired gateway fixture invokes the production app factory through
five stages: first read, offline reopen, gateway restart, terminal revocation/purge
recovery, and partial-prefix refusal/recheck. All five pass. These are application
boundary experiments, not production enrollment UI or physical-device results.

Independent implementation review passes after the Unicode equality and admitted
opener cancellation findings were corrected. Eleven focused boundary tests pass
independently. The corrected source also passes the complete 137-test suite,
all five real paired stages and architecture/design-system checks. Normal signed
simulator and generic Release device builds pass; the latest signed simulator app
and embedded framework signatures verify, and both existing chats survive its
installation/relaunch. Device execution remains unverified. The pinned gateway
revision's CI run `38311321648` passes all required checks on macOS, Linux and
Windows. This slice adds no product UI or second storage/progress owner.

## Authenticated connection identity

`AuthenticatedGatewaySessionProviding` returns an immutable application snapshot
for the caller's exact live lease. The infrastructure DTO enforces the current
ready schema, retaining all six identities, required-nullable exact expiry,
complete grants/resources and methods. Lengths count Unicode scalars; methods
are not trimmed or deduplicated. Unknown fields fail at each object boundary.
These restrictions describe the handshake; gateway policy still decides every
command. Old lease reads fail, old retirement preserves the replacement, and
disconnect/current transport failure removes the publication.
The passive values have public constructors so normal module imports can
substitute the application port. Authentication checks its original generation
and socket after receiving a challenge, and dispatch refuses a different socket.

Actual socket fixtures signal delayed authentication entry before replacement or
disconnect, and cover old success/failure, incomplete ready frames, current
transport failure, and old/current lease reads and retirement.
The peer checks unique per-socket nonces across 100 overlapping dials; the final
connection authenticates without an observed foreign challenge. This stress
check does not deterministically force every executor interleaving.
Removing lease
matching exposes the replacement identity and fails the regression; discarding
the captured publication also fails. The restored cases pass. This supplies the
authenticated product input for enrollment correlation, not the native profile
binding or retained repository by itself.

## Local enrollment correlation in the application

The package at 82d1438 and `RetainedSession.localEnrollment()` publish immutable
saved public intent, device key and pinned gateway SPKI bytes, plus the optional
issued credential/receiver pair. Swift preserves these bytes as Data and compares
opaque issued selectors by UTF-8. It adds no secret extraction, private record,
key conversion, path policy or read authority. Success capture stays inside the
existing native worker admission; storage/closed/cancellation failures use the
same typed mapping, with nil reserved for an absent local record.

The complete 138-test application suite and seven distribution regressions pass.
All new passive fields and pending/issued alternatives are checked independently
off UI. Deliberately reversing key bytes or using canonical String equality fails
the corresponding regression; restored source passes. Actual application paired
first/offline/restarted/terminal/epoch stages pass with key and credential compared
to authenticated gateway owner evidence. Revocation removes local enrollment and
reopening preserves that absence alongside the historical purge receipt.
The normally signed simulator app passes local-empty capture and the existing
open/status/cursor/NoCredential/closed/reopen check; both existing chats survive.
The generic Release device build links successfully. Device execution remains
unverified. This remains input for the persisted profile/account coordinator;
production chat history still uses the previous product-view repository path.

## Persisted profile preparation

The next slice adds immutable `PhoneProfile` records and one `PhoneProfiles`
publication containing selected identity and retained records. UUIDs name profiles;
registry revisions name saves, and neither is a socket lease. Endpoint/instance
selectors and the original product identity are public correlation only.
UUID-derived relative native directories and immutable Keychain references do not
encode a sandbox container path. Prepared means storage and credential preparation,
not native enrollment, approval or current read authority.

`PhoneProfilePreparation` saves preparing metadata before insert-or-verify of its
per-profile Keychain item, then saves prepared metadata. It does not overwrite
existing secrets or use the legacy product-v1 slot. Resume keeps the same profile
and first confirms a successful metadata publication; it adds no second lifecycle
admission owner. The future setup coordinator still owns socket/account matching,
operation tokens, explicit approval and retirement recovery.

`PhoneProfileStore` reuses existing private atomic files and holds one lock across
exact expected-byte comparison, publication and failed-write readback. A write
failure retains visible published/not-published/uncertain evidence and independent
reconciliation failure; none becomes durable success or permits setup to advance.
Keychain missing, corrupt, locked, conflicting and platform failure remain distinct.
Authenticated identity/grant/method equality now preserves exact UTF-8 bytes.

The production composition and chat history are not switched by these ports.
The optional debug native-package probe exercises a separate disposable profile,
Keychain item and native directory only when explicit probe inputs are provided.

153 full app tests and 15 independently run profile tests pass, including real
private-file contention/publication faults, disposable host Keychain, exact account
identity and actual native relocation/reopen. Eleven deliberate reversals fail;
the restored suite passes. Review caught directory preparation following an
existing NativeProfiles symlink before native validation. Creation now holds
root-relative no-follow directory descriptors, using the profile's owned relative
components; parent/leaf symlinks refuse before outside effects. Reverting to the
unsafe creator fails the real regression and creates an outside UUID directory.
A fresh second implementation review reports zero findings.

Corrected normal signed simulator and generic Release device builds pass. The
actual corrected simulator profile/native probe succeeds, preserves the same
selected profile/records and immutable Keychain reference across installation and
restart, and confirms a new metadata revision. Both existing chats remain visible;
app and embedded signatures verify. The pinned gateway82d1438 CI run38319390190
passes every required check on macOS, Linux and Windows. These are preparation
and native-boundary results, not production enrollment/repository or physical
phone execution evidence.

## Leased product pairing boundary

The app's `GatewayPairingManaging` port uses the existing product request owner
for create-device, status, approve, cancel and pending. Each accepted result and
admitted failure captures the original complete authenticated publication. Stale
lease, invalid input and cancellation before pending admission cause no dispatch.
Cancellation after admission does not discard an accepted code or status.
Replacement before acceptance leaves the remote outcome unknown; accepted replies
remain historical receipts, with no later current-lease/cancellation fence.
The future coordinator must revalidate that source before advancing setup.

Passive values preserve full consent, claimed key, receiver, terminal actor/cause,
cleanup-pending and approval activation-stop facts separately. A create code has
no Codable or profile-storage field. A generated contract, pinned to gateway82d,
validates exact schema fields, nullability, integer bounds, byte arrays and enum
spellings. Shared ready/grant/resource decoding uses that same rule owner;
malformed frames become the application's invalid-frame failure while owner wire
codes, diagnostics/details and actual transport errors stay distinct. One mapped
error settles waiter/subscriber owners; no second retry/timeout lifecycle exists.

The actual current gateway's read-only pairing.pending check returns
`pairing_not_configured`. This is not real enrollment success. Production profile
coordination, explicit approval, retained-history composition and native-enabled
live gateway experiments remain necessary; existing chats still use the previous
product-view repository path. The gateway review fixes also introduce native
uncertain-cache variants: the vendored library and phone mappings must be refreshed
from the reviewed stack before that newer ABI is used.

The restored pairing slice passes 163 app tests (the externally hosted socket test
is explicitly opt-in), eight explicit-source generator regressions, all real
pairing socket cases including two controlled accepted-receipt orderings, and the
existing full default transport/command/identity fault runner. Seven deliberate
rule reversals fail at runtime/test assertions. Fresh independent source review
passes with no remaining findings after fixing union rejection and all malformed
frame classifications. Corrected signed simulator and generic Release device
builds pass; actual simulator native/profile probes emit both success markers,
and the existing pinned Web Search and Image chats remain visible after reinstall.
No physical-device execution or chat latency improvement is claimed by this slice.

## Profile coordinator and recovery

`PhoneProfileCoordinator` now owns admission, original leased account correlation,
explicit create/claim/approval/cancellation, cold restore and native shutdown through
injected public ports. Profile metadata preserves the complete owner pairing status,
captured receiver, historical native status/purge and an immutable local creation
attempt. The attempt is saved before dispatch; it is not a gateway idempotency key.
A lost create answer cannot silently create another invitation on restart. Explicit
owner-selected recovery never retargets an existing local claim. A never-enrolled
user discard is a separate negative local decision, with no invented remote
cancellation or native terminal proof.

An issued receiver is saved before native status/refresh can remove revoked state.
Terminal evidence is then saved before durable legacy-snapshot suppression and
irreversible retirement. Failed writes remain failures even when readback sees the
new bytes; restore confirms durability before advancing. Reads require the saved
receiver and still defer current permission to Rust. Full compound refresh evidence
(initial status, read, selection failure and recheck) remains available on success
and subsequent metadata failure. No code, private key, catalogue or checkpoint is
added to profile metadata.

Close fences admission, retains one physical drain independent of any caller's
cancellation, waits for admitted work, and drains late native construction. Repeated
close joins the same owner. A failed drain is retained as failure and never permits
replacement. Last-owner disposal schedules native cleanup off the UI executor.

200 application tests and architecture/design checks pass. Eighteen coordinator
regressions include real atomic-file before/after-write uncertainty, actual Rust
late construction/drain/same-directory reopen, original lease/profile replacement,
claim-key/class correlation, receiver-before-effect failures, purge recovery and
compound refresh preservation. Five compiling reversals are rejected by assertions:
missing request marker, missing receiver save, independent close owners dropped
refresh evidence and ignored initial refresh correlation. Restored tests pass; signed simulator and generic Release device
builds pass. At this slice the native package remained pinned to reviewed gateway `542eafc3`.

At the coordinator checkpoint, production composition, setup UI, history hydration
and configured native gateway phone experiments remained pending. No new phone
latency or physical-device execution result was established by those checks.

## Application lifetime and history projections

`PhoneSyncRuntime` owns a temporary background drain separately from permanent
close. Concurrent and canceled waiters join the same physical close; replacement
waits for both native shutdown and admitted wrapper work, including a delayed
credential read. Failed drains retain their child and fence. Successful suspension
permits a fresh child to reopen the same persisted profile on foreground.

Startup restores the selected profile before handing off its immutable credential.
Only a prepared profile can hand off product connection material. A retired
profile returns passive metadata without reading the secret; preparing, changed,
corrupt or locked state never becomes a legacy fallback. A missing native profile
allows legacy startup only after the registry is confirmed still absent.

`PhoneRetainedHistory` bounds native catalogue pagination and verifies profile,
revision, receiver, full scope, generation, active boundary and cursor continuity.
It preserves complete native pages and transcript observations alongside UI
projections. Missing or unavailable history is a finite refusal, not an empty
product-cache replacement. Transcript projections must name the requested chat
and UI revision epoch. Catalogue enumeration does not establish remote catch-up.
Identical public metadata avoids incidental writes; restore still forces a
successful publication to confirm durability after an uncertain earlier write.

The application layer has passed independent review and 213 tests. Seven compiling
reversals are rejected by assertions: preparing handoff, stale handoff registry,
late wrapper publication, mixed history revision/generation, incidental identical
metadata writes and omitted restore durability confirmation. Actual packaged Rust
shutdown and same-directory reopen run through the runtime test. At this application
checkpoint, normal chat wiring, setup and configured gateway experiments remained
pending.

## Production startup and display wiring

Production composition now shares one product adapter and snapshot withdrawal
owner with the native runtime, using per-profile Keychain and the current sandbox
root. The root asks for native startup before reading the legacy credential/cache.
Only confirmed registry absence selects legacy history. Saved native connections
use their original credential; changed manual input cannot display that history
before authenticated ready matches the original account.

One admitted display operation owns refresh, bounded catalogue and requested
transcripts, with a final registry check. Its results retain partial observations
and failures. Paired lists, previews and threads use these projections; product
events trigger coalesced refreshes and supply subscription continuity only. Native
data is not written into legacy display snapshots. Background joins product and
native physical retirement; foreground restores before redial.

Cached history availability is separate from command readiness. Paired commands
require a fresh positive native read on the current product lease. Returned native
failures block dispatch while cached messages and the setup control plane remain
available. Successful and partial reads normally have no recheck; a recheck is
validated when the native driver provides one. Partial progress does not claim
catch-up. Access withdrawal drops display/read owners without deleting preferences;
later authorized regrant can restore the chat. Actual catalogue tombstones and
confirmed product deletion retain their deletion fence.

Independent review and 227 tests pass. Eight compiling reversals fail assertions,
covering cache fallback, raw live writers, fresh command admission, returned
refusal, fabricated recheck requirements, manual account crossover, final registry
validation and withdrawal mistaken for deletion. Restored gates and simulator/
generic Release builds pass. The signed live simulator retains both original chats
and opens the image conversation. The generic device build is unsigned compile/link
evidence, not physical-device execution.

Explicit pairing controls and a configured native-enabled gateway run are still
required. Backlog/catch-up behavior, actual paired latency, artifacts, uncertain
deletion and physical-device failures remain part of the original goal.
