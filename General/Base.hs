{-# LANGUAGE BangPatterns, CPP, ScopedTypeVariables #-}

module General.Base(
    Duration, duration, Time, diffTime, offsetTime, offsetTimeIncrease, sleep,
    intToDouble, floatToDouble, doubleToFloat,
    isWindows, getProcessorCount,
    readFileStrict, readFileUCS2, getEnvMaybe, captureOutput, getExePath,
    randomElem,
    showDP, showTime,
    modifyIORef'', writeIORef'',
    isLeft_, isRight_,
    swap,
    whenJust, loopM, whileM, partitionM, concatMapM, mapMaybeM, liftA2', retry,
    ifM, notM, (&&^), (||^),
    fastNub, showQuote, word1,
    withBufferMode, withCapabilities
    ) where

import Control.Applicative
import Control.Arrow
import Control.Concurrent
import Control.Exception as E
import Control.Monad
import Data.Char
import Data.IORef
import Data.List
import Data.Maybe
import Data.Time
import qualified Data.HashSet as Set
import Numeric
import System.Directory
import System.Environment
import System.IO
import System.IO.Error
import System.IO.Unsafe
import System.Random
import GHC.IO.Handle(hDuplicate,hDuplicateTo)
import Development.Shake.Classes
import Foreign.C.Types


---------------------------------------------------------------------
-- Data.Time

type Time = Double -- how far you are through this run, in seconds

diffTime :: UTCTime -> UTCTime -> Duration
diffTime end start = fromRational $ toRational $ end `diffUTCTime` start

-- | Call once at the start, then call repeatedly to get Time values out
offsetTime :: IO (IO Time)
offsetTime = do
    start <- getCurrentTime
    return $ do
        end <- getCurrentTime
        return $ diffTime end start

-- | Like offsetTime, but results will never decrease (though they may stay the same)
offsetTimeIncrease :: IO (IO Time)
offsetTimeIncrease = do
    t <- offsetTime
    ref <- newIORef 0
    return $ do
        t <- t
        atomicModifyIORef ref $ \o -> let m = max t o in m `seq` (m, m)


type Duration = Double -- duration in seconds

duration :: IO a -> IO (Duration, a)
duration act = do
    time <- offsetTime
    res <- act
    time <- time
    return (time, res)


sleep :: Duration -> IO ()
sleep x = threadDelay $ ceiling $ x * 1000000


---------------------------------------------------------------------
-- Numeric

intToDouble :: Int -> Double
intToDouble = fromInteger . toInteger

floatToDouble :: Float -> Double
floatToDouble = fromRational . toRational

doubleToFloat :: Double -> Float
doubleToFloat = fromRational . toRational


---------------------------------------------------------------------
-- Data.IORef

-- Two 's because GHC 7.6 has a strict modifyIORef
modifyIORef'' :: IORef a -> (a -> a) -> IO ()
modifyIORef'' ref f = do
    x <- readIORef ref
    writeIORef'' ref $ f x

writeIORef'' :: IORef a -> a -> IO ()
writeIORef'' ref !x = writeIORef ref x


---------------------------------------------------------------------
-- Data.List

-- | Like 'nub', but the results may be in any order.
fastNub :: (Eq a, Hashable a) => [a] -> [a]
fastNub = f Set.empty
    where f seen [] = []
          f seen (x:xs) | x `Set.member` seen = f seen xs
                        | otherwise = x : f (Set.insert x seen) xs


showQuote :: String -> String
showQuote xs | any isSpace xs = "\"" ++ concatMap (\x -> if x == '\"' then "\"\"" else [x]) xs ++ "\""
             | otherwise = xs


word1 :: String -> (String, String)
word1 x = second (dropWhile isSpace) $ break isSpace $ dropWhile isSpace x


---------------------------------------------------------------------
-- Data.String

showDP :: RealFloat a => Int -> a -> String
showDP n x = a ++ (if n > 0 then "." else "") ++ b ++ replicate (n - length b) '0'
    where (a,b) = second (drop 1) $ break (== '.') $ showFFloat (Just n) x ""

showTime :: Double -> String
showTime x | x >= 3600 = f (x / 60) "h" "m"
           | x >= 60 = f x "m" "s"
           | otherwise = showDP 2 x ++ "s"
    where
        f x m s = show ms ++ m ++ ['0' | ss < 10] ++ show ss ++ m
            where (ms,ss) = round x `divMod` 60


---------------------------------------------------------------------
-- Data.Either

isLeft_, isRight_ :: Either a b -> Bool
isLeft_ Left{} = True; isLeft_ Right{} = False
isRight_ = not . isLeft_


---------------------------------------------------------------------
-- Data.Tuple

swap :: (a, b) -> (b, a)
swap (a, b) = (b, a)


---------------------------------------------------------------------
-- Control.Monad

whenJust :: Monad m => Maybe a -> (a -> m ()) -> m ()
whenJust (Just a) f = f a
whenJust Nothing f = return ()

loopM :: Monad m => (a -> m (Either a b)) -> a -> m b
loopM act x = do
    res <- act x
    case res of
        Left x -> loopM act x
        Right v -> return v

whileM :: Monad m => m Bool -> m ()
whileM act = do
    b <- act
    when b $ whileM act

concatMapM :: Monad m => (a -> m [b]) -> [a] -> m [b]
concatMapM f xs = liftM concat $ mapM f xs

partitionM :: Monad m => (a -> m Bool) -> [a] -> m ([a], [a])
partitionM f [] = return ([], [])
partitionM f (x:xs) = do
    t <- f x
    (a,b) <- partitionM f xs
    return $ if t then (x:a,b) else (a,x:b)

mapMaybeM :: Monad m => (a -> m (Maybe b)) -> [a] -> m [b]
mapMaybeM f xs = liftM catMaybes $ mapM f xs

liftA2' :: Applicative m => m a -> m b -> (a -> b -> c) -> m c
liftA2' a b f = liftA2 f a b

ifM :: Monad m => m Bool -> m a -> m a -> m a
ifM b t f = do b <- b; if b then t else f

notM :: Functor m => m Bool -> m Bool
notM = fmap not

(||^), (&&^) :: Monad m => m Bool -> m Bool -> m Bool
(||^) a b = do a <- a; if a then return True else b
(&&^) a b = do a <- a; if a then b else return False

retry :: Int -> IO a -> IO a
retry i x | i <= 0 = error "retry count must be 1 or more"
retry 1 x = x
retry i x = do
    res <- E.try x
    case res of
        Left (e :: SomeException) -> do
            putStrLn $ "Retrying after exception: " ++ show e
            retry (i-1) x
        Right v -> return v


---------------------------------------------------------------------
-- System.Info

isWindows :: Bool
#if defined(mingw32_HOST_OS)
isWindows = True
#else
isWindows = False
#endif


-- Use the underlying GHC function
foreign import ccall getNumberOfProcessors :: IO CInt


{-# NOINLINE getProcessorCount #-}
getProcessorCount :: IO Int
-- unsafePefromIO so we cache the result and only compute it once
getProcessorCount = let res = unsafePerformIO act in return res
    where
        act =
            if rtsSupportsBoundThreads then
                fromIntegral <$> getNumberOfProcessors
            else
                handle (\(_ :: SomeException) -> return 1) $ do
                    env <- getEnvMaybe "NUMBER_OF_PROCESSORS"
                    case env of
                        Just s | [(i,"")] <- reads s -> return i
                        _ -> do
                            src <- readFile "/proc/cpuinfo"
                            return $ length [() | x <- lines src, "processor" `isPrefixOf` x]


---------------------------------------------------------------------
-- System.IO

readFileStrict :: FilePath -> IO String
readFileStrict file = withFile file ReadMode $ \h -> do
    src <- hGetContents h
    evaluate $ length src
    return src

readFileUCS2 :: FilePath -> IO String
readFileUCS2 name = openFile name ReadMode >>= \h -> do
    hSetEncoding h utf16
    hGetContents h

getEnvMaybe :: String -> IO (Maybe String)
getEnvMaybe x = catchJust (\x -> if isDoesNotExistError x then Just x else Nothing) (fmap Just $ getEnv x) (const $ return Nothing)

captureOutput :: IO () -> IO String
captureOutput act = do
    tmp <- getTemporaryDirectory
    (f,h) <- openTempFile tmp "hlint"
    sto <- hDuplicate stdout
    ste <- hDuplicate stderr
    hDuplicateTo h stdout
    hDuplicateTo h stderr
    hClose h
    act
    hDuplicateTo sto stdout
    hDuplicateTo ste stderr
    res <- readFile f
    evaluate $ length res
    removeFile f
    return res

withCapabilities :: Int -> IO a -> IO a
#if __GLASGOW_HASKELL__ >= 706
withCapabilities new act | rtsSupportsBoundThreads = do
    old <- getNumCapabilities
    if old == new then act else
        bracket_ (setNumCapabilities new) (setNumCapabilities old) act
#endif
withCapabilities new act = act

withBufferMode :: Handle -> BufferMode -> IO a -> IO a
withBufferMode h b act = bracket (hGetBuffering h) (hSetBuffering h) $ const $ do
    hSetBuffering h LineBuffering
    act


getExePath :: IO FilePath
#if __GLASGOW_HASKELL__ >= 706
getExePath = getExecutablePath
#else
getExePath = getProgName
#endif


---------------------------------------------------------------------
-- System.Random

randomElem :: [a] -> IO a
randomElem xs = do
    i <- randomRIO (0, length xs - 1)
    return $ xs !! i
