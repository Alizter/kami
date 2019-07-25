Require Import Bool String List.
Require Import Lib.CommonTactics Lib.ilist Lib.Word.
Require Import Lib.Struct Lib.FMap Lib.StringEq Lib.Indexer.
Require Import Kami.Syntax Kami.Semantics Kami.RefinementFacts Kami.Renaming Kami.Wf.
Require Import Kami.Renaming Kami.Inline Kami.InlineFacts.
Require Import Kami.Decomposition Kami.Notations Kami.Tactics.
Require Import Ex.MemTypes Ex.NativeFifo Ex.MemAsync.
Require Import Ex.SC Ex.ProcDec Ex.ProcThreeStage Ex.ProcFetch Ex.ProcFInl
        Ex.ProcFInv Ex.ProcFetchDecode.
Require Import Eqdep.

Set Implicit Arguments.

Section Fetch.
  Variables addrSize iaddrSize instBytes dataBytes: nat.

  Variables (fetch: AbsFetch addrSize iaddrSize instBytes dataBytes)
            (predictNextPc:
               forall ty, fullType ty (SyntaxKind (Pc iaddrSize)) -> (* pc *)
                          Expr ty (SyntaxKind (Pc iaddrSize))).

  Variable (f2dElt: Kind).
  Variable (f2dPack:
              forall ty,
                Expr ty (SyntaxKind (Data instBytes)) -> (* rawInst *)
                Expr ty (SyntaxKind (Pc iaddrSize)) -> (* curPc *)
                Expr ty (SyntaxKind (Pc iaddrSize)) -> (* nextPc *)
                Expr ty (SyntaxKind Bool) -> (* epoch *)
                Expr ty (SyntaxKind f2dElt)).
  Variables
    (f2dRawInst: forall ty, fullType ty (SyntaxKind f2dElt) ->
                            Expr ty (SyntaxKind (Data instBytes)))
    (f2dCurPc: forall ty, fullType ty (SyntaxKind f2dElt) ->
                          Expr ty (SyntaxKind (Pc iaddrSize)))
    (f2dNextPc: forall ty, fullType ty (SyntaxKind f2dElt) ->
                           Expr ty (SyntaxKind (Pc iaddrSize)))
    (f2dEpoch: forall ty, fullType ty (SyntaxKind f2dElt) ->
                          Expr ty (SyntaxKind Bool)).

  Hypothesis
    (Hf2dpackExt:
       forall rawInst1 curPc1 nextPc1 epoch1 rawInst2 curPc2 nextPc2 epoch2,
         evalExpr rawInst1 = evalExpr rawInst2 ->
         evalExpr curPc1 = evalExpr curPc2 ->
         evalExpr nextPc1 = evalExpr nextPc2 ->
         evalExpr epoch1 = evalExpr epoch2 ->
         evalExpr (f2dPack rawInst1 curPc1 nextPc1 epoch1) =
         evalExpr (f2dPack rawInst2 curPc2 nextPc2 epoch2)).
    
  Variables (pcInit : ConstT (Pc iaddrSize)).

  Definition fetchICache: Modules :=
    fetchICache fetch predictNextPc f2dPack pcInit.
  Definition fetchICacheInl :=
    ProcFInl.fetchICacheInl fetch predictNextPc f2dPack pcInit.
  Definition fetcher: Modules :=
    ProcFetchDecode.fetcher fetch predictNextPc f2dPack pcInit.

  Definition fetchICache_ruleMap (o: RegsT): string -> option string :=
    "pgmInitRq" |-> "pgmInitRq";
      "pgmInitRqEnd" |-> "pgmInitRqEnd";
      "pgmInitRs" |-> "pgmInitRs";
      "pgmInitRsEnd" |-> "pgmInitRsEnd";
      "modifyPc" |-> "modifyPc";
      "instFetchRs" |-> "instFetch"; ||.
  Hint Unfold fetchICache_ruleMap: MethDefs.

  Definition fetchICache_regMap (r: RegsT): RegsT :=
    (mlet pcv : (Pc iaddrSize) <- r |> "pc";
       mlet pinitv : Bool <- r |> "pinit";
       mlet pinitRqv : Bool <- r |> "pinitRq";
       mlet pinitRqOfsv : (Bit iaddrSize) <- r |> "pinitRqOfs";
       mlet pinitRsOfsv : (Bit iaddrSize) <- r |> "pinitRsOfs";
       mlet fepochv : Bool <- r |> "fEpoch";
       mlet bramv : (Vector (Data instBytes) iaddrSize) <- r |> "pgm"--"bram";
       (["fEpoch" <- existT _ _ fepochv]
        +["pgm" <- existT _ _ bramv]
        +["pinitRsOfs" <- existT _ _ pinitRsOfsv]
        +["pinitRqOfs" <- existT _ _ pinitRqOfsv]
        +["pinitRq" <- existT _ _ pinitRqv]
        +["pinit" <- existT _ _ pinitv]
        +["pc" <- existT _ _ pcv]
       )%fmap)%mapping.
  Hint Unfold fetchICache_regMap: MapDefs.

  Ltac fetchICache_dest_tac :=
    repeat match goal with
           | [H: context[fetchICache_inv] |- _] => destruct H
           end;
    kinv_red.

  Theorem fetchICache_refines_fetcher:
    fetchICache <<== fetcher.
  Proof. (* SKIP_PROOF_OFF *)

    (** inlining *)
    ketrans; [exact (projT2 fetchICacheInl)|].

    (** decomposition *)
    kdecompose_nodefs fetchICache_regMap fetchICache_ruleMap.
    kinv_add fetchICache_inv_ok.
    kinv_add_end.
    kinvert.

    - kinv_action_dest.
      kinv_custom fetchICache_dest_tac.
      kinv_regmap_red.
      kinv_constr; kinv_eq; kinv_finish.

    - kinv_action_dest.
      kinv_custom fetchICache_dest_tac.
      kinv_regmap_red.
      kinv_constr; kinv_eq; kinv_finish.

    - kinv_action_dest.
      kinv_custom fetchICache_dest_tac.
      kinv_regmap_red.
      kinv_constr; kinv_eq; kinv_finish.

    - kinv_action_dest.
      kinv_custom fetchICache_dest_tac.
      kinv_regmap_red.
      kinv_constr; kinv_eq; kinv_finish.

    - kinv_action_dest.
      kinv_custom fetchICache_dest_tac.
      kinv_regmap_red.
      kinv_constr; kinv_eq.

    - kinv_action_dest.
      kinv_custom fetchICache_dest_tac.
      kinv_regmap_red.
      kinv_constr; kinv_eq.

    - kinv_action_dest.
      kinv_custom fetchICache_dest_tac.
      kinv_regmap_red.
      kinv_constr; kinv_eq.
      apply Hf2dpackExt; try reflexivity.
      simpl.
      destruct x0; [subst|discriminate].
      reflexivity.

    - kinv_action_dest.
      kinv_custom fetchICache_dest_tac.
      kinv_regmap_red.
      kinv_constr; kinv_eq.
      (* END_SKIP_PROOF_OFF *)
  Qed.

End Fetch.

