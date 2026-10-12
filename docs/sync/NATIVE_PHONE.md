# Native receiver in the phone (proposed integration)

The gateway bridge exists locally and is under independent review. Its library
and Swift worker have run against paired records, offline reopen, restart and
revocation; a release library also runs in a disposable simulator app. These
checks do not mean Nessa's production repository uses the receiver yet.

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
organization, membership, credential and audience identities. The phone currently
decodes only its version. Preserve the real ready identity tied to the socket
lease before correlating it with native setup; strings in UI configuration are
not authenticated identity.

Native disclosure contains audience and gateway grant/resource/organization. It
intentionally omits the owner principal and membership. In local composition,
the ready gateway/audience and the disclosed grant resource identify the gateway,
not the human principal. Comparing only organization and host would mix accounts.

Setup must capture an invitation created/read by the authenticated product owner
through existing `pairing.create/status/approve` operations, correlate the native
attempt with that exact invitation and claimed key, and persist its binding to
the original authenticated principal/membership. Owner status includes exact
invitation/consent/generation/class, claimed key, credential and receiver. The
native API currently exports phase/credential/receiver/disclosed scope but not
public invitation/key selectors; inspect and expose the existing immutable
correlation through its owner when needed. Do not reconstruct these selectors in
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

Before enabling retained publication, add the existing owner's public intent/key
correlation API and persist the product principal/membership binding. Product
bearer and native issued credential IDs are distinct; their enrollment relationship
is checked rather than requiring equal credential IDs. Native terminal evidence
must durably suppress derived snapshots/preferences and fence late writers, not
merely clear view-model arrays. Artifact transfer remains unavailable until its
existing crate-private owner is exported. Durable deletion keeps exact
request/target/profile evidence and does not infer removal from list absence.
