---- MODULE ProfilePreparation ----
EXTENDS Naturals, Sequences
VARIABLES visible, durable, credential, prepared, credentialBeforeDurable, preparedWithoutCredential
vars == <<visible, durable, credential, prepared, credentialBeforeDurable, preparedWithoutCredential>>

Init == /\ visible = FALSE /\ durable = FALSE /\ credential = FALSE /\ prepared = FALSE
        /\ credentialBeforeDurable = FALSE /\ preparedWithoutCredential = FALSE
PublishPreparing == /\ ~visible /\ visible' = TRUE /\ durable' \in BOOLEAN
                    /\ UNCHANGED <<credential,prepared,credentialBeforeDurable,preparedWithoutCredential>>
RecoverPublication == /\ visible /\ ~durable /\ durable' = TRUE
                      /\ UNCHANGED <<visible,credential,prepared,credentialBeforeDurable,preparedWithoutCredential>>
SaveCredential == /\ visible /\ ~credential /\ durable
                  /\ credential' = TRUE /\ credentialBeforeDurable' = ~durable
                  /\ UNCHANGED <<visible,durable,prepared,preparedWithoutCredential>>
PublishPrepared == /\ visible /\ durable /\ ~prepared /\ credential
                   /\ prepared' = TRUE /\ preparedWithoutCredential' = ~credential
                   /\ UNCHANGED <<visible,durable,credential,credentialBeforeDurable>>
DurableBeforeCredential == ~credentialBeforeDurable
CredentialBeforePrepared == ~preparedWithoutCredential

Next == PublishPreparing \/ RecoverPublication \/ SaveCredential \/ PublishPrepared
Spec == Init /\ [][Next]_vars
====
