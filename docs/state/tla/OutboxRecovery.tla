---- MODULE OutboxRecovery ----
EXTENDS Naturals, Sequences
VARIABLES phase, durable, sends, recovery, lookup, recoveryBefore, recoveryAfter, unsafeDispatch
vars == <<phase, durable, sends, recovery, lookup, recoveryBefore, recoveryAfter, unsafeDispatch>>

Init == /\ phase = "Draft" /\ durable = FALSE /\ sends = 0 /\ recovery = FALSE
        /\ lookup = "None" /\ recoveryBefore = 0 /\ recoveryAfter = 0 /\ unsafeDispatch = FALSE
Save == /\ phase = "Draft" /\ phase' = "Saved"
        /\ UNCHANGED <<durable,sends,recovery,lookup,recoveryBefore, recoveryAfter,unsafeDispatch>>
Depart == /\ phase = "Saved" /\ durable' = TRUE /\ phase' = "Departed"
          /\ UNCHANGED <<sends,recovery,lookup,recoveryBefore, recoveryAfter,unsafeDispatch>>
Dispatch == /\ phase \in {"Saved","Departed"} /\ sends = 0
            /\ durable
            /\ phase' = "Unknown" /\ sends' = 1 /\ unsafeDispatch' = ~durable
            /\ UNCHANGED <<durable,recovery,lookup,recoveryBefore, recoveryAfter>>
Restart == /\ phase = "Unknown" /\ ~recovery /\ recovery' = TRUE
           /\ UNCHANGED <<phase,durable,sends,lookup,recoveryBefore, recoveryAfter,unsafeDispatch>>
Lookup == /\ phase = "Unknown" /\ recovery /\ lookup = "None"
          /\ lookup' \in {"Absent","Found","Lost"}
          /\ UNCHANGED <<phase,durable,sends,recovery,recoveryBefore, recoveryAfter,unsafeDispatch>>
Recover == /\ phase = "Unknown" /\ recovery /\ lookup # "None" /\ sends < 2
           /\ phase' = IF lookup = "Found" THEN "Known" ELSE "Unknown"
           /\ sends' = sends /\ recoveryBefore' = sends /\ recoveryAfter' = sends'
           /\ UNCHANGED <<durable,recovery,lookup,unsafeDispatch>>
ExplicitRetry == /\ phase = "Unknown" /\ lookup = "Absent" /\ sends < 2
                 /\ sends' = sends + 1 /\ recovery' = FALSE /\ lookup' = "None"
                 /\ UNCHANGED <<phase,durable,recoveryBefore, recoveryAfter,unsafeDispatch>>
PersistBeforeDispatch == ~unsafeDispatch
RecoveryDoesNotSend == recoveryBefore = recoveryAfter

Next == Save \/ Depart \/ Dispatch \/ Restart \/ Lookup \/ Recover \/ ExplicitRetry
Spec == Init /\ [][Next]_vars
====
