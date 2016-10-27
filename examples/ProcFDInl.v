Require Import Kami.Syntax Kami.Semantics Kami.RefinementFacts Kami.Renaming Kami.Wf.
Require Import Kami.Inline Kami.InlineFacts Kami.Tactics.
Require Import Ex.SC Ex.MemTypes Ex.ProcFetchDecode.

Set Implicit Arguments.

Section Inlined.
  Variables addrSize iaddrSize lgDataBytes rfIdx: nat.

  (* External abstract ISA: decoding and execution *)
  Variables (getOptype: OptypeT lgDataBytes)
            (getLdDst: LdDstT lgDataBytes rfIdx)
            (getLdAddr: LdAddrT addrSize lgDataBytes)
            (getLdSrc: LdSrcT lgDataBytes rfIdx)
            (calcLdAddr: LdAddrCalcT addrSize lgDataBytes)
            (getStAddr: StAddrT addrSize lgDataBytes)
            (getStSrc: StSrcT lgDataBytes rfIdx)
            (calcStAddr: StAddrCalcT addrSize lgDataBytes)
            (getStVSrc: StVSrcT lgDataBytes rfIdx)
            (getSrc1: Src1T lgDataBytes rfIdx)
            (getSrc2: Src2T lgDataBytes rfIdx)
            (getDst: DstT lgDataBytes rfIdx)
            (exec: ExecT addrSize lgDataBytes)
            (getNextPc: NextPcT addrSize lgDataBytes rfIdx)
            (alignPc: AlignPcT addrSize iaddrSize)
            (predictNextPc: forall ty, fullType ty (SyntaxKind (Bit addrSize)) -> (* pc *)
                                       Expr ty (SyntaxKind (Bit addrSize))).

  Variable (d2eElt: Kind).
  Variable (d2ePack:
              forall ty,
                Expr ty (SyntaxKind (Bit 2)) -> (* opTy *)
                Expr ty (SyntaxKind (Bit rfIdx)) -> (* dst *)
                Expr ty (SyntaxKind (Bit addrSize)) -> (* addr *)
                Expr ty (SyntaxKind (Data lgDataBytes)) -> (* val1 *)
                Expr ty (SyntaxKind (Data lgDataBytes)) -> (* val2 *)
                Expr ty (SyntaxKind (Data lgDataBytes)) -> (* rawInst *)
                Expr ty (SyntaxKind (Bit addrSize)) -> (* curPc *)
                Expr ty (SyntaxKind (Bit addrSize)) -> (* nextPc *)
                Expr ty (SyntaxKind Bool) -> (* epoch *)
                Expr ty (SyntaxKind d2eElt)).

  Variable (f2dElt: Kind).
  Variable (f2dPack:
              forall ty,
                Expr ty (SyntaxKind (Data lgDataBytes)) -> (* rawInst *)
                Expr ty (SyntaxKind (Bit addrSize)) -> (* curPc *)
                Expr ty (SyntaxKind (Bit addrSize)) -> (* nextPc *)
                Expr ty (SyntaxKind Bool) -> (* epoch *)
                Expr ty (SyntaxKind f2dElt)).
  Variables
    (f2dRawInst: forall ty, fullType ty (SyntaxKind f2dElt) ->
                            Expr ty (SyntaxKind (Data lgDataBytes)))
    (f2dCurPc: forall ty, fullType ty (SyntaxKind f2dElt) ->
                          Expr ty (SyntaxKind (Bit addrSize)))
    (f2dNextPc: forall ty, fullType ty (SyntaxKind f2dElt) ->
                           Expr ty (SyntaxKind (Bit addrSize)))
    (f2dEpoch: forall ty, fullType ty (SyntaxKind f2dElt) ->
                          Expr ty (SyntaxKind Bool)).

  Definition fetchDecode := fetchDecode getOptype getLdDst getLdAddr getLdSrc calcLdAddr
                                        getStAddr getStSrc calcStAddr getStVSrc
                                        getSrc1 getSrc2 getDst alignPc predictNextPc
                                        d2ePack f2dPack f2dRawInst f2dCurPc f2dNextPc f2dEpoch.
  Hint Unfold fetchDecode: ModuleDefs. (* for kinline_compute *)

  Definition fetchDecodeInl: sigT (fun m: Modules => fetchDecode <<== m).
  Proof.
    pose proof (inlineF_refines
                  (fetchDecode_ModEquiv getOptype getLdDst getLdAddr getLdSrc calcLdAddr
                                        getStAddr getStSrc calcStAddr getStVSrc
                                        getSrc1 getSrc2 getDst alignPc predictNextPc d2ePack
                                        f2dPack f2dRawInst f2dCurPc f2dNextPc f2dEpoch
                                        type typeUT)
                  (Reflection.noDupStr_NoDup (Struct.namesOf (getDefsBodies fetchDecode)) eq_refl))
      as Him.
    unfold MethsT in Him; rewrite <-SemFacts.idElementwiseId in Him.
    match goal with
    | [H: context[inlineF ?m] |- _] => set m as origm in H at 2
    end.
    kinline_compute_in Him.
    unfold origm in *.
    specialize (Him eq_refl).
    exact (existT _ _ Him).
  Defined.

End Inlined.