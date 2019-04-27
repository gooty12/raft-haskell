__raft-haskell__ is an attempt to implement RAFT consensus protocol in Haskell. The larger goal of the project is to learn how to build distributed systems in a functional language namely Haskell. Haskell's powerful type system and its robust concurrency primitives and constructs makes both developing and reasoning about distributed systems much easier.


# RAFT
Distributed sysetms replicate their data on multiple servers so that if one server carshes you have another (replica) server to service the client requests. It is imperative that all the replicas store the same data and perform the operations in same order in order to look consistent to the outside world. This is where RAFT can help. RAFT is an algorithm that is used in distributed systems to reach a consensus. 

RAFT, as we shall see, is simple and intuitive unlike PAXOS which is hard to understand and implement. RAFT is heavily used in real world too. For example, __Kubernetes__ [uses](https://github.com/kubernetes/kubernetes/tree/master/vendor/github.com/coreos/etcd/raft) RAFT protocol internally for its _etcd_ datastore that stores all the configuration info and metadata. Redis also uses some of the ideas presented in RAFT.

# RAFT - simply and intuitively

RAFT is simple to understand because it uses only the ideas that we see in our daily life, nothing fancy. Decisions in RAFT are taken by a leader who is an elected representative of all the participating servers. The leader has to consult all the servers and get approval from a majority before making any decision. In fact a leader himself is elected only if majority say so.

A server in RAFT operates in one of these states at all times - Follower, Candidate, or Leader.

__FOLLOWER :__ A follower listens to requests from leaders and other severs. Leaders send new decision/command requests to clients for agreement. If a follower doesn't hear from the leader for a duration, called heartbeat interval, it promotes itself as a Candidate and starts contesting for the next _term_ or round of elections.

__CANDIDATE :__ Candidates send vote requests to all the servers. A follower gives its vote only if the candidate is at least as up to date as itself. Upon receiving a majority votes, candidate becomes leader. In case of split votes, candidate waits for a random time period, allowing others to contest, and recontests if it hasn't still heard from any leader.

__LEADER :__  A Leader is the only one that accepts new commands from clients. The leader sends out AppendEntries requests asking the followers to append new commands to their own logs. If a majority agree the entries are considered _committed_. Committed entries should never be lost because from a client's (i.e. outside world) perspective they are permanent and cannot be undone. How do we guarantee this??

A Follower accept a new command request from Leader only if the immediately preceding entry in its log matches that of the leader's. Until this condition is met follower keeps rejecting leader's request. Once the condition is met, all the entries after that match index are deletd and the new entries from leader are appended. Thus if the leader is not chosen correctly we may delete even the committed entries from the follower's logs.

To avoid this we elect only the most uptodate canidate as leader. Let's say that we have 100 committed entries. A server _C_ that has only 10 entries cannot become leader because of the following simple reason. Since an entry is committed only if it's replicated on a majority you can be sure that this majority is going to turn down server _C_'s vote request. Thus server _C_ can never become leader.





