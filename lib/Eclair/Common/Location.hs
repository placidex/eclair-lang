module Eclair.Common.Location
  ( NodeId(..)
  , Span(..)
  , SpanMap(..)
  , SourcePos(..)
  , SourceSpan(..)
  , insertSpan
  , lookupSpan
  , lookupNodeId
  , spanToSourceSpan
  ) where

import qualified Text.Megaparsec as P
import qualified Data.Map as M
import qualified Language.Souffle.Marshal as S
import Data.Maybe (fromJust)

newtype NodeId
  = NodeId
  { unNodeId :: Word32
  } deriving (Eq, Ord, Show, Generic)
  deriving S.Marshal

-- A source span (begin and end position)
data Span
  = Span
  { beginPos :: {-# UNPACK #-} !Int
  , endPos :: {-# UNPACK #-} !Int
  } deriving Show

data SpanMap =
  SpanMap
  { spanMapPath :: !FilePath
  , spanMapSpans :: !(Map Word32 Span)
  }
  deriving Show

insertSpan :: NodeId -> Span -> SpanMap -> SpanMap
insertSpan nodeId span' (SpanMap path m) =
  SpanMap path (M.insert (unNodeId nodeId) span' m)

-- NOTE: this assumes the node ID is generated by parsing the same file that resulted in the SpanMap.
lookupSpan :: SpanMap -> NodeId -> Span
lookupSpan (SpanMap _path m) nodeId =
  fromJust $ M.lookup (unNodeId nodeId) m

-- Finds the most specific NodeId (that corresponds with the smallest span)
lookupNodeId :: SpanMap -> Int -> Maybe NodeId
lookupNodeId (SpanMap _ m) offset =
  m & M.toList
    & filter (containsOffset . snd)
    -- Just sorting by span size is not enough, sometimes we have two spans
    -- with identical widths (e.g. with parentheses). The last one will always
    -- be the node ID that belongs to the smallest (most specific) node.
    & sortWith (spanSize . snd &&& negate . fst)
    & viaNonEmpty head
    & map (NodeId . fst)
  where
    containsOffset span' =
      offset >= beginPos span' && offset < endPos span'

    spanSize span' =
      endPos span' - beginPos span'

-- Helpers for producing error messages:

-- Line and column information. 1-based!
data SourcePos
  = SourcePos
  { sourcePosLine :: {-# UNPACK #-} !Int
  , sourcePosColumn :: {-# UNPACK #-} !Int
  } deriving (Eq, Ord, Show)

data SourceSpan
  = SourceSpan
  { sourceSpanFile :: FilePath
  , sourceSpanBegin :: {-# UNPACK #-} !SourcePos
  , sourceSpanEnd :: {-# UNPACK #-} !SourcePos
  }

spanToSourceSpan :: FilePath -> Text -> Span -> SourceSpan
spanToSourceSpan path text span'@(Span begin end) =
  either raiseError id parseResult
  where
    parseResult = P.runParser parser path text

    parser :: P.Parsec Void Text SourceSpan
    parser = do
      _ <- P.takeP Nothing begin
      beginPos' <- P.getSourcePos
      _ <- P.takeP Nothing diff
      endPos' <- P.getSourcePos
      let beginSourcePos = SourcePos (line beginPos') (column beginPos')
          endSourcePos = SourcePos (line endPos') (column endPos')
      pure $ SourceSpan path beginSourcePos endSourcePos
      where
        diff = end - begin
        line = P.unPos . P.sourceLine
        column = P.unPos . P.sourceColumn

    raiseError =
      const $ panic $ "Failed to get source location for file '" <> toText path <> "' and span " <> show span'
