__raft-haskell__ is an attempt to implement [RAFT consensus protocol](https://raft.github.io/) in Haskell. The larger goal of the project is to learn how to build distributed systems in a functional language namely Haskell. Haskell's powerful type system and its robust concurrency primitives and constructs makes both developing and reasoning about distributed systems much easier.


# RAFT
Distributed sysetms replicate their data on multiple servers - if one server crashes another (replica) server can serve client requests. It is imperative that all the servers store the same data and perform the operations in same order in order to look consistent and logical to the outside world. RAFT can help reach consensus among the servers in this case. 

RAFT, as we shall see, is simple and intuitive unlike PAXOS which is hard to understand and implement. RAFT is widely used in real world too. For example, __Kubernetes__ [uses](https://github.com/kubernetes/kubernetes/tree/master/vendor/github.com/coreos/etcd/raft) RAFT internally for its _etcd_ datastore that stores all the configuration info and metadata. Redis uses some of the ideas presented in RAFT.

# RAFT - simply and intuitively

Decisions in RAFT are taken by a leader. Any server that receives majority votes can become leader. Any decision by the leader is made only if a majority of the servers approve. Decision can be any command/request from clients. For a distributed Key-Value datastore, the decision can either be a _get_ or a _put_ command issued by client.

A server in RAFT operates in one of the three states at all times - Follower, Candidate, or Leader.

__FOLLOWER :__ A follower receives and responds to new command requests from Leader. If it doesn't receive requests from the leader for some duration, called heartbeat interval, it assumes the leader is dead and promotes itself as a Candidate and starts contesting for the next _term_. To prevent the followers from contesting leader may have to send (dummy) requests even if there are no new command requests from clients.

__CANDIDATE :__ Candidates send vote requests to other servers. Upon receiving majority votes, candidate becomes leader. In case of split votes, candidate waits for a random time period to allow others to contest and recontests only if there's still no leader elected.

__LEADER :__  A Leader is the only one that accepts new commands/entries from clients. The leader sends out requests, called AppendEntries, asking the followers to append new entries to their own logs. If a majority agree the entries are considered _committed_, so they're applied to the state machine (i.e. written to the database), and  client's request is successfully completed. Committed entries should never be lost because from a client's (i.e. outside world) perspective they are permanent and cannot be undone. 

Followers do not always accept to append new entries though. They do so only if the preceding entries in the log match with the leader's log. If not they delete entries starting from the first unmatched entry, and append the entries sent by the leader. Thus every follower eventually updates its log to match that of leader's. There is one problem though. What if committed entries get deleted? This can happen if we elect a leader that is not up to date.

Let's say that we have 100 committed entries. A server __C__ that has only 10 entries, if elected as leader, would delete the last 90 committed entries. Server __C__ can be stopped from becoming leader by making the follower give its vote only if the candidate is at least uptodate as itself. Since an entry is committed only if it is replicated on a majority we know that some majority of the servers have 100 entries at least. Thus this majority is going to turn down server __C__'s vote request and __C__ can not become leader.

Although it's an over simplification this is all the reasoning behind RAFT's correctness. For a more detailed explanation read this [RAFT paper](https://raft.github.io/raft.pdf).





