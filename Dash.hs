{-# LANGUAGE OverloadedStrings #-}

module Dash where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as C
import Data.Maybe
import Data.List
import qualified Data.HashMap.Strict as M
import Control.Concurrent
import Control.Monad
import Control.Monad.IO.Class
import System.Console.Haskeline
import System.Environment

import Network.Connection
import Network.Node
import Transaction
import Block


-- -----------------------------------------------------------------------------
-- Dash is a Command Line Interface that helps interact with Lambda-Chain

-- | Define Type of Commands
data Cmd = Conn String String
         | Mine
         | Peers
         | Block_ Int
         | BlockHeight
         | Tx_Pool
         | Txn String Int
         | Raw String
         deriving (Show, Eq)

-- | Parse from input -> Command Type         
toCmd :: Maybe String -> Cmd
toCmd Nothing = Raw "Nothing"
toCmd (Just input)
    | isInfixOf "connect"  input = Conn (head args) (last args)
    | isInfixOf "transfer" input = Txn  (head args) (read $ last args :: Int)
    | isInfixOf "mine"     input = Mine
    | isInfixOf "peers"    input = Peers
    | isInfixOf "tx-pool"  input = Tx_Pool
    | isInfixOf "block"    input = Block_ (read $ head args :: Int)
    | isInfixOf "height"   input = BlockHeight
    | otherwise = Raw input
    where args = tail $ words input

-- | The REPL interface
-- dash :: PortNumber -> IO ()
dash p2p_port = do
    node <- go_live p2p_port
    runInputT defaultSettings $ loopCmd node

loopCmd :: NodeState -> InputT IO ()
loopCmd st = do
    minput <- getInputLine "> "
    case toCmd minput of
        Conn h p -> liftIO $ do
            sock <- connect_ (h, p)
            modifyMVarMasked_ (_peers st) $ \lst -> return $ sock:lst
        Peers    -> liftIO $ tryReadMVar (_peers st) >>= print
        Tx_Pool  -> liftIO $ tryReadMVar (_pool st)  >>= print
        Txn a m  -> liftIO $ do
            socks   <- tryReadMVar (_peers st)
            maybeTx <- send_to (C.pack a) m
            case maybeTx of
                Nothing -> print "invalid Tx"
                Just tx -> do
                    modifyMVarMasked_ (_pool st) $ \txs -> return $ expand_pool tx txs
                    sendNetwork (fromJust socks) (C.append "txn:" (showBS tx))
        Mine     -> liftIO $ do
            txs <- tryReadMVar (_pool st)
            block <- mine_block $ fromJust txs
            print "A new block was mined, sending to network.."
            print block
            socks <- tryReadMVar (_peers st)
            sendNetwork (fromJust socks) (C.append "block:" (showBS block))
        Block_ i -> liftIO $ do
            block <- find_by_index $ C.append "block#" (showBS i)
            print block
        BlockHeight -> liftIO $ block_height >>= print
        Raw m    -> liftIO $ do
            socks <- tryReadMVar (_peers st)
            sendNetwork (fromJust socks) (C.pack m)    
    loopCmd st
