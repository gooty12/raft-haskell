{-# Language RecordWildCards, MultiWayIf #-}
module Raft.Server where

import Raft.Types
import Raft.Utils
import Raft.Network
import Prelude hiding (lookup)
import Data.List hiding (lookup, insert)
import Data.Aeson (encode, eitherDecode)
import Data.HashMap.Strict (fromList, HashMap, elems, lookup, insert)
import Data.Maybe (Maybe(..), isJust, fromJust)
import Data.Either (Either(..), fromRight, fromLeft)
import qualified Data.ByteString.Lazy as DB (ByteString, empty, null)
import Control.Concurrent.MVar (newEmptyMVar, newMVar, 
                                takeMVar, tryTakeMVar,
                                putMVar, tryPutMVar)
import Control.Concurrent (forkIO, MVar, threadDelay)
import Control.Monad.State.Lazy (runState, get, put, gets)
import Control.Monad (mapM_, mapM)
import Control.Concurrent.Chan (newChan, readChan, writeChan, dupChan, Chan)
import Control.Concurrent.Async (async, wait, race)
import Network.Socket hiding (send, sendTo, recv, recvFrom)
import Network.Socket.ByteString.Lazy
import qualified Control.Exception as E
import Control.Monad (unless, forever, void)
import Control.Concurrent (forkFinally)



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

getNodeAddress :: NodeId -> Maybe NodeAddress
getNodeAddress nodeId = lookup nodeId clusterConfig

-------------------------- Networking ----------------------------------------

maxBytesToRcv = 4096 -- 4KB
maxOutstandingConnections = 30

resolve host port hints  = do
  addr:_ <- getAddrInfo (Just hints) (Just host) (Just port)
  return addr

sendToNode :: NodeId -> DB.ByteString -> IO (Maybe DB.ByteString)
sendToNode nodeId args =
  withSocketsDo $ do
    let nodeAddress = getNodeAddress nodeId
    if isJust nodeAddress then
      do
        let NodeAddress{..} = fromJust nodeAddress
            hints = defaultHints { addrSocketType = Stream }
        addr <- resolve hostName portName hints
        E.bracket (open addr) close talk
    else
      do
        putStrLn $ "Invalid nodeId : " ++ (show nodeId)
        return Nothing
  where
    open addr = do
        sock <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
        connect sock $ addrAddress addr
        return sock
    talk sock = do
        sendAll sock args
        msg <- recv sock maxBytesToRcv
        if DB.null msg then
          return Nothing
        else
          return $ Just DB.empty

-- Opens conncection and starts processing messages
startListening :: [Char] -> [Char] -> IO ()
startListening host port = 
  withSocketsDo $ do
    let hints = defaultHints {
                addrFlags = [AI_PASSIVE]
              , addrSocketType = Stream
              }
    addr <- resolve host port hints
    E.bracket (open addr) close loop
  where
    open addr = do
        sock <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
        setSocketOption sock ReuseAddr 1
        -- If the prefork technique is not used,
        -- set CloseOnExec for the security reasons.
        fd <- fdSocket sock
        setCloseOnExecIfNeeded fd
        bind sock (addrAddress addr)
        listen sock maxOutstandingConnections
        return sock
    loop sock = forever $ do
        (conn, peer) <- accept sock
        void $ forkFinally (handleMsg conn) (\_ -> close conn)

handleMsg conn = do
  byteStringMsg <- recv conn maxBytesToRcv
  let (Right msg) = eitherDecode byteStringMsg :: Either String Message
  rplyMsg <- 
    case msg of
      MRequestVote args -> handleRequestVoteRPC args >>= \res -> return $ encode res
      MAppendEntries args -> handleAppendEntriesRPC args >>= \res -> return $ encode res
      MNewCommand args -> handleNewCommandRPC args >>= \res -> return $ encode res
  sendAll conn rplyMsg

------------------------- START ----------------------------------------------

-- Once server is launched it starts listening to messages from outside (RPCs
-- from fellow servers well as new commands from clients) and begins as a
-- follower
launchServer host port myNodeId = do
  forkIO (startListening host port) >> follow myNodeId


------------------------- RPC/Request handlers --------------------------------

handleNewCommandRPC :: Command -> IO Bool
handleNewCommandRPC arg = do
  st@(NodeState{..}) <- nodeStateMVar >>= takeMVar
  nodeStateMVar >>= (`putMVar` st)
  if rState == LEADER then
    do
      Log lg <- logMVar >>= takeMVar
      logMVar >>= (`putMVar` (Log $ lg ++ [LogEntry arg currentTerm]))
      return True
  else
    return False

handleRequestVoteRPC :: RequestVoteArgs -> IO (RequestVoteResponse)
handleRequestVoteRPC args = do
  curState@(NodeState myTerm votedFor_  _) <- nodeStateMVar >>= takeMVar
  if (myTerm > (term args)) then
    do
      nodeStateMVar >>= (`putMVar` curState)
      return $ RequestVoteResponse myTerm False
  else
    do
      lg <- logMVar >>= takeMVar
      let voteGranted_ = ((votedFor_ == unVote) || (votedFor_ == candidateId args)) &&
                         (isLogUptodate args lg)
      logMVar >>= (`putMVar` lg)
      let newState = if voteGranted_ then 
                        NodeState (term args) (candidateId args) FOLLOWER
                     else
                        curState
      if voteGranted_ then followerChan >>= (`tryPutMVar` ()) else return True
      nodeStateMVar >>= (`putMVar` newState)
      return $ RequestVoteResponse myTerm voteGranted_
  where
    isLogUptodate arg@(RequestVoteArgs{..}) lg = 
      (lastLogTerm > getLastLogTerm lg) ||
      ((lastLogTerm == getLastLogTerm lg) && (lastLogIndex >= getLastLogIndex lg))

handleAppendEntriesRPC :: AppendEntriesArgs -> IO (AppendEntriesResponse)
handleAppendEntriesRPC AppendEntriesArgs{..} = do
  curState@(NodeState myTerm votedFor_  _) <- nodeStateMVar >>= takeMVar
  let newState = if leaderTerm > myTerm then 
                    curState {currentTerm=leaderTerm, rState=FOLLOWER}
                 else
                    curState
  nodeStateMVar >>= (`putMVar` newState)
  lg <- logMVar >>= takeMVar
  let response =
        if | leaderTerm < myTerm -> AppendEntriesResponse myTerm False (LogIndex 0)
           | not $ isValidIndex prevLogIndex lg -> 
                          AppendEntriesResponse myTerm False (getLastLogIndex lg)
           | otherwise -> if (logTerm myEntry) == prevLogTerm then 
                            AppendEntriesResponse myTerm True (getLastLogIndex lg)
                          else
                            AppendEntriesResponse myTerm False (indexToSend lg prevLogTerm) 
        where myEntry = getEntryAt lg prevLogIndex
              isValidIndex indx lg = indx <= getLastLogIndex lg
  if success response then
    do
      let newLog = append (deleteAfter prevLogIndex lg) entries
          newLastIndex = getLastLogIndex newLog
      logMVar >>= (`putMVar` newLog)
      cmtIndx <- commitIndexMVar >>= takeMVar
      commitIndexMVar >>= (`putMVar` (min leaderCommitIndex newLastIndex))
      return response{nextIndexToSend = nextIndex newLastIndex}
  else
    return response
  where
    indexToSend arg@(Log lg) prevTerm = 
      let indx =  snd (fromJust $ find  (\(entry, indx) -> prevTerm == logTerm entry)
                                        (zip lg [0 .. (length lg)-1]))
      in LogIndex (indx - 1)
  
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
  let otherNodeIds = [node | node <- nodeIds, node /= myNodeId]
  quitChans <- mapM (\_ -> newEmptyMVar) otherNodeIds
  mapM_ (\(nodeId, chan) -> async $ do
                      sendVoteRequestTo nodeId args voteCounter myNodeId chan quitChans)
        (zip otherNodeIds quitChans)
  let majority = (div nodesInCluster 2) + 1
  Right res <- race (waitAndBroadcast quitChans) (collectVotes voteCounter 0 1)
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
          res <- sendToNode nodeId $ encode args
          let response = if isJust res then 
                eitherDecode (fromJust res) :: Either String RequestVoteResponse 
                else 
                  Left "Vote Request failed" 
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
lead myNodeId = do
  curState <- nodeStateMVar >>= takeMVar
  nodeStateMVar >>= (`putMVar` curState{rState=LEADER}) 
  let myTerm = currentTerm curState
      otherNodeIds = [node | node <- nodeIds, node /= myNodeId]
  matchIndexMvar <- newMVar $ initMap otherNodeIds (LogIndex 0)
  nextIndexMVar <- newMVar $ initMap otherNodeIds (LogIndex 1)
  quitChans <- mapM (\_ -> newEmptyMVar) otherNodeIds
  mapM_ (\(nodeId, chan) -> async $ sendHeartbeats nodeId chan nextIndexMVar matchIndexMvar myNodeId myTerm) 
        (zip otherNodeIds quitChans)
  qChan <- newEmptyMVar
  async $ updateCommitIndex qChan matchIndexMvar myTerm
  followerChan >>= takeMVar >> broadcast quitChans ()
  return ()

updateCommitIndex :: MVar () -> MVar (HashMap NodeId LogIndex) -> Term -> IO ()
updateCommitIndex qChan matchIndexMvar myTerm = do
  quit <- tryTakeMVar qChan
  if isJust quit then
    return ()
  else
    do 
      matchIndex <- takeMVar matchIndexMvar
      putMVar matchIndexMvar matchIndex
      let indx = sortedIndices !! (majority-2)
          sortedIndices = sortBy (\a b -> compare b a) (elems matchIndex)
          majority = (div nodesInCluster 2) + 1
      myLog <- logMVar >>= takeMVar
      logMVar >>= (`putMVar` myLog)
      if myTerm == (logTerm $ getEntryAt myLog indx) then
        do
          commitIndexMVar >>= takeMVar
          commitIndexMVar >>= (`putMVar` indx)
      else 
        updateCommitIndex qChan matchIndexMvar myTerm

sendHeartbeats :: NodeId -> MVar () -> MVar (HashMap NodeId LogIndex)
                    -> MVar (HashMap NodeId LogIndex) -> NodeId -> Term -> IO ()
sendHeartbeats nodeId qChan nextIndexMVar matchIndexMvar myNodeId myTerm = do
  quit <- tryTakeMVar qChan
  if isJust quit then
    return ()
  else 
    do
      (prevIndx, prevTerm, entrys) <- getLogDetails nextIndexMVar nodeId
      cmtIndx <- commitIndexMVar >>= takeMVar
      commitIndexMVar >>= (`putMVar` cmtIndx)
      let args = AppendEntriesArgs {
                                       leaderTerm = myTerm
                                    ,  leaderId = myNodeId
                                    ,  prevLogIndex = prevIndx
                                    ,  prevLogTerm = prevTerm
                                    ,  entries = entrys
                                    ,  leaderCommitIndex = cmtIndx
                                   }
      timeoutChan <- newEmptyMVar                           
      async $ threadDelay electionTimeout >> putMVar timeoutChan Nothing                             
      id <- async $ sendAHeartbeat nodeId args timeoutChan
      response <- wait id
      if isJust response then
        do
          let AppendEntriesResponse{..} = fromJust response
          if followerTerm > myTerm then
            do
              updateToFollower followerTerm
              followerChan >>= (`tryPutMVar` ())
              return ()   
          else
            do
              nxtIndex <- takeMVar nextIndexMVar
              putMVar nextIndexMVar $ insert nodeId nextIndexToSend nxtIndex
              if success then
                do
                  mtchIndex <- takeMVar matchIndexMvar
                  putMVar matchIndexMvar $ insert nodeId (getPrevIndex nextIndexToSend) mtchIndex
              else
                return ()
              sendHeartbeats nodeId qChan nextIndexMVar matchIndexMvar myNodeId myTerm
      else 
        sendHeartbeats nodeId qChan nextIndexMVar matchIndexMvar myNodeId myTerm
  where
    getLogDetails nextIndexMvar nodeId = do
      nxtIndx <- takeMVar nextIndexMVar
      let indx = (fromJust $ lookup nodeId nxtIndx)
          prevIndx = getPrevIndex indx
      putMVar nextIndexMVar nxtIndx
      lg <- logMVar >>= takeMVar
      let entrys = getEntriesFrom indx lg
          prevTerm = logTerm $ getEntryAt lg prevIndx
      logMVar >>= (`putMVar` lg)
      return (prevIndx, prevTerm, entrys)

sendAHeartbeat :: NodeId -> AppendEntriesArgs -> MVar (Maybe DB.ByteString) -> IO (Maybe AppendEntriesResponse)
sendAHeartbeat nodeId args timeoutChan = do
  v <- tryTakeMVar timeoutChan
  if isJust v then
    return Nothing
  else
    do
      res <- sendToNode nodeId $ encode args
      if isJust res then 
        do
          let (Right response) = eitherDecode (fromJust res) :: Either String AppendEntriesResponse
          return $ Just response
      else 
        sendAHeartbeat nodeId args timeoutChan 