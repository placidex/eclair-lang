{-# LANGUAGE UndecidableInstances #-}

module Eclair.AST.Analysis
  ( Result(..)
  , PointsToAnalysis(..)
  , SemanticInfo(..)
  , SemanticErrors(..)
  , hasSemanticErrors
  , runAnalysis
  , UngroundedVar(..)
  , WildcardInFact(..)
  , WildcardInRuleHead(..)
  , WildcardInConstraint(..)
  , WildcardInBinOp(..)
  , DeadCode(..)
  , DeadInternalRelation(..)
  , NoOutputRelation(..)
  , NodeId(..)
  , Container
  , computeUsageMapping
  ) where

import qualified Language.Souffle.Interpreted as S
import qualified Language.Souffle.Analysis as S
import qualified Eclair.AST.IR as IR
import qualified Data.Map as Map
import Eclair.Common.Id
import Eclair.Common.Location (NodeId(..))


type Position = Word32

-- The facts submitted to Datalog closely follow the AST structure,
-- but are denormalized so that Datalog can easily process it.

data LitNumber
  = LitNumber NodeId Word32
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions LitNumber "lit_number" 'S.Input

data LitString
  = LitString NodeId Text
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions LitString "lit_string" 'S.Input

data Var
  = Var NodeId Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Var "variable" 'S.Input

newtype Hole
  = Hole NodeId
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Hole "hole" 'S.Input

data Constraint
  = Constraint
  { constraintId :: NodeId
  , constraintOperator :: Text
  , constraintLhsId :: NodeId
  , constraintRhsId :: NodeId
  }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Constraint "constraint" 'S.Input

data BinOp
  = BinOp
  { binOpId :: NodeId
  , op :: Text
  , binOpLhsId :: NodeId
  , binOpRhsId :: NodeId
  }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions BinOp "binop" 'S.Input

data Atom
  = Atom NodeId Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Atom "atom" 'S.Input

data AtomArg
  = AtomArg { atomId :: NodeId, atomArgPos :: Word32, atomArgId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions AtomArg "atom_arg" 'S.Input

data Rule
  = Rule NodeId Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Rule "rule" 'S.Input

data RuleArg
  = RuleArg { raRuleId :: NodeId, raArgPos :: Word32, raArgId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions RuleArg "rule_arg" 'S.Input

data RuleClause
  = RuleClause { rcRuleId :: NodeId, rcClausePos :: Word32, rcClauseId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions RuleClause "rule_clause" 'S.Input

-- NOTE: not storing types right now, but might be useful later?
data DeclareType
  = DeclareType NodeId Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions DeclareType "declare_type" 'S.Input

newtype InputRelation
  = InputRelation Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions InputRelation "input_relation" 'S.Input

newtype OutputRelation
  = OutputRelation Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions OutputRelation "output_relation" 'S.Input

newtype InternalRelation
  = InternalRelation Id
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions InternalRelation "internal_relation" 'S.Input

newtype Module
  = Module NodeId
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions Module "module" 'S.Input

data ModuleDecl
  = ModuleDecl { moduleId :: NodeId, declId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions ModuleDecl "module_declaration" 'S.Input

data ScopedValue
  = ScopedValue { svScopeId :: NodeId, svNodeId :: NodeId }
  deriving stock Generic
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions ScopedValue "scoped_value" 'S.Input

data PointsToVar
  = PointsToVar
  { ptRuleId :: NodeId
  , ptVar1Id :: NodeId
  , ptVar2Id :: NodeId
  , ptVar2Name :: Id
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions PointsToVar "points_to_var" 'S.Output

data UngroundedVar loc
  = UngroundedVar
  { ungroundedRuleLoc :: loc
  , ungroundedVarLoc :: loc
  , ungroundedVarName :: Id
  }
  deriving stock (Generic, Eq, Show, Functor)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions (UngroundedVar loc) "ungrounded_variable" 'S.Output

data WildcardInFact loc
  = WildcardInFact
  { factLoc :: loc
  , factArgLoc :: loc
  , wildcardFactPos :: Position
  }
  deriving stock (Generic, Eq, Show, Functor)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions (WildcardInFact loc) "wildcard_in_fact" 'S.Output

data WildcardInRuleHead loc
  = WildcardInRuleHead
  { wildcardRuleLoc :: loc
  , wildcardRuleArgLoc :: loc
  , wildcardRuleHeadPos :: Position
  }
  deriving stock (Generic, Eq, Show, Functor)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions (WildcardInRuleHead loc) "wildcard_in_rule_head" 'S.Output

data WildcardInConstraint loc
  = WildcardInConstraint
  { wildcardConstraintLoc :: loc
  , wildcardConstraintPos :: loc
  }
  deriving stock (Generic, Eq, Show, Functor)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions (WildcardInConstraint loc) "wildcard_in_constraint" 'S.Output

data WildcardInBinOp loc
  = WildcardInBinOp
  { wildcardBinOpLoc :: loc
  , wildcardBinOpPos :: loc
  }
  deriving stock (Generic, Eq, Show, Functor)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions (WildcardInBinOp loc) "wildcard_in_binop" 'S.Output

newtype DeadCode
  = DeadCode { unDeadCode :: NodeId }
  deriving stock (Generic, Eq, Show)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions DeadCode "dead_code" 'S.Output

newtype NoOutputRelation loc
  = NoOutputRelation loc
  deriving stock (Generic, Eq, Show, Functor)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions (NoOutputRelation loc) "no_output_relation" 'S.Output

data DeadInternalRelation loc
  = DeadInternalRelation loc Id
  deriving stock (Generic, Eq, Show, Functor)
  deriving anyclass S.Marshal
  deriving S.Fact via S.FactOptions (DeadInternalRelation loc) "dead_internal_relation" 'S.Output

data SemanticAnalysis
  = SemanticAnalysis
  deriving S.Program
  via S.ProgramOptions SemanticAnalysis "semantic_analysis"
      '[ LitNumber
       , LitString
       , Var
       , Hole
       , Constraint
       , BinOp
       , Atom
       , AtomArg
       , Rule
       , RuleArg
       , RuleClause
       , DeclareType
       , InputRelation
       , OutputRelation
       , InternalRelation
       , Module
       , ModuleDecl
       , ScopedValue
       , PointsToVar
       , UngroundedVar NodeId
       , WildcardInRuleHead NodeId
       , WildcardInFact NodeId
       , WildcardInConstraint NodeId
       , WildcardInBinOp NodeId
       , DeadCode
       , NoOutputRelation NodeId
       , DeadInternalRelation NodeId
       ]

-- TODO: change to Vector when finished for performance
type Container = []

-- Points-to analysis of variables.
-- For now only takes variables mapping to other variables into account.
newtype PointsToAnalysis
  = PointsToAnalysis (Map NodeId IR.AST)
  deriving (Eq, Show)

mkPointsToAnalysis :: Container PointsToVar -> PointsToAnalysis
mkPointsToAnalysis =
  PointsToAnalysis . Map.fromList . toList . map toEntry
  where
    toEntry (PointsToVar _ var1Id var2Id var2Name) =
      (var1Id, IR.Var var2Id var2Name)

data SemanticInfo
  = SemanticInfo
  { pointsToAnalysis :: PointsToAnalysis
  , deadCodeIds :: Container DeadCode
  } deriving (Eq, Show)

data Result
  = Result
  { semanticInfo :: SemanticInfo
  , semanticErrors :: SemanticErrors NodeId
  }
  deriving (Eq, Show)

data SemanticErrors loc
  = SemanticErrors
  { ungroundedVars :: Container (UngroundedVar loc)
  , wildcardsInFacts :: Container (WildcardInFact loc)
  , wildcardsInRuleHeads :: Container (WildcardInRuleHead loc)
  , wildcardsInConstraints :: Container (WildcardInConstraint loc)
  , wildcardsInBinOps :: Container (WildcardInBinOp loc)
  , deadInternalRelations :: Container (DeadInternalRelation loc)
  , noOutputRelations :: Container (NoOutputRelation loc)
  }
  deriving (Eq, Show, Exception, Functor)

hasSemanticErrors :: Result -> Bool
hasSemanticErrors result =
  isNotNull ungroundedVars ||
  isNotNull wildcardsInFacts ||
  isNotNull wildcardsInRuleHeads ||
  isNotNull wildcardsInConstraints ||
  isNotNull wildcardsInBinOps ||
  isNotNull deadInternalRelations ||
  isNotNull noOutputRelations
  where
    errs = semanticErrors result
    isNotNull :: (SemanticErrors NodeId -> [a]) -> Bool
    isNotNull f = not . null $ f errs

analysis :: S.Handle SemanticAnalysis -> S.Analysis S.SouffleM IR.AST Result
analysis prog = S.mkAnalysis addFacts run getFacts
  where
    addFacts :: IR.AST -> S.SouffleM ()
    addFacts ast = usingReaderT Nothing $ flip (zygo getNodeId) ast $ \case
      IR.LitF nodeId lit -> do
        mScopeId <- ask
        forM_ mScopeId $ \scopeId ->
          S.addFact prog $ ScopedValue scopeId nodeId
        case lit of
          IR.LNumber x ->
            S.addFact prog $ LitNumber nodeId x
          IR.LString x ->
            S.addFact prog $ LitString nodeId x
      IR.PWildcardF nodeId ->
        S.addFact prog $ Var nodeId (Id "_")
      IR.VarF nodeId var -> do
        S.addFact prog $ Var nodeId var
        maybeRuleId <- ask
        for_ maybeRuleId $ \ruleId ->
          S.addFact prog $ ScopedValue ruleId nodeId
      IR.HoleF nodeId ->
        S.addFact prog $ Hole nodeId
      IR.BinOpF nodeId arithOp (lhsId', lhsAction) (rhsId', rhsAction) -> do
        let textualOp = case arithOp of
              IR.Plus -> "+"
              IR.Minus -> "-"
              IR.Multiply -> "*"
              IR.Divide -> "/"
        S.addFact prog $ BinOp nodeId textualOp lhsId' rhsId'
        lhsAction
        rhsAction
      IR.ConstraintF nodeId constraintOp (lhsId', lhsAction) (rhsId', rhsAction) -> do
        let textualOp = case constraintOp of
              IR.Equals -> "="
              IR.NotEquals -> "!="
              IR.LessThan -> "<"
              IR.LessOrEqual -> "<="
              IR.GreaterThan -> "<"
              IR.GreaterOrEqual -> "<="
        S.addFact prog $ Constraint nodeId textualOp lhsId' rhsId'
        lhsAction
        rhsAction
      IR.AtomF nodeId atom (unzip -> (argNodeIds, actions)) -> do
        S.addFact prog $ Atom nodeId atom
        S.addFacts prog $ mapWithPos (AtomArg nodeId) argNodeIds
        mScopeId <- ask
        let maybeAddScope =
              if isJust mScopeId
                then id
                else local (const $ Just nodeId)
        maybeAddScope $ sequence_ actions
      IR.RuleF nodeId rule ruleArgs ruleClauses -> do
        let (argNodeIds, argActions) = unzip ruleArgs
            (clauseNodeIds, clauseActions) = unzip ruleClauses
        S.addFact prog $ Rule nodeId rule
        S.addFacts prog $ mapWithPos (RuleArg nodeId) argNodeIds
        S.addFacts prog $ mapWithPos (RuleClause nodeId) clauseNodeIds
        local (const $ Just nodeId) $ do
          sequence_ argActions
          sequence_ clauseActions
      IR.DeclareTypeF nodeId name _ usageMode -> do
        S.addFact prog $ DeclareType nodeId name

        case usageMode of
          IR.Input ->
            S.addFact prog $ InputRelation name
          IR.Output ->
            S.addFact prog $ OutputRelation name
          IR.InputOutput -> do
            S.addFact prog $ InputRelation name
            S.addFact prog $ OutputRelation name
          IR.Internal ->
            S.addFact prog $ InternalRelation name
      IR.ModuleF nodeId (unzip -> (declNodeIds, actions)) -> do
        S.addFact prog $ Module nodeId
        S.addFacts prog $ map (ModuleDecl nodeId) declNodeIds
        sequence_ actions

    run :: S.SouffleM ()
    run = do
      -- TODO: optimal CPU core count? just use all cores?
      S.setNumThreads prog 8
      S.run prog

    getFacts :: S.SouffleM Result
    getFacts = do
      info <- SemanticInfo <$> (mkPointsToAnalysis <$> S.getFacts prog)
                           <*> S.getFacts prog
      errs <- SemanticErrors <$> S.getFacts prog
                             <*> S.getFacts prog
                             <*> S.getFacts prog
                             <*> S.getFacts prog
                             <*> S.getFacts prog
                             <*> S.getFacts prog
                             <*> S.getFacts prog
      pure $ Result info errs

    getNodeId :: IR.ASTF NodeId -> NodeId
    getNodeId = \case
      IR.LitF nodeId _ -> nodeId
      IR.VarF nodeId _ -> nodeId
      IR.HoleF nodeId -> nodeId
      IR.BinOpF nodeId _ _ _ -> nodeId
      IR.ConstraintF nodeId _ _ _ -> nodeId
      IR.AtomF nodeId _ _ -> nodeId
      IR.RuleF nodeId _ _ _ -> nodeId
      IR.DeclareTypeF nodeId _ _ _ -> nodeId
      IR.ModuleF nodeId _ -> nodeId

    mapWithPos :: (Word32 -> a -> b) -> [a] -> [b]
    mapWithPos g = zipWith g [0..]

runAnalysis :: IR.AST -> IO Result
runAnalysis ast = S.runSouffle SemanticAnalysis $ \case
  Nothing -> panic "Failed to load Souffle during semantic analysis!"
  Just prog -> S.execAnalysis (analysis prog) ast

computeUsageMapping :: IR.AST -> Map Id IR.UsageMode
computeUsageMapping ast =
  Map.fromList pairs
  where
    pairs = flip cata ast $ \case
      IR.DeclareTypeF _ name _ mode ->
        one (name, mode)
      astf ->
        fold astf
