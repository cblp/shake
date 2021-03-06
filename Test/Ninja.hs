
module Test.Ninja(main) where

import Development.Shake
import Development.Shake.FilePath
import qualified Development.Shake.Config as Config
import System.Directory(copyFile)
import Control.Monad
import General.Base
import Test.Type
import qualified Data.HashMap.Strict as Map
import Data.List
import Data.Maybe
import qualified Start
import System.Environment


main = shaken test $ \args obj -> do
    let args2 = ("-C" ++ obj "") : map tail (filter ("@" `isPrefixOf`) args)
    let real = "real" `elem` args
    action $
        if real then cmd "ninja" args2 else liftIO $ withArgs args2 Start.main


test build obj = do
    -- when calling run anything with a leading @ gets given to Shake, anything without gets given to Ninja
    let run xs = build $ "--exception" : map (\x -> fromMaybe ('@':x) $ stripPrefix "@" x) (words xs)
    let runFail xs bad = assertException [bad] $ run $ xs ++ " --quiet"

    build ["clean"]
    run "-f../../Test/Ninja/test1.ninja"
    assertExists $ obj "out1.txt"

    run "-f../../Test/Ninja/test2.ninja"
    assertExists $ obj "out2.2"
    assertMissing $ obj "out2.1"
    build ["clean"]
    run "-f../../Test/Ninja/test2.ninja out2.1"
    assertExists $ obj "out2.1"
    assertMissing $ obj "out2.2"

    copyFile "Test/Ninja/test3-sub.ninja" $ obj "test3-sub.ninja"
    copyFile "Test/Ninja/test3-inc.ninja" $ obj "test3-inc.ninja"
    copyFile ("Test/Ninja/" ++ if null exe then "test3-unix.ninja" else "test3-win.ninja") $ obj "test3-platform.ninja"
    run "-f../../Test/Ninja/test3.ninja"
    assertNonSpace (obj "out3.1") "g4+b1+++i1"
    assertNonSpace (obj "out3.2") "g4++++i1"
    assertNonSpace (obj "out3.3") "g4++++i1"
    assertNonSpace (obj "out3.4") "g4+++s1+s2"

    run "-f../../Test/Ninja/test4.ninja out"
    assertExists $ obj "out.txt"
    assertExists $ obj "out2.txt"

    run "-f../../Test/Ninja/test5.ninja"
    assertExists $ obj "output file"

    writeFile (obj "nocreate.log") ""
    writeFile (obj "nocreate.in") ""
    run "-f../../Test/Ninja/nocreate.ninja"
    assertNonSpace (obj "nocreate.log") "x"
    run "-f../../Test/Ninja/nocreate.ninja"
    run "-f../../Test/Ninja/nocreate.ninja"
    assertNonSpace (obj "nocreate.log") "xxx"

    writeFile (obj "input") ""
    runFail "-f../../Test/Ninja/lint.ninja bad --lint" "'needed' file required rebuilding"
    run "-f../../Test/Ninja/lint.ninja good --lint"
    runFail "-f../../Test/Ninja/lint.ninja bad --lint" "not a pre-dependency"

    res <- fmap (drop 1 . lines) $ captureOutput $ run "-f../../Test/Ninja/compdb.ninja -t compdb cxx @--no-report @--quiet"
    want <- fmap lines $ readFile "Test/Ninja/compdb.output"
    let eq a b | (a1,'*':a2) <- break (== '*') a = unless (a1 `isPrefixOf` b && a2 `isSuffixOf` b) $ a === b
               | otherwise = a === b
    length want === length res
    zipWithM_ eq want res

    -- Test initial variable bindings and variables in include/subninja statements
    let test6 = obj "test6"

    copyFile "Test/Ninja/test6-sub.ninja" $ test6 ++ "-sub.ninja"
    copyFile "Test/Ninja/test6-inc.ninja" $ test6 ++ "-inc.ninja"
    copyFile "Test/Ninja/test6.ninja" $ test6 ++ ".ninja"

    config <- Config.readConfigFileWithEnv [("v1", test6)] $ test6 ++ ".ninja"
    -- The file included by subninja should have a separate variable scope
    Map.lookup "v2" config === Just "g2"
