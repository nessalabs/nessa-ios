---- MODULE DraftOwnership ----
EXTENDS Naturals, Sequences
VARIABLES revision, scope, capturedRevision, capturedScope, owned, cleared, clearRevision, clearScope
vars == <<revision, scope, capturedRevision, capturedScope, owned, cleared, clearRevision, clearScope>>

Init == /\ revision = 0 /\ scope = 0 /\ capturedRevision = 0 /\ capturedScope = 0
        /\ owned = FALSE /\ cleared = FALSE /\ clearRevision = 0 /\ clearScope = 0
Begin == /\ ~owned /\ ~cleared /\ revision = 0 /\ scope = 0
         /\ owned' = TRUE /\ capturedRevision' = revision /\ capturedScope' = scope
         /\ UNCHANGED <<revision,scope,cleared,clearRevision,clearScope>>
Edit == /\ owned /\ revision = 0 /\ revision' = 1
        /\ UNCHANGED <<scope,capturedRevision,capturedScope,owned,cleared,clearRevision,clearScope>>
Switch == /\ owned /\ scope = 0 /\ scope' = 1
          /\ UNCHANGED <<revision,capturedRevision,capturedScope,owned,cleared,clearRevision,clearScope>>
Accept == /\ owned
          /\ capturedRevision = revision
          /\ capturedScope = scope
          /\ cleared' = TRUE /\ owned' = FALSE
          /\ clearRevision' = revision /\ clearScope' = scope
          /\ UNCHANGED <<revision,scope,capturedRevision,capturedScope>>
Forget == /\ owned /\ (capturedRevision # revision \/ capturedScope # scope)
          /\ owned' = FALSE /\ UNCHANGED <<revision,scope,capturedRevision,capturedScope,cleared,clearRevision,clearScope>>
OnlyOriginalDraft == cleared => clearRevision = capturedRevision
OnlyOriginalScope == cleared => clearScope = capturedScope

Next == Begin \/ Edit \/ Switch \/ Accept \/ Forget
Spec == Init /\ [][Next]_vars
====
