__raft-haskell__ is an attempt to implement [RAFT consensus protocol] (https://raft.github.io/) in Haskell. The larger goal of the project is to learn how to build distributed systems in a functional language namely Haskell. Haskell's powerful type system and its robust concurrency primitives and constructs makes both developing and reasoning about distributed systems much easier.


# RAFT
Distributed sysetms replicate their data on multiple servers - if one server crashes another (replica) server can serve client requests. It is imperative that all the servers store the same data and perform the operations in same order in order to look consistent to the outside world. RAFT can help reach a consensus among the servers in this case. 

RAFT, as we shall see, is simple and intuitive unlike PAXOS which is hard to understand and implement. RAFT is widely used in real world too. For example, __Kubernetes__ [uses](https://github.com/kubernetes/kubernetes/tree/master/vendor/github.com/coreos/etcd/raft) RAFT internally for its _etcd_ datastore that stores all the configuration info and metadata. Redis uses some of the ideas presented in RAFT.

# RAFT - simply and intuitively

RAFT is very intutitive because it uses some of the most common ideas seen in our daily life. Decisions in RAFT are taken by a leader. A server that receives majority votes can act as a leader. Any decision by the leader is made only after approval from a majority of servers.

A server in RAFT operates in one of these states at all times - Follower, Candidate, or Leader.

__FOLLOWER :__ A follower receives and responds to requests from other severs. When a new command comes from a client leader sends requests to the followers for agreement. If the follower doesn't hear from the leader for a duration, called heartbeat interval, it promotes itself as a Candidate and starts contesting for the next _term_. Note that the leader may have to send empty requests during idle (no new commands from clients) periods to prevent followers from contesting.

__CANDIDATE :__ Candidates send vote requests to all the servers. A follower gives its vote only if the candidate is at least as up to date (explained below) as itself. Upon receiving majority votes, candidate becomes leader. In case of split votes, candidate waits for a random time period, allowing others to contest, and recontests only if it hasn't still heard from any leader.

__LEADER :__  A Leader is the only one that accepts new commands from clients. The leader sends out AppendEntries requests asking the followers to append new commands to their own logs. If a majority agree the entries are considered _committed_. Committed entries should never be lost because from a client's (i.e. outside world) perspective they are permanent and cannot be undone. 

A Follower accepts a new command request from Leader only if the immediately preceding entry in its log matches that of the leader's. Until this condition is met follower keeps rejecting leader's request. Once the condition is met, all the entries after that match index are deleted and the new entries from leader are appended. Thus if the leader is not chosen correctly we may delete even the committed entries from the follower's logs. How do we prevent this??

To avoid this we elect only the most uptodate canidate as leader. Let's say that we have 100 committed entries. A server __C__ that has only 10 entries cannot become leader because of the following simple reason. Since an entry is committed only if it's replicated on a majority we know that some majority of the servers have 100 entries at least. Thus server__C__ cannot become leader as this majority is going to turn down its vote request.

Although it's an over simplification this is all the reasoning behind RAFT's correctness. For a more detailed explanation read this [RAFT paper] (https://raft.github.io/raft.pdf).





