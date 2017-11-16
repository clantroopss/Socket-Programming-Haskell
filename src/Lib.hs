module Lib where

import Network.BSD
import System.IO
import System.Directory
import Control.Exception
import Control.Monad.Fix (fix)
import Control.Concurrent.Chan
import Control.Concurrent
import Data.IP
import Data.List
import qualified Data.Maybe as M
import Data.String.Utils
import Foreign.Ptr
import Foreign.C.String
import Foreign.C.Types
import Foreign.Marshal.Alloc (mallocBytes, free)
import qualified Data.HashTable.IO as H

type HashTable k v = H.CuckooHashTable k v

-- Client data structure
data Client    = Client { clientName :: String
                        , subs       :: HashTable Int (Chan String)
                        , joinId     :: Int
                        }
data Clients   = Clients { lastClientId   :: Int
                         , theClients     :: HashTable Int Client
                         , clientsNames   :: HashTable String Int
                         }

-- Chatroom data structure
data ChatRoom  = ChatRoom Int (Chan String)
data ChatRooms = ChatRooms { chatRoomFromId     :: HashTable Int ChatRoom
                           , chatRoomIdFromName :: HashTable String Int
                           , numberOfChatRooms  :: Int  
                           }

getWaitBySocket :: Int
getWaitBySocket = 60000

nonBlockingRead :: Handle -> String -> IO String
nonBlockingRead hdl currentS = do
  buf <- mallocBytes 4096 :: IO (Ptr CChar)
  nbRead <- hGetBufNonBlocking hdl buf 4096 
  request <- peekCStringLen (buf, nbRead)
  free buf
  if nbRead == 0 then do
    threadDelay getWaitBySocket
    return currentS
  else do
    next <- nonBlockingRead hdl (currentS ++ request)
    return next

readChansClient :: [(String, Int)] -> (Int, Chan String) -> IO [(String, Int)]
readChansClient current (ref, chan) = do
  canPass <- isEmptyChan chan
  if canPass then return current
  else do
    toSend <- readChan chan
    return ((toSend, ref):current)

unpackAndReadChansClient :: Handle -> MVar Clients -> Int -> IO ()
unpackAndReadChansClient hdl clients joinId = do
  (Clients lastClientId theClients clientsNames) <- takeMVar clients
  maybeClient <- H.lookup theClients joinId
  let (Client _ channels _) = M.fromJust maybeClient
  messages <- H.foldM readChansClient [] channels
  let messagesStr = map (\(m,ref) -> m) $ sortOn (\(m,ref) -> ref) messages
  mapM_ (sendResponse hdl) messagesStr
  putMVar clients (Clients lastClientId theClients clientsNames)

readChans :: Handle -> [Int] -> MVar Clients -> IO ()
readChans hdl joinIds clients = do
  mapM_ (unpackAndReadChansClient hdl clients) joinIds

waitForInput :: Handle -> Chan Bool -> Int -> [Int] -> MVar Clients -> IO (Bool, Bool, String)
waitForInput hdl killedChan waitingTime joinIds clients = do
  let socketTimedOut = waitingTime > getWaitBySocket*100
  if socketTimedOut then (return (False, True, ""))
  else do
    stillAlive <- isEmptyChan killedChan
    if stillAlive then do
      readChans hdl joinIds clients
      request <- handle (\(SomeException _) -> return "") $ fix $ (return $ nonBlockingRead hdl "")
      if null request then do
        res <- waitForInput hdl killedChan (waitingTime + getWaitBySocket) joinIds clients
        return res
      else do
        return (False, False, clean request)
    else return (True, False, [])

sendResponse :: Handle -> String -> IO ()
sendResponse hdl resp = do
    hSetBuffering hdl $ BlockBuffering $ Just (length resp)
    hPutStr hdl resp

getClientName :: IO String
getClientName = do
    host <- (getHostName >>= getHostByName)
    return $ show $ fromHostAddress $ head $ hostAddresses host

clean :: String -> String
clean input = init input

sendLeaveMessages :: String -> [(String, Chan String, Int)] -> (Int, Chan String) -> IO [(String, Chan String, Int)]
sendLeaveMessages clientName currentRes (chatRoomRef, chan) = do
  let message = "CHAT: " ++ (show chatRoomRef) ++ "\nCLIENT_NAME: " ++ clientName ++ "\nMESSAGE: " ++ clientName ++ " has left this chatroom.\n\n"
  return (currentRes ++ [(message, chan, chatRoomRef)])


sendError :: Handle -> Int -> String -> IO ()
sendError hdl errorCode errorString = sendResponse hdl $ "ERROR_CODE: " ++ (show errorCode) ++ "\nERROR_DESCRIPTION: " ++ errorString

logg :: String -> IO ()
logg s = putStrLn $ "\n" ++ s
