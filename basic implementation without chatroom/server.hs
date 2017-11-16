import Control.Concurrent
import Control.Monad
import Text.Printf
import System.IO
import Network
import Network.Socket.Internal

receive :: Handle -> TChan String  -> IO ()
receive h c =  forever $do
  line <- hGetLine h
  atomically $ writeTChan c line

server :: Handle -> TVar Integer -> TChan String -> IO ()
server h factor c = do
  f <- atomically $ readTVar factor
  hPrintf h "Current factor: %d\n" f
  loop f
   where  loop f = do
    action <- atomically $ do
      f' <- readTVar factor
      if (f /= f')
         then return (newfactor f')
         else do
           l <- readTChan c
           return (command f l)
    action
    newfactor f = do
      hPrintf h "new factor: %d\n" f
      loop f

    command f s
     = case s of
        "end" ->
           hPutStrLn h ("Thank you for using chat server ")
        '*':s -> do
          atomically $ writeTVar factor (read s :: Integer)
          loop f
        line  -> do
          hPutStrLn h (show (f * (read line :: Integer)))
          loop f


talk :: Handle -> TVar Integer -> IO ()
talk h factor = do
 hSetBuffering h LineBuffering
 c <- atomically newTChan
-- race is used to create sibling relationship between two thread
 race (server h factor c) (receive h c)
 return ()
 loop
 where
  loop = do
   line <- hGetLine h
   if line == "end"
      then hPutStrLn h ("Thank you for using chat server")
      else do hPutStrLn h ("Bad Command")
              loop

main = withSocketsDo $ do
 sock <- listenOn (PortNumber (fromIntegral port))
 printf "Listening on port %d\n" port
 factor <- atomically $ newTVar 2
 forever $ do
    (handle, host,port) <- accept sock
    printf "Accepted connection from %s: %s\n" host (show port)
    forkFinally (talk handle factor) (\_ -> hClose handle)

port :: Int
port = 44444
