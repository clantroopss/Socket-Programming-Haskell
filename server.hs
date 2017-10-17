import Control.Concurrent
import Control.Monad
import Text.Printf
import System.IO
import Network
import Network.Socket.Internal

talk :: Handle -> IO ()
talk h = do
 hSetBuffering h LineBuffering
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
 forever $ do
    (handle, host,port) <- accept sock
    printf "Accepted %s: %s\n" host (show port)
    forkFinally (talk handle) (\_ -> hClose handle)

port :: Int
port = 44444
