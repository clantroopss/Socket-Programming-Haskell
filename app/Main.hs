module Main where

import Network.Socket
import System.IO
import System.Environment
import Data.List
import Data.List.Split
import Control.Exception
import Control.Monad (when, unless)
import Control.Monad.Fix (fix)
import Control.Concurrent.Chan
import Control.Concurrent
import Control.Concurrent.ParallelIO.Local
import Control.Concurrent.MVar
import qualified Data.HashTable.IO as H

import Lib
import Client

main :: IO ()
main = do
    [port] <- getArgs
    sock <- socket AF_INET Stream 0
    setSocketOption sock ReuseAddr 1
    bind sock (SockAddrInet (toEnum $ read port) iNADDR_ANY)
    let nbThreads = 10
    listen sock (nbThreads*2)
    
    killedChan <- newChan
    htSI           <- H.new :: IO (HashTable String Int)
    htIC           <- H.new :: IO (HashTable Int ChatRoom)
    htClients      <- H.new :: IO (HashTable Int Client)
    htClientsNames <- H.new :: IO (HashTable String Int)
    
    chatRooms <- newMVar (ChatRooms {chatRoomFromId=htIC, chatRoomIdFromName=htSI, numberOfChatRooms=0})
    clients <- newMVar (Clients 0 htClients htClientsNames)
    withPool nbThreads $ 
        \pool -> parallel_ pool (replicate nbThreads (server sock port killedChan clients chatRooms))
    logg "Stopping Server and kill Clients "

server :: Socket -> String -> Chan Bool -> MVar Clients -> MVar ChatRooms -> IO ()
server sock port killedChan clients chatrooms = do
    logg "Waiting for Clients..."
    conn <- try (accept sock) :: IO (Either SomeException (Socket, SockAddr))
    case conn of
        Left  _    -> logg "Socket is now closed. Exiting."
        Right conn -> do
            logg "Client Joined!"
            runClient conn sock port killedChan clients chatrooms
            server sock port killedChan clients chatrooms

loopClient :: Handle -> Socket -> String -> Chan Bool -> MVar Clients -> MVar ChatRooms -> [Int] -> IO ()
loopClient hdl originalSocket port killedChan clients chatrooms joinIds = do
    (kill, timedOut, input) <- waitForInput hdl killedChan 0 joinIds clients
    when (timedOut) (logg "Time out due to inactivity")
    when (kill || timedOut) (return ())
    let message = splitOn " " input
    let command = head message
    let args = intercalate " " $ tail message
    case command of
        "HELO"            -> do
            helo hdl args port
            loopClient hdl originalSocket port killedChan clients chatrooms joinIds
        "JOIN_CHATROOM:"  -> do
            (error, id) <- join hdl args port clients chatrooms
            if error then return ()
            else do
                if id `elem` joinIds then loopClient hdl originalSocket port killedChan clients chatrooms joinIds
                else loopClient hdl originalSocket port killedChan clients chatrooms (id:joinIds)
        "LEAVE_CHATROOM:" -> do
            (error, id) <- leave hdl args clients
            if error then return ()
            else do
                loopClient hdl originalSocket port killedChan clients chatrooms (delete id joinIds)
        "DISCONNECT:"     -> do
            error <- disconnect hdl args clients
            unless error (loopClient hdl originalSocket port killedChan clients chatrooms joinIds)
        "CHAT:"           -> do
            error <- chat hdl args clients
            unless error (loopClient hdl originalSocket port killedChan clients chatrooms joinIds)
        "KILL_SERVICE"    -> do
            writeChan killedChan True
            threadDelay 100000
            killService originalSocket
        _                 -> otherCommand hdl input


runClient :: (Socket, SockAddr) -> Socket -> String -> Chan Bool -> MVar Clients -> MVar ChatRooms -> IO ()
runClient (sock, addr) originalSocket port killedChan clients chatrooms = do
    hdl <- socketToHandle sock ReadWriteMode
    hSetBuffering hdl LineBuffering
    handle (\(SomeException _) -> return ()) $ fix $ (\loop -> (loopClient hdl originalSocket port killedChan clients chatrooms []))
    hClose hdl
    logg "Client disconnected"