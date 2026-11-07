---- MODULE DictationGeneration ----
EXTENDS Naturals, Sequences
VARIABLES token, callback, state, accepted, acceptedToken, updatedToken, cleaned, cleanupToken, cleanedCurrentToken
vars == <<token, callback, state, accepted, acceptedToken, updatedToken, cleaned, cleanupToken, cleanedCurrentToken>>

Init == /\ token = 0 /\ callback = 0 /\ state = "Listening"
        /\ accepted = FALSE /\ acceptedToken = 0 /\ updatedToken = 0
        /\ cleaned = FALSE /\ cleanupToken = 0 /\ cleanedCurrentToken = 0
Replace == /\ token = 0 /\ token' = 1 /\ state' = "Listening"
           /\ UNCHANGED <<callback,accepted,acceptedToken,updatedToken,cleaned,cleanupToken,cleanedCurrentToken>>
Result == /\ state = "Listening" /\ ~accepted /\ callback = token
          /\ accepted' = TRUE /\ acceptedToken' = callback /\ updatedToken' = token
          /\ UNCHANGED <<token,callback,state,cleaned,cleanupToken,cleanedCurrentToken>>
Finish == /\ ~cleaned /\ callback = token
          /\ cleaned' = TRUE /\ cleanupToken' = callback /\ cleanedCurrentToken' = token /\ state' = "Idle"
          /\ UNCHANGED <<token,callback,accepted,acceptedToken,updatedToken>>
CurrentTranscriptOnly == accepted => acceptedToken = updatedToken
CurrentCleanupOnly == cleaned => cleanupToken = cleanedCurrentToken

Next == Replace \/ Result \/ Finish
Spec == Init /\ [][Next]_vars
====
