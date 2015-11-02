{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module HSnippet.BuildSnippet where

------------------------------------------------------------------------------
import           Control.Monad.Trans
import           Data.Aeson
import           Data.Digest.Pure.SHA
import           Data.String.Conv
import qualified Data.Text.IO         as T
import           Data.Text            (Text)
import           Snap.Core
import           Snap.Snaplet
import           System.Directory
import           System.Exit
import           System.FilePath
import           System.Process
------------------------------------------------------------------------------
import           HSnippet.Types.App
import           HSnippet.Shared.Types.BuildResults
------------------------------------------------------------------------------

writeJSON :: (MonadSnap m, ToJSON a) => a -> m ()
writeJSON a = do
  modifyResponse $ setHeader "Content-Type" "application/json"
  writeLBS . encode $ a

ghcjsBuildHandler :: Handler App App ()
ghcjsBuildHandler = do
    mbs <- getParam "snippet"
    case decode . toS =<< mbs of
      Just (String t) -> do
          let sb = mkSnippetBlob t
          (out, err, success) <- liftIO $ do
              exists <- doesFileExist $ sbJsOut sb
              putStrLn $ "Exists " ++ show exists ++ ": " ++ sbJsOut sb
              if exists
                then return ("Snippet already built", "", True)
                else do
                  createDirectoryIfMissing True (sbRoot sb)
                  copyFile "../sandbox/template.hs" (sbMain sb)
                  T.appendFile (sbMain sb) t
                  (code, out, err) <- buildSnippet sb
                  return (out, err, code == ExitSuccess)
          writeJSON $ BuildResults (sbName sb) out err success
      _ -> writeJSON $ String "<h2 class='red'>Error: no data</h2>"

data SnippetBlob = SnippetBlob
    { sbContents :: Text
    , sbHash     :: Digest SHA1State
    }

mkSnippetBlob :: Text -> SnippetBlob
mkSnippetBlob t = SnippetBlob t (sha1 $ toS t)

sbName :: SnippetBlob -> String
sbName SnippetBlob{..} = "Snippet_" ++ showDigest sbHash

sbRoot :: SnippetBlob -> String
sbRoot sb = "../sandbox/snippets/" ++ sbName sb

sbMain :: SnippetBlob -> String
sbMain sb = sbRoot sb </> "Main.hs"

-- NOTE: This must match the output file in sandbox/build-snippet.sh
sbJsOut :: SnippetBlob -> String
sbJsOut sb = sbRoot sb </> "out.js.gz"

buildSnippet :: SnippetBlob -> IO (ExitCode, String, String)
buildSnippet sb = do
    putStrLn $ "Building " ++ sbName sb
    let cp = (proc "../sandbox/build-snippet.sh" [sbName sb])
               { cwd = Just "../sandbox" }
    readCreateProcessWithExitCode cp ""