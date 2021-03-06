{-# LANGUAGE RecordWildCards, PatternGuards #-}

module Development.Make.All(runMakefile) where

import System.Environment
import Development.Shake hiding (addEnv)
import Development.Shake.FilePath
import Development.Make.Parse
import Development.Make.Env
import Development.Make.Rules
import Development.Make.Type
import qualified System.Directory as IO
import General.Base
import Data.List
import Data.Maybe
import Control.Arrow
import Control.Monad
import System.Process
import System.Exit
import Control.Monad.Trans.State.Strict


runMakefile :: FilePath -> [String] -> IO (Rules ())
runMakefile file args = do
    env <- defaultEnv
    mk <- parse file
    rs <- eval env mk
    return $ do
        defaultRuleFile_
        case filter (not . isPrefixOf "." . target) rs of
            Ruler x _ _ : _ | null args, '%' `notElem` x -> want_ [x]
            _ -> return ()
        mapM_ (want_ . return) args
        convert rs


data Ruler = Ruler
    {target :: String
    ,prereq :: (Env, Expr) -- Env is the Env at this point
    ,cmds :: (Env, [Command]) -- Env is the Env at the end
    }


eval :: Env -> Makefile -> IO [Ruler]
eval env (Makefile xs) = do
    (rs, env) <- runStateT (fmap concat $ mapM f xs) env
    return [r{cmds=(env,snd $ cmds r)} | r <- rs]
    where
        f :: Stmt -> StateT Env IO [Ruler]
        f Assign{..} = do
            e <- get
            e <- liftIO $ addEnv name assign expr e
            put e
            return []

        f Rule{..} = do
            e <- get
            target <- liftIO $ fmap words $ askEnv e targets
            return $ map (\t -> Ruler t (e, prerequisites) (undefined, commands)) target


convert :: [Ruler] -> Rules ()
convert rs = match ??> run
    where
        match s = any (isJust . check s) rs
        check s r = makePattern (target r) s

        run target =  do
            let phony = has False ".PHONY" target
            let silent = has True ".SILENT" target
            (deps, cmds) <- fmap (first concat . second concat . unzip) $ forM rs $ \r ->
                case check target r of
                    Nothing -> return ([], [])
                    Just op -> do
                        let (preEnv,preExp) = prereq r
                        env <- liftIO $ addEnv "@" Equals (Lit target) preEnv
                        pre <- liftIO $ askEnv env preExp
                        vp <- liftIO $ fmap splitSearchPath $ askEnv env $ Var "VPATH"
                        pre <- mapM (vpath vp) $ words $ op pre
                        return (pre, [cmds r])
            mapM_ (need_ . return) deps
            forM_ cmds $ \(env,cmd) -> do
                env <- liftIO $ addEnv "@" Equals (Lit target) env
                env <- liftIO $ addEnv "^" Equals (Lit $ unwords deps) env
                env <- liftIO $ addEnv "<" Equals (Lit $ head $ deps ++ [""]) env
                forM_ cmd $ \c ->
                    case c of
                        Expr c -> (if silent then quietly else id) $
                            execCommand =<< liftIO (askEnv env c)
            return $ if phony then Phony else NotPhony

        has auto name target =
            or [(null ws && auto) || target `elem` ws | Ruler t (_,Lit s) _ <- rs, t == name, let ws = words s]


execCommand :: String -> Action ()
execCommand x = do
    res <- if "@" `isPrefixOf` x then sys $ drop 1 x
           else putNormal x >> sys x
    when (res /= ExitSuccess) $
        error $ "System command failed: " ++ x
    where sys = quietly . traced (unwords $ take 1 $ words x) . system


makePattern :: String -> FilePath -> Maybe (String -> String)
makePattern pat v = case break (== '%') pat of
    (pre,'%':post) -> if pre `isPrefixOf` v && post `isSuffixOf` v && rest >= 0
                      then Just $ concatMap (\x -> if x == '%' then subs else [x])
                      else Nothing
        where rest = length v - (length pre + length post)
              subs = take rest $ drop (length pre) v
    otherwise -> if pat == v then Just id else Nothing


vpath :: [FilePath] -> FilePath -> Action FilePath
vpath [] y = return y
vpath (x:xs) y = do
    b <- doesFileExist $ x </> y
    if b then return $ x </> y else vpath xs y


defaultEnv :: IO Env
defaultEnv = do
    exePath <- getExePath
    env <- getEnvironment
    cur <- IO.getCurrentDirectory
    return $ newEnv $
        ("EXE",if null exe then "" else "." ++ exe) :
        ("MAKE",normalise exePath) :
        ("CURDIR",normalise cur) :
        env
