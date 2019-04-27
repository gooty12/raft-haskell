module Lib
    ( someFunc
    ) where

import Raft.Server

--- read host, port and node id (a number), then launch server
someFunc :: IO ()
someFunc = do
  putStrLn "Input server/host name:"
  host <- getLine
  putStrLn "Input  server/host port:"
  port <- getLine
  startListening host port
