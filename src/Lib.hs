module Lib
    ( someFunc
    ) where

import Raft.Types
import Raft.Server

someFunc :: IO ()
someFunc = putStrLn "someFunc"
