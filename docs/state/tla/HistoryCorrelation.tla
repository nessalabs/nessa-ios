---- MODULE HistoryCorrelation ----
EXTENDS Naturals, Sequences
VARIABLES phase, profile, receiver, generation, acceptedProfile, acceptedReceiver, acceptedGeneration
vars == <<phase, profile, receiver, generation, acceptedProfile, acceptedReceiver, acceptedGeneration>>

Init == /\ phase = "FirstPage" /\ profile = 0 /\ receiver = 0 /\ generation = 0
        /\ acceptedProfile = 0 /\ acceptedReceiver = 0 /\ acceptedGeneration = 0
NextPage == /\ phase = "FirstPage" /\ phase' = "Candidate"
            /\ profile' \in 0..1 /\ receiver' \in 0..1 /\ generation' \in 0..1
            /\ UNCHANGED <<acceptedProfile,acceptedReceiver,acceptedGeneration>>
Publish == /\ phase = "Candidate" /\ profile = 0 /\ receiver = 0 /\ generation = 0
           /\ phase' = "Published" /\ acceptedProfile' = profile
           /\ acceptedReceiver' = receiver /\ acceptedGeneration' = generation
           /\ UNCHANGED <<profile,receiver,generation>>
Reject == /\ phase = "Candidate" /\ (profile # 0 \/ receiver # 0 \/ generation # 0)
          /\ phase' = "Refused" /\ UNCHANGED <<profile,receiver,generation,acceptedProfile,acceptedReceiver,acceptedGeneration>>
SameProfile == phase = "Published" => acceptedProfile = 0
SameReceiver == phase = "Published" => acceptedReceiver = 0
SameGeneration == phase = "Published" => acceptedGeneration = 0

Next == NextPage \/ Publish \/ Reject
Spec == Init /\ [][Next]_vars
====
