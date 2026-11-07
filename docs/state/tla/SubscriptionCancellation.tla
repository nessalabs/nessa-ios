---- MODULE SubscriptionCancellation ----
EXTENDS Naturals, Sequences
VARIABLES phase, cancelled, cleanupID, activatedCancelled
vars == <<phase, cancelled, cleanupID, activatedCancelled>>

Init == /\ phase = "Pending" /\ cancelled = FALSE /\ cleanupID = FALSE /\ activatedCancelled = FALSE
Cancel == /\ phase = "Pending" /\ ~cancelled /\ cancelled' = TRUE
          /\ UNCHANGED <<phase,cleanupID,activatedCancelled>>
Activate == /\ phase = "Pending"
            /\ phase' = IF cancelled THEN "Cleanup" ELSE "Live"
            /\ cleanupID' = cancelled /\ activatedCancelled' = cancelled /\ UNCHANGED cancelled
End == /\ phase = "Live" /\ phase' = "Ended" /\ UNCHANGED <<cancelled,cleanupID,activatedCancelled>>
NoCancelledActivation == phase = "Live" => ~activatedCancelled
LateIDRetainedForCleanup == phase = "Cleanup" => cleanupID

Next == Cancel \/ Activate \/ End
Spec == Init /\ [][Next]_vars
====
