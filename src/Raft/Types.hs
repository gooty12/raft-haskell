{-# Language DeriveGeneric, DefaultSignatures #-}

module Raft.Types where

import Data.List
import Data.HashMap.Strict
import GHC.Generics
import Data.Hashable
import Data.Aeson (FromJSON, ToJSON)

data NodeState = NodeState {
    currentTerm :: Term,
    votedFor :: NodeId,
    rLog :: Log,
    commitIndex :: LogIndex,
    lastApplied :: LogIndex,
    nextIndex :: HashMap NodeId LogIndex,
    matchIndex :: HashMap NodeId LogIndex,
    rState :: RAFTState
} deriving (Show)

data RAFTState = FOLLOWER | LEADER | CANDIDATE deriving (Show, Generic, Eq)

newtype Term = Term Int deriving (Show, Generic, Eq)

instance ToJSON Term
instance FromJSON Term

newtype NodeId = NodeId Int deriving (Show, Generic, Eq)
instance Hashable NodeId
instance ToJSON  NodeId
instance FromJSON NodeId

data NodeAddress = NodeAddress {  hostName :: [Char],
                                  portName :: [Char]
                               } deriving(Show, Generic, Eq)

-- define append, getLogEntry, removeFrom on Log
newtype Log = Log [LogEntry] deriving (Show, Generic)

instance ToJSON Log
instance FromJSON Log

newtype LogIndex = LogIndex Int deriving (Show, Generic, Eq)

instance ToJSON LogIndex
instance FromJSON LogIndex

data LogEntry = LogEntry {logCmd :: Command,
                          logTerm :: Term} deriving (Show, Generic, Eq)
instance ToJSON LogEntry
instance FromJSON LogEntry

newtype Command = Command {cmd :: Int} deriving (Show, Generic, Eq)

instance ToJSON Command
instance FromJSON Command

data Message = 
    MRequestVote { requestVoteArgs :: RequestVoteArgs}
  | MAppendEntries { appendEntriesArgs :: AppendEntriesArgs}
  | MNewCommand { newCmd :: Command } deriving (Show, Generic)

instance ToJSON Message
instance FromJSON Message

--instance Serialize Message

data RequestVoteArgs = RequestVoteArgs {
  term :: Term,
  candidateId :: NodeId,
  lastLogTerm :: Term,
  lastLogIndex :: LogIndex
} deriving (Show, Eq, Generic)

instance ToJSON RequestVoteArgs
instance FromJSON RequestVoteArgs

data RequestVoteResponse = RequestVoteResponse {
  voterTerm :: Term,
  voteGranted :: Bool
} deriving (Show, Eq, Generic)

instance ToJSON RequestVoteResponse
instance FromJSON RequestVoteResponse

data AppendEntriesArgs = AppendEntriesArgs {
  leaderTerm :: Term,
  leaderId :: NodeId,
  prevLogIndex :: LogIndex,
  prevLogTerm :: Term,
  entries :: Log,
  leaderCommitIndex :: LogIndex
} deriving (Show, Generic)

instance ToJSON AppendEntriesArgs
instance FromJSON AppendEntriesArgs

data AppendEntriesResponse = AppendEntriesResponse {
  followerTerm :: Term,
  success :: Bool
} deriving (Show, Eq, Generic)

instance ToJSON AppendEntriesResponse
instance FromJSON AppendEntriesResponse


