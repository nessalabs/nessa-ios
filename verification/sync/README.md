# Phone synchronization verification

Run deterministic local lifecycle experiments on macOS with Swift/Xcode and Python 3.9+:

```sh
./verification/sync/run-fixtures.sh
```

The runner installs the pinned peer dependency in a temporary environment, starts a loopback-only peer on an ephemeral port, builds the production Swift adapter into `PhoneSyncVerification`, and cleans up the peer and temporary environment. Set `NESSA_VERIFICATION_PYTHON` to an existing interpreter with the pinned dependency to reuse it. The peer accepts only `fixture-only`; never supply a real credential to it.

Cases: cancel before subscribe acknowledgment with a live inbox; rapid A→B→C navigation; asynchronous termination with a delayed unsubscribe acknowledgment; foreign conversation publication; acknowledged registration with a missing first publication; old connection cleanup versus a ready replacement; lost registration acknowledgment; lost create/submit acknowledgments with disk recreation and exact retries; foreign command identities and cross-scope dispatch. Publication waits have deadlines and the verification process has a 75-second watchdog. The final case waits the production 30-second request deadline and verifies its socket owner and other streams retire.

Authenticated identity cases use the real full ready frame. A disposable peer
marker proves delayed authentication entered before replacement/disconnect.
Late old success/refusal cannot replace or clear current identity; old lease reads
and retirement, incomplete ready frames, and current transport loss are checked.
To check full identity decoding and retirement against a real gateway without
creating chats or sending messages:

```sh
.build/debug/PhoneSyncVerification --identity-live ws://127.0.0.1:18743/session /absolute/path/to/test-panel.token
```

Run real transport/model latency experiments against an isolated gateway using a credential file:

```sh
swift build --product PhoneSyncVerification
.build/debug/PhoneSyncVerification --live ws://127.0.0.1:18743/session /absolute/path/to/test-panel.token
```

The live check injects a temporary disk journal, creates one disposable Codex/Terra conversation, follows the inbox and conversation, sends twenty tool-free timing probes, measures authentication, provider session creation, send acknowledgment, first visible view and completed model reply separately, reports nearest-rank p50/p95/max, verifies immediate resubscription and an empty pending journal, and deletes the conversation. It fails if delivery fails; it does not print the credential. Use a non-production test namespace. These are native-client transport measurements, not render-frame or physical-device timing.

See [the sync plan](../../docs/sync/PLAN.md) for the remaining command-recovery and retained-core gates. Replacement views and their cursors do not establish physical-record retained progress.

To verify phone photo input against the same isolated gateway:

```sh
.build/debug/PhoneSyncVerification --image ws://127.0.0.1:18743/session /absolute/path/to/test-panel.token
```

This generates a blue PNG with a red circle and yellow square, applies the phone's model-selection logic, uploads and sends it, checks the history reference and exact locally cached bytes, waits for a completed model response, and deletes the test chat. It does not open or send photos from the user's library. The gateway must advertise and implement image input for its selected agent/model. Recognition quality is reported through the response rather than asserted against an exact sentence. Photo preparation/downsampling is covered by the app tests; picker and rendering verification still requires the app.

To check exact command identities and durable receipts against the isolated real gateway:

```sh
.build/debug/PhoneSyncVerification --command-live ws://127.0.0.1:18743/session /absolute/path/to/test-panel.token
```

This uses the application journal and production typed socket port. It creates a disposable chat, repeats the same creation ID, submits one frozen message, recreates the disk journal before observing the submission confirmation, looks up its receipt, retries the same request/execution IDs, verifies one turn and resolves the record durably. It then deletes its test chat. Product composition now also injects the journal; the scripted product cases and image runner cover the view-model create/send path.

Product fault cases recreate presentation, transport and disk journal after lost ACKs, test Check versus explicit Retry, first-attempt model/photo refusals, a later refusal after earlier uncertainty, and corrupted journal binding.

To exercise the application-owned retained session against the existing disposable
paired native gateway fixture, first build `PhoneSyncVerification` here, then run
this from the gateway checkout matching `Vendor/NessaNative/SOURCE.json`:

```sh
NESSA_NATIVE_SWIFT_CHECK=/absolute/path/to/nessa-ios/.build/debug/PhoneSyncVerification \
  cargo test -p nessa-server generated_swift_runs_paired_native_lifecycle -- --ignored --nocapture
```

The fixture supplies its own private directory, paired identities and endpoint.
It invokes the production application factory for first read, offline reopen,
gateway restart, revocation/purge receipt recovery and partial-prefix refusal.
The executable accepts those seven fixture arguments; do not point it at a user's
private native directory. Full view bytes and exact progress stay separate from
the display projection. This checks the application boundary; production profile
enrollment and actual phone history composition still need integration.

Pairing setup uses the explicit authenticated connection lease and the existing
request/timeout owner. Run the real WebSocket contract and ordering cases with:

```sh
bash verification/sync/run-pairing-fixtures.sh
```

This verifies create-device, status, approval, cancel and pending parameters,
complete original-source receipts, UInt64-max and beyond-JavaScript-safe counters,
byte-array identity encoding, malformed/raw JSON refusals, error-code policy,
pre-admission cancellation, admitted cancellation, connection replacement and
accepted receipts held before publication. It starts only a disposable loopback
peer and also runs the opt-in actor-settlement socket test. Normal `swift test`
reports that socket test skipped unless `NESSA_PAIRING_FIXTURE_ENDPOINT` is set.

The generated wire grammar is frozen from a clean reviewed gateway checkout;
normal app compilation does not need that checkout. To verify provenance and
unsupported-grammar regressions, provide the source explicitly:

```sh
python3 scripts/generate-gateway-pairing.py "$GATEWAY_CHECKOUT" --check
NESSA_GATEWAY_SCHEMA_SOURCE="$GATEWAY_CHECKOUT" \
  python3 -m unittest discover -s verification/sync -p test_gateway_pairing_generator.py
```

Without that explicit prerequisite the generator regression class reports a
skip; it never guesses a sibling checkout. To observe the currently configured
real gateway's pairing capability without creating or approving an invitation:

```sh
.build/debug/PhoneSyncVerification --pairing-live ws://127.0.0.1:18743/session /absolute/path/to/test-panel.token
```

A typed capability/configuration refusal is reported as observed evidence. This
read-only check does not broaden grants or substitute a different credential.


Read-only diagnostics for an explicitly selected isolated gateway and native
profile:

```sh
.build/debug/PhoneSyncVerification --owner-list ws://127.0.0.1:19743/session /absolute/path/to/test-panel.token original-instance
.build/debug/PhoneSyncVerification --pairing-inspect ws://127.0.0.1:19743/session /absolute/path/to/test-panel.token
.build/debug/PhoneSyncVerification --retained-inspect /absolute/sandbox/root NativeProfiles/profile-uuid 127.0.0.1:19744 conversation-uuid
```

These print public identities and retained observations, never the product token
or native private key. The native inspection reads cached state without refresh;
background and physically close the app's native owner first. Never open the
same private directory concurrently. An empty owner list does not prove no
sessions exist: the product list excludes chats without a summary. Native
`notLoaded` is recorded as such, not converted to an empty readable transcript.
