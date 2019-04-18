module Raft.Server where

import Raft.Types
import Raft.Utils
import Data.List
import Data.HashMap.Strict (fromList, HashMap)
import Control.Concurrent.MVar (newEmptyMVar, newMVar, 
                                takeMVar, tryTakeMVar,
                                putMVar, tryPutMVar)
import Control.Concurrent (forkIO, MVar, threadDelay)
import Control.Monad.State.Lazy (runState, get, put, gets)
import Control.Monad (mapM_, mapM)
import Control.Concurrent.Chan (newChan, readChan, writeChan, dupChan, Chan)
import Control.Concurrent.Async (async, wait, race)
import Data.Maybe (Maybe(..), isJust, fromJust)
import qualified Data.ByteString.Lazy.Char8 as DB (ByteString, empty)
import Data.Aeson (encode, eitherDecode)


------------------------- Intial State of the server ---------------------------
myState = NodeState {
    currentTerm = Term 0,
    votedFor = unVote,
    rState = FOLLOWER
}

-- MVar lock for accessing myState
nodeStateMVar :: IO (MVar NodeState)
nodeStateMVar = newEmptyMVar

-- followerChan is set whenever you're supposed to be in FOLLOWER state
followerChan :: IO (MVar ())
followerChan = newEmptyMVar

commitIndexMVar :: IO (MVar LogIndex)
commitIndexMVar = newMVar $ LogIndex 0

lastAppliedMVar :: IO (MVar LogIndex)
lastAppliedMVar = newMVar $ LogIndex 0

logMVar :: IO (MVar Log)
logMVar = newMVar $ initLog

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
  if isJust val then follow myNodeId else contest myNodeId


------------------------- CANDIDATE Implementation ----------------------------

contest :: NodeId -> IO ()
contest myNodeId = do
  curState <- nodeStateMVar >>= takeMVar
  let newState = curState{currentTerm = nextTerm (currentTerm curState),
           rState = CANDIDATE, votedFor = myNodeId}
  nodeStateMVar >>= \mvar -> putMVar mvar newState
  args <- getRequestVoteArgs newState
  voteCounter <- newChan :: IO (Chan Int)
  quitChans <- mapM (\_ -> newEmptyMVar) nodeIds
  mapM_ (\(nodeId, chan) -> async $ do
                      sendVoteRequestTo nodeId args voteCounter myNodeId chan quitChans)
        (zip nodeIds quitChans)
  let majority = (div nodesInCluster 2) + 1
  Right res <- race (waitAndBroadcast quitChans) (collectVotes voteCounter 0 0)
  case res of
    Nothing -> contestOrFollow myNodeId quitChans
    Just count | count >= majority -> broadcast quitChans  () >> lead myNodeId
               | otherwise -> contestOrFollow myNodeId quitChans
  where 
    getRequestVoteArgs st = do
      log <- logMVar >>= takeMVar
      return $ RequestVoteArgs (currentTerm st) myNodeId
                               (getLastLogTerm log) (getLastLogIndex log)
    
    waitAndBroadcast quitChans = threadDelay electionTimeout >> broadcast quitChans ()

sendVoteRequestTo :: NodeId -> RequestVoteArgs -> Chan Int -> NodeId -> MVar () -> [MVar ()] -> IO ()   
sendVoteRequestTo nodeId args voteCounter myNodeId quitChan quitChans = 
    do
      q <- tryTakeMVar quitChan 
      if isJust q then
        writeChan voteCounter 0
      else
        do
          res <- send nodeId args
          let response = if isJust res then 
                eitherDecode (fromJust res) :: Either String RequestVoteResponse 
                else 
                  Left "Request failed" 
          case response of
            Left err -> do
              putStrLn err 
              sendVoteRequestTo nodeId args voteCounter myNodeId quitChan quitChans
            Right (RequestVoteResponse trm reply) 
              | reply -> writeChan voteCounter 0
              | otherwise -> do
                  broadcast quitChans ()
                  if trm > (term args) then updateToFollower trm else return ()
                  followerChan >>= \mvar -> tryPutMVar mvar ()
                  return ()

updateToFollower :: Term -> IO ()
updateToFollower trm = do
  curState <- nodeStateMVar >>= takeMVar
  let newState = curState{currentTerm = trm,
           rState = FOLLOWER, votedFor = unVote}
  nodeStateMVar >>= \mvar -> putMVar mvar newState


broadcast :: [MVar a] -> a -> IO ()
broadcast quitChans val = mapM_ (\chan -> tryPutMVar chan val) quitChans

collectVotes :: Chan Int -> Int -> Int -> IO (Maybe Int)
collectVotes voteCounter votesCounted votesReceived = 
  if (votesCounted==nodesInCluster) || (votesReceived >= majority) then
    return $ Just votesReceived
  else 
    do
      v <- readChan voteCounter
      collectVotes voteCounter (votesCounted + 1) (votesReceived + v)
  where majority = (div nodesInCluster 2) + 1

contestOrFollow :: NodeId -> [MVar ()] -> IO ()
contestOrFollow myNodeId quitChans = do
  toFollow <- followerChan >>= tryTakeMVar
  if isJust toFollow then 
    broadcast quitChans () >> follow myNodeId 
  else 
    threadDelay electionTimeout >> contest myNodeId

---------------------------- LEADER Implementation -------------------------------

lead :: NodeId -> IO ()
lead myNodeId = return ()


