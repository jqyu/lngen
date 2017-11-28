{-# OPTIONS_GHC -fcontext-stack=50 #-}

{- | This module defines the functions necessary to transform an 'AST'
   into a 'String' containing output for the Coq proof assistant.
   Definitions are encoded using a locally nameless representation. -}

module CoqLNOutput ( coqOfAST ) where

import Data.Graph    ( SCC(..), stronglyConnComp )
import Text.Printf   ( printf )

import AST
import ASTAnalysis
import ComputationMonad
import CoqLNOutputCommon
import CoqLNOutputDefinitions
import CoqLNOutputThmDegree
import CoqLNOutputThmFv
import CoqLNOutputThmLc
import CoqLNOutputThmOpenClose
import CoqLNOutputThmOpenClose2
import CoqLNOutputThmSize
import CoqLNOutputThmSwap
import CoqLNOutputThmSubst
import MyLibrary ( nmap )


{- ----------------------------------------------------------------------- -}
{- * Exported functionality -}

{- | Generates Coq output for the given 'AST'.  The first argument is
   the name of the library for the output generated by Ott.  The
   second is the directory name for a @LoadPath@ declaration. -}

coqOfAST :: Maybe String -> Maybe String -> AST -> M String
coqOfAST ott loadpath ast =
    do { bodyStrs   <- mapM (local . processBody aa) nts
       ; closeStrs  <- mapM (local . processClose aa) nts
       ; degreeStrs <- mapM (local . processDegree aa) nts
       ; lcStrs     <- mapM (local . processLc aa) nts
       ; ntStrs     <- mapM (local . processNt aa) nts
       ; sizeStrs   <- mapM (local . processSize aa) nts
       ; swapStrs   <- mapM (local . processSwap aa) nts
       ; tacticStrs <- local $ processTactics aa

       ; degree_thms      <- degreeThms aa nts
       ; fv_thms          <- fvThms aa nts
       ; lc_thms          <- lcThms aa nts
       ; open_close_thms  <- openCloseThms aa nts
       ; open_close_thms2 <- openCloseThms2 aa nts
       ; size_thms        <- sizeThms aa nts
       ; swap_thms        <- swapThms aa nts
       ; subst_thms       <- substThms aa nts

       ; return $ (case loadpath of
                     Nothing -> ""
                     Just s  -> "Add LoadPath \"" ++ s ++ "\".\n") ++
                  "Require Import Coq.Arith.Wf_nat.\n\
                  \Require Import Coq.Logic.FunctionalExtensionality.\n\
                  \Require Import Coq.Program.Equality.\n\
                  \\n\
                  \Require Export Metalib.Metatheory.\n\
                  \Require Export Metalib.LibLNgen.\n" ++
                  (case ott of
                     Nothing -> ""
                     Just s  -> "\nRequire Export " ++ s ++ ".\n") ++
                  "\n\
                  \(** NOTE: Auxiliary theorems are hidden in generated documentation.\n\
                  \    In general, there is a [_rec] version of every lemma involving\n\
                  \    [open] and [close]. *)\n\
                  \\n\
                  \\n" ++
                  coqSep ++ "(** * Induction principles for nonterminals *)\n\n" ++
                  concat ntStrs ++ "\n" ++
                  coqSep ++ "(** * Close *)\n\n" ++
                  concat closeStrs ++ "\n" ++
                  coqSep ++ "(** * Size *)\n\n" ++
                  concat sizeStrs ++ "\n" ++
                  coqSep ++ "(** * Degree *)\n\
                            \\n\
                            \(** These define only an upper bound, not a strict upper bound. *)\n\
                            \\n" ++
                  concat degreeStrs ++ "\n" ++
                  coqSep ++ "(** * Local closure (version in [Set], induction principles) *)\n\n" ++
                  concat lcStrs ++ "\n" ++
                  coqSep ++ "(** * Body *)\n\n" ++
                  concat bodyStrs ++ "\n" ++
                  -- coqSep ++ "(** * Swapping *)\n\n" ++
                  -- concat swapStrs ++ "\n" ++
                  coqSep ++ "(** * Tactic support *)\n\n" ++
                  tacticStrs ++ "\n" ++
                  coqSep ++ "(** * Theorems about [size] *)\n\n" ++
                  size_thms ++
                  coqSep ++ "(** * Theorems about [degree] *)\n\n" ++
                  degree_thms ++
                  coqSep ++ "(** * Theorems about [open] and [close] *)\n\n" ++
                  open_close_thms ++
                  coqSep ++ "(** * Theorems about [lc] *)\n\n" ++
                  lc_thms ++
                  coqSep ++ "(** * More theorems about [open] and [close] *)\n\n" ++
                  open_close_thms2 ++
                  coqSep ++ "(** * Theorems about [fv] *)\n\n" ++
                  fv_thms ++
                  coqSep ++ "(** * Theorems about [subst] *)\n\n" ++
                  subst_thms ++
                  -- coqSep ++ "(** * Theorems about [swap] *)\n\n" ++
                  -- swap_thms ++
                  coqSep ++ printf "(** * \"Restore\" tactics *)\n\
                                   \\n\
                                   \Ltac %s ::= auto; tauto.\n\
                                   \Ltac %s ::= fail.\n"
                                   defaultAuto
                                   defaultAutoRewr
       }
    where
      fixSCC (AcyclicSCC n) = [canon n]
      fixSCC (CyclicSCC ns) = nmap canon ns

      aa    = analyzeAST ast
      canon = canonRoot aa
      nts   = reverse $ nmap fixSCC $ stronglyConnComp $ ntGraph aa
