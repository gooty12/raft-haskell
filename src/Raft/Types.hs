{-# Language DeriveGeneric, DefaultSignatures #-}

module Raft.Types where

import Data.List
import Data.HashMap.Strict
import GHC.Generics -- derive generic??
import Data.Hashable

data RAFTState = RAFTState {
    currentTerm :: Term,
    votedFor :: NodeId,
    rLog :: Log,
    commitIndex :: LogIndex,
    lastApplied :: LogIndex,
    nextIndex :: HashMap NodeId LogIndex,
    matchIndex :: HashMap NodeId LogIndex
} deriving (Show)

newtype Term = Term Int deriving (Show, Generic, Eq)

newtype NodeId = NodeId Int deriving (Show, Generic, Eq)
instance Hashable NodeId

data NodeAddress = NodeAddress {  hostName :: [Char],
                                  portName :: [Char]
                               } deriving(Show, Generic, Eq)

-- define append, getLogEntry, removeFrom on Log
newtype Log = Log [LogEntry] deriving (Show, Generic)
newtype LogIndex = LogIndex Int deriving (Show, Generic, Eq)
newtype LogEntry = LogEntry {logCmd :: Command} deriving (Show, Generic, Eq)

newtype Command = Command {cmd :: Int} deriving (Show, Generic, Eq)

data Message = 
    MRequestVote { requestVoteArgs :: RequestVoteArgs}
  | MAppendEntries { appendEntriesArgs :: AppendEntriesArgs}
  | MNewCommand { newCmd :: Command } deriving (Show, Generic)

--instance Serialize Message

data RequestVoteArgs = RequestVoteArgs {
  term :: Term,
  candidateId :: NodeId,
  lastLogTerm :: Term,
  lastLogIndex :: LogIndex
} deriving (Show, Eq, Generic)

data RequestVoteResponse = RequestVoteResponse {
  voterTerm :: Term,
  voteGranted :: Bool
} deriving (Show, Eq, Generic)

data AppendEntriesArgs = AppendEntriesArgs {
  leaderTerm :: Term,
  leaderId :: NodeId,
  prevLogIndex :: LogIndex,
  prevLogTerm :: Term,
  entries :: Log,
  leaderCommitIndex :: LogIndex
} deriving (Show, Generic)

data AppendEntriesResponse = AppendEntriesResponse {
  followerTerm :: Term,
  success :: Bool
}


