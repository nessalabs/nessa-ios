---- MODULE JournalRefusal ----
EXTENDS Naturals, Sequences
VARIABLES pending, attempts, ack, removedBy, removedAttempts, removedAck
vars == <<pending, attempts, ack, removedBy, removedAttempts, removedAck>>

Init == /\ pending = TRUE /\ attempts = 0 /\ ack = "None"
        /\ removedBy = "None" /\ removedAttempts = 0 /\ removedAck = "None"
Attempt == /\ pending /\ attempts < 2 /\ attempts' = attempts + 1
           /\ UNCHANGED <<pending,ack,removedBy,removedAttempts,removedAck>>
ObserveAck == /\ pending /\ attempts > 0 /\ ack = "None" /\ ack' \in {"Original","Foreign"}
              /\ UNCHANGED <<pending,attempts,removedBy,removedAttempts,removedAck>>
Reject == /\ pending /\ attempts > 0 /\ attempts = 1
          /\ pending' = FALSE /\ removedBy' = "Refusal" /\ removedAttempts' = attempts
          /\ UNCHANGED <<attempts,ack,removedAck>>
Resolve == /\ pending /\ ack # "None" /\ ack = "Original"
           /\ pending' = FALSE /\ removedBy' = "Ack" /\ removedAck' = ack
           /\ UNCHANGED <<attempts,ack,removedAttempts>>
FirstRefusalOnly == removedBy = "Refusal" => removedAttempts = 1
MatchingAckOnly == removedBy = "Ack" => removedAck = "Original"

Next == Attempt \/ ObserveAck \/ Reject \/ Resolve
Spec == Init /\ [][Next]_vars
====
