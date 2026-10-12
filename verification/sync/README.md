# Phone synchronization verification

Run deterministic local lifecycle experiments on macOS with Swift/Xcode and Python 3.9+:

```sh
./verification/sync/run-fixtures.sh
```

The runner installs the pinned peer dependency in a temporary environment, starts a loopback-only peer on an ephemeral port, builds the production Swift adapter into `PhoneSyncVerification`, and cleans up the peer and temporary environment. Set `NESSA_VERIFICATION_PYTHON` to an existing interpreter with the pinned dependency to reuse it. The peer accepts only `fixture-only`; never supply a real credential to it.

Cases: cancel before subscribe acknowledgment with a live inbox; rapid A→B→C navigation; asynchronous termination with a delayed unsubscribe acknowledgment; foreign conversation publication; acknowledged registration with a missing first publication; lost registration acknowledgment. Publication waits have deadlines and the verification process has a 75-second watchdog. The final case waits the production 30-second request deadline and verifies its socket owner and other streams retire.

Run real transport/model latency experiments against an isolated gateway using a credential file:

```sh
swift build --product PhoneSyncVerification
.build/debug/PhoneSyncVerification --live ws://127.0.0.1:18743/session /absolute/path/to/test-panel.token
```

The live check creates one disposable Codex/Terra conversation, follows the inbox and conversation, sends five tool-free timing probes, measures authentication, provider session creation, send acknowledgment, first visible view and completed model reply separately, verifies immediate resubscription, and deletes the conversation. It fails if delivery fails; it does not print the credential. Use a non-production test namespace. These are native-client transport measurements, not render-frame or physical-device timing.

See [the sync plan](../../docs/sync/PLAN.md) for the remaining durable-cache and retained-core gates. Replacement views and their cursors do not establish physical-record retained progress.

To verify phone photo input against the same isolated gateway:

```sh
.build/debug/PhoneSyncVerification --image ws://127.0.0.1:18743/session /absolute/path/to/test-panel.token
```

This generates a blue PNG with a red circle and yellow square, applies the phone's model-selection logic, uploads and sends it, checks the history reference and exact locally cached bytes, waits for a completed model response, and deletes the test chat. It does not open or send photos from the user's library. The gateway must advertise and implement image input for its selected agent/model. Recognition quality is reported through the response rather than asserted against an exact sentence. Photo preparation/downsampling is covered by the app tests; picker and rendering verification still requires the app.
