module Raft.Server where

import Raft.Types
import Raft.Utils
import Data.List
import Data.HashMap.Strict (fromList, HashMap)
import Control.Concurrent.MVar (newEmptyMVar, takeMVar, tryTakeMVar, putMVar)
import Control.Concurrent (forkIO, MVar, threadDelay)
import Control.Monad.State.Lazy (runState, get, put, gets)
import Control.Monad (mapM_)
import Control.Concurrent.Chan (newChan, readChan, writeChan, dupChan, Chan)
import Control.Concurrent.Async (async, wait, race)
import Data.Maybe (Maybe(..), isJust, fromJust)
import qualified Data.ByteString.Lazy.Char8 as DB (ByteString, empty)
import Data.Aeson (encode, eitherDecode)


------------------------- Intial State of the server ---------------------------
myState = NodeState {
    currentTerm = Term 0,
    votedFor = unVote,
    rLog = initLog,
    commitIndex = LogIndex 0,
    lastApplied = LogIndex 0,
    nextIndex = initMap nodeIds (LogIndex 1),
    matchIndex = initMap nodeIds (LogIndex 0),
    rState = FOLLOWER
}

-- MVar lock for accessing myState
nodeStateMVar :: IO (MVar ())
nodeStateMVar = newEmptyMVar

getStateLock :: IO ()
getStateLock = nodeStateMVar >>= takeMVar  >> return ()

putStateLock :: IO ()
putStateLock = nodeStateMVar >>= (\mvar -> putMVar mvar ())  >> return ()

isFollower :: IO Bool
isFollower = do
  getStateLock
  let isFlwr = fst (runState (gets rState) myState) == FOLLOWER
  putStateLock
  return isFlwr


-- followerChan is set whenever you're supposed to be in FOLLOWER state
followerChan :: IO (MVar ())
followerChan = newEmptyMVar

------------------------- Cluster Configuration -------------------------------
nodesInCluster = 5
nodeIds = [NodeId i | i <- [1..nodesInCluster]]
nodesAddrs = [NodeAddress localHostName (show $ 3000 + port) | port <- [1 .. nodesInCluster]]

clusterConfig :: HashMap NodeId NodeAddress
clusterConfig = fromList $ zip nodeIds nodesAddrs

-- election timeout 120 milli secs = 120 * 1000 micro secs
electionTimeout = 120000

-- Once server is launched it starts listening to messages from outside (RPCs
-- from fellow servers well as new commands from clients) and begins as a
-- follower
launchServer host port myNodeId = do
  forkIO (startListening host port) >> follow myNodeId

-- Opens conncection and starts processing messages
startListening :: [Char] -> [Char] -> IO ()
startListening host port = return ()


------------------------- Networking layer ------------------------------

send :: NodeId -> RequestVoteArgs -> IO (Maybe DB.ByteString)
send nodeId args = do
  return $ Just DB.empty

------------------------- FOLLOWER Implementation -----------------------------
follow :: NodeId -> IO ()
follow myNodeId = do
  threadDelay electionTimeout
  val <- followerChan >>= tryTakeMVar
  case val of 
    Nothing -> contest myNodeId
    Just _ -> follow myNodeId


------------------------- CANDIDATE Implementation ----------------------------

contest :: NodeId -> IO ()
contest myNodeId = do
  updateStateToCandidate -- [FIX!] - vote for self not unvote
  voteCounter <- newChan :: IO (Chan Int)
  args <- getRequestVoteArgs myNodeId
  mapM_ (\nodeId -> async $ sendVoteRequestTo nodeId args voteCounter myNodeId) nodeIds
  let majority = (div nodesInCluster 2) + 1
  Right res <- race (threadDelay electionTimeout >> return Nothing) (collectVotes voteCounter 0 0)
  case res of
    Nothing -> contestOrFollow myNodeId
    Just count | count < 0 -> follow myNodeId
               | count >= majority -> lead myNodeId
               | otherwise -> contestOrFollow myNodeId
  return ()

updateStateToCandidate :: IO ()
updateStateToCandidate = do
  getStateLock
  let (st, _) = runState get myState
      newState = st {currentTerm = nextTerm (currentTerm st),
                     rState = CANDIDATE, votedFor = unVote}
  return (runState (put newState) myState)
  putStateLock

getRequestVoteArgs :: NodeId -> IO RequestVoteArgs
getRequestVoteArgs myNodeId = do
  getStateLock
  let (st, _) = runState get myState
      newState = st {currentTerm = nextTerm (currentTerm st),
                     rState = CANDIDATE, votedFor = unVote}
  putStateLock
  return $ RequestVoteArgs (currentTerm st) myNodeId
                         (getLastLogTerm $ rLog st)
                         (getLastLogIndex $ rLog st)

largeNegativeVal = -1000

sendVoteRequestTo :: NodeId -> RequestVoteArgs ->Chan Int -> NodeId -> IO ()
sendVoteRequestTo nodeId args voteCounter myNodeId = do
  fol <- isFollower
  if fol then
    writeChan voteCounter largeNegativeVal
  else
    do
      res <- send nodeId args
      let response = if isJust res then 
            eitherDecode (fromJust res) :: Either String RequestVoteResponse 
            else 
              Left "Request failed" 
      case response of
        Left err -> putStrLn err >> sendVoteRequestTo nodeId args voteCounter myNodeId
        Right res -> return ()

collectVotes :: Chan Int -> Int -> Int -> IO (Maybe Int)
collectVotes voteCounter votesCounted votesReceived = 
  if (votesCounted==nodesInCluster) || 
     (votesReceived >= majority) ||
     (votesReceived < 0) then
    return $ Just votesReceived
  else 
    do
      v <- readChan voteCounter
      collectVotes voteCounter (votesCounted + 1) (votesReceived + 1)
  where majority = (div nodesInCluster 2) + 1

contestOrFollow :: NodeId -> IO ()
contestOrFollow myNodeId = do
  threadDelay electionTimeout
  isFollower >>= \fol -> if fol then follow myNodeId else contest myNodeId

---------------------------- LEADER Implementation -------------------------------

lead :: NodeId -> IO ()
lead myNodeId = return ()


