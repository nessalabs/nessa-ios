---- MODULE LinkedRetirement ----
EXTENDS Naturals, Sequences
VARIABLES readers, forgotten, unclean, deleted, deletedReaders, deletedUnclean
vars == <<readers, forgotten, unclean, deleted, deletedReaders, deletedUnclean>>

Init == /\ readers = 0 /\ forgotten = FALSE /\ unclean = FALSE /\ deleted = FALSE
        /\ deletedReaders = 0 /\ deletedUnclean = FALSE
Open == /\ ~forgotten /\ readers < 2 /\ readers' = readers + 1
        /\ UNCHANGED <<forgotten,unclean,deleted,deletedReaders,deletedUnclean>>
Forget == /\ ~forgotten /\ forgotten' = TRUE
          /\ UNCHANGED <<readers,unclean,deleted,deletedReaders,deletedUnclean>>
CloseClean == /\ readers > 0 /\ readers' = readers - 1
              /\ UNCHANGED <<forgotten,unclean,deleted,deletedReaders,deletedUnclean>>
CloseUnclean == /\ readers > 0 /\ readers' = readers - 1 /\ unclean' = TRUE
                /\ UNCHANGED <<forgotten,deleted,deletedReaders,deletedUnclean>>
Delete == /\ forgotten /\ ~deleted /\ readers = 0 /\ ~unclean
          /\ deleted' = TRUE /\ deletedReaders' = readers /\ deletedUnclean' = unclean
          /\ UNCHANGED <<readers,forgotten,unclean>>
DrainBeforeDelete == deleted => deletedReaders = 0
CleanBeforeDelete == deleted => ~deletedUnclean

Next == Open \/ Forget \/ CloseClean \/ CloseUnclean \/ Delete
Spec == Init /\ [][Next]_vars
====
