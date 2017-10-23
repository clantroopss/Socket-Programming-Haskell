--importing libraries
{-# LANGUAGE RecordWildCards #-}
import System.IO
import Data.Map (Map)
import qualified Data.Map as Map
import Text.Printf
import Network
import Control.Concurrent
import Control.Concurrent.STM
import Control.Monad


--Defining student identification value
type StudentId = Int
type StudentName = String

--Defining properties of student
data Student = Student
  { studentId     :: StudentId,
    studentName   :: StudentName,
    studentHandle :: Handle,
    studentChan   :: TChan Message
  }

--defining message for studentChan
data Message = Notice String
             | Tell StudentName String
             | Broadcast StudentName String
             | Command String

--new instance of participants
newParticipant :: StudentId -> StudentName -> Handle -> STM Student
newParticipant id name handle = do
  n <- newTChan
  return Student { studentId     = id
                 , studentName   = name
                 , studentHandle = handle
                 , studentChan   = n
                 }

--sending a message to a given client
sendMessage :: Student -> Message -> STM ()
sendMessage Student{..} msg =
  writeTChan studentChan msg


--data structure that stores the sserver state
data Server = Server
  { participants :: TVar (Map StudentName Student)
  }

initServer :: IO Server
initServer = do
  n <- newTVarIO Map.empty
  return Server {participants = n}

broadcast :: Server -> Message -> STM ()
broadcast Server{..} msg = do
  participantmap <- readTVar participants
  mapM_ (\participant -> sendMessage participant msg) (Map.elems participantmap)


main :: IO ()
main = withSocketsDo $ do
  server <- initServer
  sock <- listenOn (PortNumber (fromIntegral port))
  printf "Listening on port %d\n" port
  forever $ do
      (handle, host, port) <- accept sock
      printf "Accepted connecteion from %s: %s\n" host (show port)
      --forkFinally (talk handle server) (\_ -> hClose handle)

port :: Int
port = 50000
      
