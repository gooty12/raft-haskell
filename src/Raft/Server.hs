module Raft.Server where

import Raft.Types
import Raft.Utils
import Data.List
import Data.HashMap.Strict (fromList, HashMap)


myState = RAFTState {
    currentTerm = Term 0,
    votedFor = unVote,
    rLog = initLog,
    commitIndex = LogIndex 0,
    lastApplied = LogIndex 0,
    nextIndex = initMap nodeIds (LogIndex 1),
    matchIndex = initMap nodeIds (LogIndex 0)
}

localHostName = "127.0.0.1"

nodesInCluster = 5
nodeIds = [NodeId i | i <- [1..nodesInCluster]]
nodesAddrs = [NodeAddress localHostName (show $ 3000 + port) | port <- [1 .. nodesInCluster]]

clusterConfig = fromList $ zip nodeIds nodesAddrs

initMap :: [NodeId] -> LogIndex -> HashMap NodeId LogIndex
initMap nodeIds val = fromList [(k, val) | k <- nodeIds]