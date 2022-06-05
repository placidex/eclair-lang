module Test.Eclair.AST.AnalysisSpec
  ( module Test.Eclair.AST.AnalysisSpec
  ) where

import Test.Hspec
import System.FilePath
import Eclair.AST.Analysis
import Eclair.Id
import Eclair


check :: (Eq a, Show a) => (Result -> a) -> FilePath -> a -> IO ()
check f path expected = do
  let file = "tests/fixtures" </> path <.> "dl"
  result <- semanticAnalysis file
  f result `shouldBe` expected

checkUngroundedVars :: FilePath -> [Text] -> IO ()
checkUngroundedVars path expectedVars =
  check getUngroundedVars path (map Id expectedVars)
  where
    getUngroundedVars =
      map (\(UngroundedVar _ v) -> v) . ungroundedVars

checkMissingTypedefs :: FilePath -> [Text] -> IO ()
checkMissingTypedefs path expectedVars =
  check getMissingTypedefs path (map Id expectedVars)
  where
    getMissingTypedefs =
      map (\(MissingTypedef _ v) -> v) . missingTypedefs

spec :: Spec
spec = describe "Semantic analysis" $ parallel $ do
  describe "detecting missing typedefinitions" $ do
    it "detects no missing type definitions for empty file" $
      checkMissingTypedefs "empty" []

    it "detects missing type definitions for rules" $
      checkMissingTypedefs "missing_typedef_in_rule"
        ["unknown_rule", "unknown_fact1", "unknown_fact2"]

    it "detects missing type definitions for top level facts" $
      checkMissingTypedefs "missing_typedef_in_atom"
        ["unknown_fact"]

    it "finds no issues if all types are defined" $ do
      checkMissingTypedefs "mutually_recursive_rules" []
      checkMissingTypedefs "typedef_after_usage" []

  describe "detecting ungrounded variables" $ do
    it "finds no ungrounded vars for empty file" $ do
      checkUngroundedVars "empty" []

    it "finds no ungrounded vars for top level fact with no vars" $ do
      checkUngroundedVars "single_fact" []

    it "finds no ungrounded vars for valid non-recursive rules" $ do
      checkUngroundedVars "single_nonrecursive_rule" []
      checkUngroundedVars "multiple_rule_clauses" []
      checkUngroundedVars "multiple_clauses_same_name" []

    it "finds no ungrounded vars for valid recursive rules" $ do
      checkUngroundedVars "single_recursive_rule" []
      checkUngroundedVars "mutually_recursive_rules" []

    it "finds no ungrounded vars for a rule where 2 vars are equal" pending

    it "marks all variables found in top level facts as ungrounded" $ do
      checkUngroundedVars "ungrounded_var_in_facts" ["a", "b", "c", "d"]

    it "marks all variables only found in a rule head as ungrounded" $ do
      checkUngroundedVars "ungrounded_var_in_rules" ["z", "a", "b"]

    it "finds no ungrounded vars for a rule with a unused var in the body" $ do
      checkUngroundedVars "ungrounded_var_check_in_rule_body" []