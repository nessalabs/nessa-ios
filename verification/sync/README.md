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
