module Raft.Utils where

import Raft.Types

initLog :: Log
initLog = Log [LogEntry (Command 1)]

unVote :: NodeId
unVote = NodeId (-1)

hasVoted :: NodeId -> Bool
hasVoted vote = vote /= unVote