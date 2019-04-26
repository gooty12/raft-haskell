__raft-haskell__ is an implementation of RAFT consensus protocol in Haskell. The goal of the project is to learn how to build distributed systems in a functional language namely Haskell. Haskell's support for concurrent programming is both robust and extensive. It's design is heavily influenced by Erlang, another language that is renowned for its support for building scalable, fault-tolerant distributed software.


# RAFT

RAFT is a protocol/agorithm used in distributed environments where multiple servers performing some (distributed) task have to reach a consensus. A typical use case would be replicating data on multiple servers. To achieve fault-tolerance distributed sysetms replicate their data on multiple servers so that if one server carshes you have another (replica) server to service the client requests. It is imperative that all the replicas store the same data and perform the operations in same order in order to look consistent to the outside world. RAFT is used to achieve this. For a real world example, etcd datastore which stores all the configuration and metadata of __Kubernetes__ [uses](https://github.com/kubernetes/kubernetes/tree/master/vendor/github.com/coreos/etcd/raft) RAFT protocol.

# RAFT - simply and intuitively

A simple approach to reaching consensus when there is a possibility for different opinions is to just accept what the majority accept. RAFT also does the same. In order to perform/commit any operation a majority of the severs need to accept that particular operation. To facilitate this RAFT elects a Leader and the Leader is the only server that accepts commands from the clients. Given a command, a leader appends the command to its own log first and then sends the command to other servers (followers) asking them to append it to their respective logs. If a majority of followers accept, the command is considered committed and appropriate reply is sent to the client by the leader.

Leader in RAFT is elected, once again, using the majority approach. A contestant (called Candidate in RAFT) becomes Leader upon receieving votes from majority of the servers. Once elected the leader sends RPCs, known as AppendEntriesRPC, to followers in order to commit new entries and also to bring outdated or crashed servers up to date. AppendEntriesRPCs are also sent out to establish its leadership during idle periods
