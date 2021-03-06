module Pscid.Options where

import Prelude
import Control.Monad.Eff.Console as Console
import Data.Array as Array
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Exception (catchException)
import Data.Array (filter, filterM)
import Data.Either (Either(Left))
import Data.Int (floor)
import Data.Maybe (Maybe(Just))
import Data.String (split, null)
import Global (readInt)
import Node.FS (FS)
import Node.Platform (Platform(Win32))
import Node.Process (platform)
import Node.Yargs.Applicative (flag, yarg, runY)
import Node.Yargs.Setup (example, usage, defaultHelp, defaultVersion)
import Pscid.Util ((∘))

type PscidOptions =
  { port              ∷ Int
  , buildCommand      ∷ String
  , testCommand       ∷ String
  , testAfterRebuild  ∷ Boolean
  , sourceDirectories ∷ Array String
  , censorCodes       ∷ Array String
  }

defaultOptions ∷ PscidOptions
defaultOptions =
  { port: 4243
  , buildCommand: pulpCmd <> " build"
  , testCommand: pulpCmd <> " test"
  , testAfterRebuild: false
  , sourceDirectories: ["src", "test"]
  , censorCodes: []
  }

-- | Scans the default directories and returns those, that did contain
-- | PureScript files.
scanDefaultDirectories :: forall e. Eff (fs :: FS | e) (Array String)
scanDefaultDirectories =
  let
    defaultDirectories = ["src", "app", "test", "tests"]
    mkGlob dir = dir <> "/**/*.purs"
  in
   filterM (map (not ∘ Array.null) ∘ glob ∘ mkGlob) defaultDirectories

pulpCmd ∷ String
pulpCmd = if platform == Win32 then "pulp.cmd" else "pulp"

npmCmd ∷ String
npmCmd = if platform == Win32 then "npm.cmd" else "npm"

mkDefaultOptions ∷ ∀ e. Eff (fs ∷ FS | e) PscidOptions
mkDefaultOptions =
  defaultOptions { buildCommand = _
                 , testCommand = _
                 , sourceDirectories = _
                 }
  <$> mkCommand "build"
  <*> mkCommand "test"
  <*> scanDefaultDirectories

mkCommand ∷ ∀ e. String → Eff (fs ∷ FS | e) String
mkCommand cmd =
  hasNamedScript cmd <#> \b →
    (if b then npmCmd <> " run -s " else pulpCmd <> " ") <> cmd

optionParser ∷ ∀ e. Eff (console ∷ Console.CONSOLE, fs ∷ FS | e) PscidOptions
optionParser =
  let
    setup = usage "$0 -p 4245"
            <> example "$0 -p 4245" "Watching ... on port 4245"
            <> defaultHelp
            <> defaultVersion
  in
   catchException (const do
                      Console.error "Failed parsing the arguments."
                      Console.error "Falling back to default options"
                      mkDefaultOptions) $
     runY setup $ buildOptions
       <$> yarg "p" ["port"] (Just "The Port") (Left "4243") false
       <*> flag "test" [] (Just "Test project after save")
       <*> yarg "I" ["include"]
         (Just "Additional globs for PureScript source files, separated by `;`")
         (Left "")
         false
       <*> yarg "censor-codes" []
         (Just "Warning codes to ignore, seperated by `,`")
         (Left "")
         false

buildOptions
  :: forall e
  . String
  -> Boolean
  -> String
  -> String
  -> Eff (fs :: FS | e) PscidOptions
buildOptions port testAfterRebuild includes censor = do
  defaults <- mkDefaultOptions
  let sourceDirectories =
        if null includes
        then defaults.sourceDirectories
        else filter (not null) (split ";" includes)
      censorCodes = filter (not null) (split "," censor)
  pure { port: floor (readInt 10 port)
       , testAfterRebuild
       , sourceDirectories
       , censorCodes
       , buildCommand: defaults.buildCommand
       , testCommand: defaults.testCommand
       }

foreign import hasNamedScript ∷ ∀ e. String → Eff (fs ∷ FS | e) Boolean
foreign import glob :: forall e. String -> Eff (fs :: FS | e) (Array String)
