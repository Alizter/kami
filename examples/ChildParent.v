Require Import Ascii Bool String List.
Require Import Lib.CommonTactics Lib.ilist Lib.Word Lib.Struct Lib.StringBound Lib.Indexer.
Require Import Lts.Syntax Lts.Semantics Lts.Equiv Lts.Tactics.
Require Import Ex.MemTypes.

Set Implicit Arguments.

Section ChildParent.
  Variables IdxBits LgNumDatas LgDataBytes LgNumChildren: nat.
  Variable Id: Kind.

  Definition AddrBits := IdxBits + (LgNumDatas + LgDataBytes).
  Definition Addr := Bit AddrBits.
  Definition Idx := Bit IdxBits.
  Definition Data := Bit (LgDataBytes * 8).
  Definition Offset := Bit LgNumDatas.
  Definition Line := Vector Data LgNumDatas.
 
  Definition RqToP := Ex.MemTypes.RqToP Addr Id.
  Definition RqFromC := Ex.MemTypes.RqFromC LgNumChildren Addr Id.
  Definition RsToP := Ex.MemTypes.RsToP LgDataBytes LgNumDatas Addr.
  Definition RsFromC := Ex.MemTypes.RsFromC LgDataBytes LgNumDatas LgNumChildren Addr.
  Definition FromP := Ex.MemTypes.FromP LgDataBytes LgNumDatas Addr Id.
  Definition ToC := Ex.MemTypes.ToC LgDataBytes LgNumDatas LgNumChildren Addr Id.

  Definition rqToPPop i := MethodSig "rqToP".."deq"__ i (Void): RqToP.
  Definition rqFromCEnq := MethodSig "rqFromC".."enq" (RqFromC): Void.
  Definition rsToPPop i := MethodSig "rsToP".."deq"__ i (Void): RsToP.
  Definition rsFromCEnq := MethodSig "rsFromC".."enq" (RsFromC): Void.

  Definition toCPop := MethodSig "toC".."deq" (Void): ToC.
  Definition fromPEnq i := MethodSig "fromP".."deq"__ i (FromP): Void.

  Definition n := wordToNat (wones LgNumChildren).
  Definition childParent :=
    MODULE {
        Repeat n as i {
          Rule ("rqFromCToP"__ i) :=
            Call rq <- (rqToPPop i)();
            Call rqFromCEnq(STRUCT{"child" ::= $ i; "rq" ::= #rq});
            Retv
              
          with Rule ("rsFromCToP"__ i) :=
            Call rs <- (rsToPPop i)();
            Call rsFromCEnq(STRUCT{"child" ::= $ i; "rs" ::= #rs});
            Retv

          with Rule ("fromPToC"__ i) :=
            Call msg <- toCPop();
            Assert $ i == #msg@."child";
            Call (fromPEnq i)(#msg@."msg");
            Retv
                      }
      }.
End ChildParent.

Hint Unfold AddrBits Addr Idx Data Offset Line : MethDefs.
Hint Unfold RqToP RqFromC RsToP RsFromC FromP ToC : MethDefs.
Hint Unfold rqToPPop rqFromCEnq rsToPPop rsFromCEnq toCPop fromPEnq n : MethDefs.

Hint Unfold childParent : ModuleDefs.

Section Facts.
  Variables IdxBits LgNumDatas LgDataBytes LgNumChildren: nat.
  Variable Id: Kind.

  Lemma childParent_ModEquiv:
    ModEquiv type typeUT (childParent IdxBits LgNumDatas LgDataBytes LgNumChildren Id).
  Proof.
    admit. (* ModEquiv for repetition *)
  Qed.

End Facts.

Hint Immediate childParent_ModEquiv.

