module Raft.Utils where

import Raft.Types
import Data.List
import Data.HashMap.Strict (fromList, HashMap)

initLog :: Log
initLog = Log [LogEntry (Command 1) (Term 0)]

unVote :: NodeId
unVote = NodeId (-1)

hasVoted :: NodeId -> Bool
hasVoted vote = vote /= unVote

initMap :: [NodeId] -> LogIndex -> HashMap NodeId LogIndex
initMap nodeIds val = fromList [(k, val) | k <- nodeIds]

nextTerm :: Term -> Term
nextTerm (Term t) = Term (t+1)

nextIndex :: LogIndex -> LogIndex
nextIndex (LogIndex indx) = LogIndex $ indx+1

getLastLogIndex :: Log -> LogIndex
getLastLogIndex (Log ls) = LogIndex $ (length ls) - 1

getLastLogTerm  :: Log -> Term
getLastLogTerm arg@(Log ls) = 
  logTerm $ getEntryAt arg indx 
  where indx = getLastLogIndex arg

getEntryAt :: Log -> LogIndex -> LogEntry
getEntryAt (Log ls) (LogIndex indx) = ls !! indx

getPrevIndex :: LogIndex -> LogIndex
getPrevIndex (LogIndex indx) = LogIndex (indx - 1)

getEntriesFrom :: LogIndex -> Log -> Log
getEntriesFrom (LogIndex indx) (Log lg) = Log $ drop (indx-1) lg

append :: Log -> Log -> Log
append (Log lg1) (Log lg2) = Log $ lg1 ++ lg2

deleteAfter :: LogIndex -> Log -> Log
deleteAfter (LogIndex indx) (Log lg) = Log $ take (indx+1) lg

localHostName = "127.0.0.1"