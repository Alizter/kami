Require Import Bool List String Structures.Equalities.
Require Import Lib.Struct Lib.Word Lib.CommonTactics Lib.StringBound Lib.ilist Lib.FnMap Syntax.
Require Import FunctionalExtensionality Program.Equality Eqdep Eqdep_dec.

Set Implicit Arguments.

(* concrete representations of data kinds *)
Fixpoint type (t: Kind): Type :=
  match t with
    | Bool => bool
    | Bit n => word n
    | Vector nt n => word n -> type nt
    | Struct attrs => forall i, @GetAttrType _ (map (mapAttr type) attrs) i
  end.

Section WordFunc.

  Definition wordZero (w: word 0): w = WO :=
    shatter_word w.

  Variable A: Type.

  (* a lemma for wordVecDec *)
  Definition wordVecDec':
    forall n (f g: word n -> A), (forall x: word n, {f x = g x} + {f x <> g x}) ->
                                 {forall x, f x = g x} + {exists x, f x <> g x}.
  Proof.
    intro n.
    induction n; intros f g H.
    - destruct (H WO).
      + left; intros x.
        rewrite (wordZero x) in *; intuition.
      + right; eauto.
    - assert (Hn: forall b (x: word n),
                    {f (WS b x) = g (WS b x)} + {f (WS b x) <> g (WS b x)}) by
             (intros; specialize (H (WS b x)); intuition).
      destruct (IHn _ _ (Hn false)) as [ef | nf].
      + destruct (IHn _ _ (Hn true)) as [et | nt].
        * left; intros x.
          specialize (ef (wtl x)).
          specialize (et (wtl x)).
          pose proof (shatter_word x) as use; simpl in *.
          destruct (whd x); rewrite <- use in *; intuition.
        * right; destruct_ex; eauto.
      + right; destruct_ex; eauto.
  Qed.

  Definition wordVecDec:
    forall n (f g: word n -> A), (forall x: word n, {f x = g x} + {f x <> g x}) ->
                                 {f = g} + {f <> g}.
  Proof.
    intros.
    pose proof (wordVecDec' _ _ H) as [lt | rt].
    left; apply functional_extensionality; intuition.
    right; unfold not; intros eq; rewrite eq in *.
    destruct rt; intuition.
  Qed.
End WordFunc.

Section VecFunc.
  Variable A: Type.
  Fixpoint evalVec n (vec: Vec A n): word n -> A.
  Proof.
    refine match vec in Vec _ n return word n -> A with
             | Vec0 e => fun _ => e
             | VecNext n' v1 v2 =>
               fun w =>
                 match w in word m0 return m0 = S n' -> A with
                   | WO => _
                   | WS b m w' =>
                     if b
                     then fun _ => evalVec _ v2 (_ w')
                     else fun _ => evalVec _ v2 (_ w')
                 end eq_refl
           end;
    clear evalVec.
    abstract (intros; discriminate).
    abstract (injection _H; intros; subst; intuition).
    abstract (injection _H; intros; subst; intuition).
  Defined.

  Variable B: Type.
  Variable map: A -> B.
  Fixpoint mapVec n (vec: Vec A n): Vec B n :=
    match vec in Vec _ n return Vec B n with
      | Vec0 e => Vec0 (map e)
      | VecNext n' v1 v2 => VecNext (mapVec v1) (mapVec v2)
    end.
End VecFunc.

(* for any kind, we have decidable equality on its representation *)
Definition isEq : forall k (e1: type k) (e2: type k),
                    {e1 = e2} + {e1 <> e2}.
Proof.
  refine (fix isEq k : forall (e1: type k) (e2: type k), {e1 = e2} + {e1 <> e2} :=
            match k return forall (e1: type k) (e2: type k),
                             {e1 = e2} + {e1 <> e2} with
              | Bool => bool_dec
              | Bit n => fun e1 e2 => weq e1 e2
              | Vector n nt =>
                  fun e1 e2 =>
                    wordVecDec e1 e2 (fun x => isEq _ (e1 x) (e2 x))
              | Struct h =>
                (fix isEqs atts : forall (vs1 vs2 : forall i, @GetAttrType _ (map (mapAttr type) atts) i),
                                    {vs1 = vs2} + {vs1 <> vs2} :=
                   match atts return forall (vs1 vs2 : forall i, @GetAttrType _ (map (mapAttr type) atts) i),
                                       {vs1 = vs2} + {vs1 <> vs2} with
                     | nil => fun _ _ => Yes
                     | att :: atts' => fun vs1 vs2 =>
                       isEq _
                            (vs1 {| bindex := attrName att; indexb := {| ibound := 0;
                                      boundi := eq_refl :
                                                  nth_error
                                                    (map (attrName (Kind:=Type))
                                                         (map (mapAttr type) (att :: atts'))) 0
                                                    = Some (attrName att) |} |})
                            (vs2 {| bindex := attrName att; indexb := {| ibound := 0;
                                      boundi := eq_refl :
                                                  nth_error
                                                    (map (attrName (Kind:=Type))
                                                         (map (mapAttr type) (att :: atts'))) 0
                                                    = Some (attrName att) |} |});;
                       isEqs atts'
                       (fun i => vs1 {| indexb := {| ibound := S (ibound (indexb i)) |} |})
                       (fun i => vs2 {| indexb := {| ibound := S (ibound (indexb i)) |} |});;
                       Yes
                   end) h
            end); clear isEq; try clear isEqs;
  abstract (unfold BoundedIndexFull in *; simpl in *; try (intro; subst; tauto);
  repeat match goal with
           | [ |- _ = _ ] => extensionality i
           | [ x : BoundedIndex _ |- _ ] => destruct x
           | [ x : IndexBound _ _ |- _ ] => destruct x
           | [ H : nth_error nil ?n = Some _ |- _ ] => destruct n; discriminate
           | [ |- _ {| indexb := {| ibound := ?b |} |} = _ ] =>
             match goal with
               | [ x : _ |- _ ] =>
                 match x with
                   | b => destruct b; simpl in *
                 end
             end
           | [ H : Specif.value _ = Some _ |- _ ] => progress (injection H; intro; subst)
           | [ H : _ = _ |- _ ] => progress rewrite (UIP_refl _ _ H)
           | [ H : _ = _ |- _ {| bindex := ?bi; indexb := {| ibound := S ?ib; boundi := ?pf |} |} = _ ] =>
             apply (f_equal (fun f => f {| bindex := bi; indexb := {| ibound := ib; boundi := pf |} |})) in H
         end; auto).
Defined.

Definition evalUniBool (op: UniBoolOp) : bool -> bool :=
  match op with
    | Neg => negb
  end.

Definition evalBinBool (op: BinBoolOp) : bool -> bool -> bool :=
  match op with
    | And => andb
    | Or => orb
  end.

(* the head of a word, or false if the word has 0 bits *)
Definition whd' sz (w: word sz) :=
  match sz as s return word s -> bool with
    | 0 => fun _ => false
    | S n => fun w => whd w
  end w.

Definition evalUniBit n1 n2 (op: UniBitOp n1 n2): word n1 -> word n2.
refine match op with
         | Inv n => @wneg n
         | ConstExtract n1 n2 n3 => fun w => split2 n1 n2 (split1 (n1 + n2) n3 w)
         | ZeroExtendTrunc n1 n2 => fun w => split2 n1 n2 (_ (combine (wzero n2) w))
         | SignExtendTrunc n1 n2 => fun w => split2 n1 n2 (_ (combine (if whd' w
                                                                       then wones n2
                                                                       else wzero n2) w))
         | TruncLsb n1 n2 => fun w => split1 n1 n2 w
       end;
  assert (H: n3 + n0 = n0 + n3) by omega;
  rewrite H in *; intuition.
Defined.

Definition evalBinBit n1 n2 n3 (op: BinBitOp n1 n2 n3)
  : word n1 -> word n2 -> word n3 :=
  match op with
    | Add n => @wplus n
    | Sub n => @wminus n
  end.

(* evaluate any constant operation *)
Fixpoint evalConstT k (e: ConstT k): type k :=
  match e in ConstT k return type k with
    | ConstBool b => b
    | ConstBit n w => w
    | ConstVector k' n v => evalVec (mapVec (@evalConstT k') v)
    | ConstStruct attrs ils =>
        fun (i: BoundedIndex (map (@attrName _) (map (mapAttr type) attrs))) =>
          mapAttrEq1 type attrs i
                     (ith_Bounded _ (imap _ (fun _ ba => evalConstT ba) ils)
                                  (getNewIdx1 type attrs i))
  end.

Section GetCms.
  Fixpoint getCmsA {k} (a: Action type k): list string :=
    match a with
      | MCall m _ _ c => m :: (getCmsA (c (evalConstT (getDefaultConst _))))
      | Let _ _ c => getCmsA (c (evalConstT (getDefaultConst _)))
      | ReadReg _ _ c => getCmsA (c (evalConstT (getDefaultConst _)))
      | WriteReg _ _ _ c => getCmsA c
      | IfElse _ _ aT aF c =>
        (getCmsA aT) ++ (getCmsA aF)
                     ++ (getCmsA (c (evalConstT (getDefaultConst _))))
      | Assert _ c => getCmsA c
      | Return _ => nil
    end.

  Fixpoint getCmsR (rl: list (Attribute (Action type (Bit 0))))
  : list string :=
    match rl with
      | nil => nil
      | r :: rl' => (getCmsA (attrType r)) ++ (getCmsR rl')
    end.

  Fixpoint getCmsM (ms: list (DefMethT type)): list string :=
    match ms with
      | nil => nil
      | m :: ms' => (getCmsA ((objVal (attrType m))
                                (evalConstT (getDefaultConst _))))
                      ++ (getCmsM ms')
    end.

  Fixpoint getCmsMod (m: Modules type): list string :=
    match m with
      | Mod _ rules meths => getCmsR rules ++ getCmsM meths
      | ConcatMod m1 m2 => (listSub (getCmsMod m1) (getDmsMod m2))
                             ++ (listSub (getCmsMod m2) (getDmsMod m1))
    end
  with getDmsMod (m: Modules type): list string :=
         match m with
           | Mod _ _ meths => map (@attrName _) meths
           | ConcatMod m1 m2 => (listSub (getDmsMod m1) (getCmsMod m2))
                                  ++ (listSub (getDmsMod m2) (getCmsMod m1))
         end.

End GetCms.

Hint Unfold getCmsMod getDmsMod.

(* maps register names to the values which they currently hold *)
Definition RegsT := @Map (Typed type).

(* a pair of the value sent to a method call and the value it returned *)
Definition SignT k := (type (arg k) * type (ret k))%type.

(* a list of simulatenous method call actions made during a single step *)
Definition CallsT := @Map (Typed SignT).

Section Semantics.
  Fixpoint evalExpr exprT (e: Expr type exprT): type exprT :=
    match e in Expr _ exprT return type exprT with
      | Var _ v => v
      | Const _ v => evalConstT v
      | UniBool op e1 => (evalUniBool op) (evalExpr e1)
      | BinBool op e1 e2 => (evalBinBool op) (evalExpr e1) (evalExpr e2)
      | UniBit n1 n2 op e1 => (evalUniBit op) (evalExpr e1)
      | BinBit n1 n2 n3 op e1 e2 => (evalBinBit op) (evalExpr e1) (evalExpr e2)
      | ITE _ p e1 e2 => if evalExpr p
                         then evalExpr e1
                         else evalExpr e2
      | Eq _ e1 e2 => if isEq _ (evalExpr e1) (evalExpr e2)
                      then true
                      else false
      | ReadIndex _ _ i f => (evalExpr f) (evalExpr i)
      | ReadField heading fld val =>
          mapAttrEq2 type fld
            ((evalExpr val) (getNewIdx2 type fld))
      | BuildVector _ k vec => evalVec (mapVec (@evalExpr _) vec)
      | BuildStruct attrs ils =>
          fun (i: BoundedIndex (map (@attrName _) (map (mapAttr type) attrs))) =>
            mapAttrEq1 type attrs i (ith_Bounded _ (imap _ (fun _ ba => evalExpr ba) ils)
                                                 (getNewIdx1 type attrs i))
      | UpdateVector _ _ fn i v =>
          fun w => if weq w (evalExpr i) then evalExpr v else (evalExpr fn) w
    end.

  (*register names and constant expressions for their initial values *)
  Variable regInit: list RegInitT.

  Variable rules: list (Attribute (Action type (Bit 0))).

  (* register values just before the current cycle *)
  Variable oldRegs: RegsT.

  Inductive SemAction:
    forall k, Action type k -> RegsT -> CallsT -> type k -> Prop :=
  | SemMCall
      meth s (marg: Expr type (arg s))
      (mret: type (ret s))
      retK (fret: type retK)
      (cont: type (ret s) -> Action type retK)
      newRegs (calls: CallsT) acalls
      (HAcalls: acalls = add meth {| objVal := (evalExpr marg, mret) |} calls)
      (HSemAction: SemAction (cont mret) newRegs calls fret):
      SemAction (MCall meth s marg cont) newRegs acalls fret
  | SemLet
      k (e: Expr type k) retK (fret: type retK)
      (cont: type k -> Action type retK) newRegs calls
      (HSemAction: SemAction (cont (evalExpr e)) newRegs calls fret):
      SemAction (Let e cont) newRegs calls fret
  | SemReadReg
      (r: string) regT regV
      retK (fret: type retK) (cont: type regT -> Action type retK)
      newRegs calls
      (HRegVal: find r oldRegs = Some {| objType := regT; objVal := regV |})
      (HSemAction: SemAction (cont regV) newRegs calls fret):
      SemAction (ReadReg r _ cont) newRegs calls fret
  | SemWriteReg
      (r: string) k
      (e: Expr type k)
      retK (fret: type retK)
      (cont: Action type retK) newRegs calls anewRegs
      (HANewRegs: anewRegs = add r {| objVal := (evalExpr e) |} newRegs)
      (HSemAction: SemAction cont newRegs calls fret):
      SemAction (WriteReg r e cont) anewRegs calls fret
  | SemIfElseTrue
      (p: Expr type Bool) k1
      (a: Action type k1)
      (a': Action type k1)
      (r1: type k1)
      k2 (cont: type k1 -> Action type k2)
      newRegs1 newRegs2 calls1 calls2 (r2: type k2)
      (HTrue: evalExpr p = true)
      (HAction: SemAction a newRegs1 calls1 r1)
      (HSemAction: SemAction (cont r1) newRegs2 calls2 r2)
      unewRegs ucalls
      (HUNewRegs: unewRegs = union newRegs1 newRegs2)
      (HUCalls: ucalls = union calls1 calls2):
      SemAction (IfElse p a a' cont) unewRegs ucalls r2
  | SemIfElseFalse
      (p: Expr type Bool) k1
      (a: Action type k1)
      (a': Action type k1)
      (r1: type k1)
      k2 (cont: type k1 -> Action type k2)
      newRegs1 newRegs2 calls1 calls2 (r2: type k2)
      (HFalse: evalExpr p = false)
      (HAction: SemAction a' newRegs1 calls1 r1)
      (HSemAction: SemAction (cont r1) newRegs2 calls2 r2)
      unewRegs ucalls
      (HUNewRegs: unewRegs = union newRegs1 newRegs2)
      (HUCalls: ucalls = union calls1 calls2):
      SemAction (IfElse p a a' cont) unewRegs ucalls r2
  | SemAssertTrue
      (p: Expr type Bool) k2
      (cont: Action type k2) newRegs2 calls2 (r2: type k2)
      (HTrue: evalExpr p = true)
      (HSemAction: SemAction cont newRegs2 calls2 r2):
      SemAction (Assert p cont) newRegs2 calls2 r2
  | SemReturn
      k (e: Expr type k) evale
      (HEvalE: evale = evalExpr e):
      SemAction (Return e) empty empty evale.

  Theorem inversionSemAction
          k a news calls retC
          (evalA: @SemAction k a news calls retC):
    match a with
      | MCall m s e c =>
        exists mret pcalls,
          SemAction (c mret) news pcalls retC /\
          calls = add m {| objVal := (evalExpr e, mret) |} pcalls
      | Let _ e cont =>
        SemAction (cont (evalExpr e)) news calls retC
      | ReadReg r k c =>
        exists rv,
          find r oldRegs = Some {| objType := k; objVal := rv |} /\
          SemAction (c rv) news calls retC
      | WriteReg r _ e a =>
        exists pnews,
          SemAction a pnews calls retC /\
          news = add r {| objVal := evalExpr e |} pnews
      | IfElse p _ aT aF c =>
        exists news1 calls1 news2 calls2 r1,
          match evalExpr p with
            | true =>
              SemAction aT news1 calls1 r1 /\
              SemAction (c r1) news2 calls2 retC /\
              news = union news1 news2 /\
              calls = union calls1 calls2
            | false =>
              SemAction aF news1 calls1 r1 /\
              SemAction (c r1) news2 calls2 retC /\
              news = union news1 news2 /\
              calls = union calls1 calls2
          end
      | Assert e c =>
        SemAction c news calls retC /\
        evalExpr e = true
      | Return e =>
        retC = evalExpr e /\
        news = empty /\
        calls = empty
    end.
  Proof.
    destruct evalA; eauto; repeat eexists; destruct (evalExpr p); eauto; try discriminate.
  Qed.

  Inductive SemMod: option string -> RegsT -> list (DefMethT type) -> CallsT -> CallsT -> Prop :=
  | SemEmpty news dm cm
             (HEmptyRegs: news = empty)
             (HEmptyDms: dm = empty)
             (HEmptyCms: cm = empty):
      SemMod None news nil dm cm
  | SemAddRule (ruleName: string)
               (ruleBody: Action type (Bit 0))
               (HInRule: In {| attrName := ruleName; attrType := ruleBody |} rules)
               news calls retV
               (HAction: SemAction ruleBody news calls retV)
               news2 meths dm2 cm2
               (HSemMod: SemMod None news2 meths dm2 cm2)
               (HNoDoubleWrites: Disj news news2)
               (HNoCallsBoth: Disj calls cm2)
               unews ucalls
               (HRegs: unews = union news news2)
               (HCalls: ucalls = union calls cm2):
      SemMod (Some ruleName) unews meths dm2 ucalls
  (* method `meth` was also called this clock cycle *)
  | SemAddMeth calls news (meth: DefMethT type) meths argV retV
               (HAction: SemAction ((objVal (attrType meth)) argV) news calls retV)
               news2 dm2 cm2
               (HSemMod: SemMod None news2 meths dm2 cm2)
               (HNoDoubleWrites: Disj news news2)
               (HNoCallsBoth: Disj calls cm2)
               unews ucalls udefs
               (HRegs: unews = union news news2)
               (HCalls: ucalls = union calls cm2)
               (HDefs: udefs = add (attrName meth) {| objVal := (argV, retV) |} dm2):
      SemMod None unews (meth :: meths) udefs ucalls
  (* method `meth` was not called in this clock cycle *)
  | SemSkipMeth news meth meths dm cm
                (HSemMod: SemMod None news meths dm cm):
      SemMod None news (meth :: meths) dm cm.

End Semantics.

Ltac invertAction H :=
  ((destruct (inversionSemAction H))
     || (let Hia := fresh "Hia" in
         pose proof (inversionSemAction H) as Hia; simpl in Hia));
  clear H; dest; subst.
Ltac invertActionFirst :=
  match goal with
    | [H: SemAction _ _ _ _ _ |- _] => invertAction H
  end.
Ltac invertActionRep :=
  repeat
    match goal with
      | [H: SemAction _ _ _ _ _ |- _] => invertAction H
      | [H: if ?c
            then
              SemAction _ _ _ _ _ /\ _ /\ _ /\ _
            else
              SemAction _ _ _ _ _ /\ _ /\ _ /\ _ |- _] =>
        let ic := fresh "ic" in
        (remember c as ic; destruct ic; dest; subst)
    end.

Ltac invertSemMod H :=
  inv H;
  repeat match goal with
           | [H: Disj _ _ |- _] => clear H
         end.

Ltac invertSemModRep :=
  repeat
    match goal with
      | [H: SemMod _ _ _ _ _ _ _ |- _] => invertSemMod H
    end.

(* dm       : defined methods
   cm       : called methods
   ruleMeth : `None` if it is a method,
              `Some [rulename]` if it is a rule *)

Record RuleLabelT := { ruleMeth: option string;
                       dms: list string;
                       dmMap: CallsT;
                       cms: list string;
                       cmMap: CallsT }.

Hint Unfold ruleMeth dms dmMap cms cmMap.

Definition CombineRm (rm1 rm2 crm: option string) :=
  (rm1 = None \/ rm2 = None) /\
  crm = match rm1, rm2 with
          | Some rn1, None => Some rn1
          | None, Some rn2 => Some rn2
          | _, _ => None
        end.

Definition CallIffDef (l1 l2: RuleLabelT) :=
  (forall m, In m (cms l2) -> InMap m (dmMap l1) -> find m (dmMap l1) = find m (cmMap l2)) /\
  (forall m, In m (dms l1) -> InMap m (cmMap l2) -> find m (dmMap l1) = find m (cmMap l2)) /\
  (forall m, In m (cms l1) -> InMap m (dmMap l2) -> find m (dmMap l2) = find m (cmMap l1)) /\
  (forall m, In m (dms l2) -> InMap m (cmMap l1) -> find m (dmMap l2) = find m (cmMap l1)).

Definition FiltDm (l1 l2 l: RuleLabelT) :=
  dmMap l = disjUnion (complement (dmMap l1) (cms l2))
                      (complement (dmMap l2) (cms l1)) (listSub (dms l1) (cms l2)).

Definition FiltCm (l1 l2 l: RuleLabelT) :=
  cmMap l = disjUnion (complement (cmMap l1) (dms l2))
                      (complement (cmMap l2) (dms l1)) (listSub (cms l1) (dms l2)).

Definition ConcatLabel (l1 l2 l: RuleLabelT) :=
  CombineRm (ruleMeth l1) (ruleMeth l2) (ruleMeth l) /\
  CallIffDef l1 l2 /\ FiltDm l1 l2 l /\ FiltCm l1 l2 l.

Hint Unfold CombineRm CallIffDef FiltDm FiltCm ConcatLabel.

Ltac destConcatLabel :=
  repeat match goal with
           | [H: ConcatLabel _ _ _ |- _] =>
             let Hcrm := fresh "Hcrm" in
             let Hcid := fresh "Hcid" in
             let Hfd := fresh "Hfd" in
             let Hfc := fresh "Hfc" in
             destruct H as [Hcrm [Hcid [Hfd Hfc]]]; clear H; dest;
             unfold ruleMeth in Hcrm
         end.

(* rm = ruleMethod *)
Inductive LtsStep:
  Modules type -> option string -> RegsT -> RegsT -> CallsT -> CallsT -> Prop :=
| LtsStepMod regInits oRegs nRegs rules meths rm dmMap cmMap
             (HOldRegs: InDomain oRegs (map (@attrName _) regInits))
             (Hltsmod: SemMod rules oRegs rm nRegs meths dmMap cmMap):
    LtsStep (Mod regInits rules meths) rm oRegs nRegs dmMap cmMap
| LtsStepConcat m1 rm1 olds1 news1 dmMap1 cmMap1
                m2 rm2 olds2 news2 dmMap2 cmMap2
                (HOldRegs1: InDomain olds1 (map (@attrName _) (getRegInits m1)))
                (HOldRegs2: InDomain olds2 (map (@attrName _) (getRegInits m2)))
                (Hlts1: @LtsStep m1 rm1 olds1 news1 dmMap1 cmMap1)
                (Hlts2: @LtsStep m2 rm2 olds2 news2 dmMap2 cmMap2)
                crm colds cnews cdmMap ccmMap
                (Holds: colds = disjUnion olds1 olds2 (map (@attrName _) (getRegInits m1)))
                (Hnews: cnews = disjUnion news1 news2 (map (@attrName _) (getRegInits m1)))
                (HMerge: ConcatLabel
                           (Build_RuleLabelT rm1 (getDmsMod m1) dmMap1 (getCmsMod m1) cmMap1)
                           (Build_RuleLabelT rm2 (getDmsMod m2) dmMap2 (getCmsMod m2) cmMap2)
                           (Build_RuleLabelT crm (getDmsMod (ConcatMod m1 m2)) cdmMap
                                             (getCmsMod (ConcatMod m1 m2)) ccmMap)):
    LtsStep (ConcatMod m1 m2) crm colds cnews cdmMap ccmMap.

Ltac constr_concatMod :=
  repeat autounfold with ModuleDefs;
  match goal with
    | [ |- LtsStep (ConcatMod ?m1 ?m2) (Some ?r) ?or _ _ _ ] =>
      (let Hvoid := fresh "Hvoid" in
       assert (In r (map (@attrName _) (getRules m1))) as Hvoid by in_tac;
       clear Hvoid;
       eapply LtsStepConcat with
       (olds1 := restrict or (map (@attrName _) (getRegInits m1)))
         (olds2 := complement or (map (@attrName _) (getRegInits m1)))
         (rm1 := Some r) (rm2 := None); eauto)
        || (eapply LtsStepConcat with
            (olds1 := restrict or (map (@attrName _) (getRegInits m1)))
              (olds2 := complement or (map (@attrName _) (getRegInits m1)))
              (rm1 := None) (rm2 := Some r); eauto)
    | [ |- LtsStep (ConcatMod ?m1 ?m2) None _ _ _ _ ] =>
      eapply LtsStepConcat with
      (olds1 := restrict or (map (@attrName _) (getRegInits m1)))
        (olds2 := complement or (map (@attrName _) (getRegInits m1)))
        (rm1 := None) (rm2 := None); eauto
  end.

Hint Extern 1 (LtsStep (Mod _ _ _) _ _ _ _ _) => econstructor.
Hint Extern 1 (LtsStep (ConcatMod _ _) _ _ _ _ _) => constr_concatMod.
Hint Extern 1 (SemMod _ _ _ _ _ _ _) => econstructor.
(* Hint Extern 1 (SemAction _ _ _ _ _) => econstructor. *)
Hint Extern 1 (SemAction _ (Return _) _ _ _) =>
match goal with
  | [ |- SemAction _ _ _ _ ?ret ] =>
    match type of ret with
      | type (Bit 0) => eapply SemReturn with (evale := WO)
      | _ => econstructor
    end
end.

Definition initRegs (init: list RegInitT): RegsT := makeMap type evalConstT init.
Hint Unfold initRegs.

(* m = module
   or = old registers
   nr = new registers *)
Inductive LtsStepClosure:
  Modules type ->
  RegsT -> list RuleLabelT ->
  Prop :=
| lcNil m inits
        (Hinits: inits = (initRegs (getRegInits m))):
    LtsStepClosure m inits nil
| lcLtsStep m rm or nr c cNew dNew or'
            (Hlc: LtsStepClosure m or c)
            (Hlts: LtsStep m rm or nr dNew cNew)
            (Hrs: or' = update or nr):
    LtsStepClosure m or' ((Build_RuleLabelT rm (getDmsMod m) dNew (getCmsMod m) cNew) :: c).

Inductive ConcatLabelSeq: list RuleLabelT -> list RuleLabelT -> list RuleLabelT -> Prop :=
| ConcatNil: ConcatLabelSeq nil nil nil
| ConcatJoin l1 l2 l:
    ConcatLabelSeq l1 l2 l ->
    forall a1 a2 a, ConcatLabel a1 a2 a -> ConcatLabelSeq (a1 :: l1) (a2 :: l2) (a :: l).

Definition RegsInDomain m :=
  forall rm or nr dm cm,
    LtsStep m rm or nr dm cm -> InDomain nr (map (@attrName _) (getRegInits m)).

Lemma concatMod_RegsInDomain:
  forall m1 m2 (Hin1: RegsInDomain m1) (Hin2: RegsInDomain m2),
    RegsInDomain (ConcatMod m1 m2).
Proof.
  unfold RegsInDomain; intros; inv H.
  specialize (Hin1 _ _ _ _ _ Hlts1).
  specialize (Hin2 _ _ _ _ _ Hlts2).
  clear -Hin1 Hin2.
  unfold getRegInits; rewrite map_app.
  unfold InDomain in *; intros.
  unfold InMap, find, disjUnion in H.
  destruct (in_dec string_dec k _).
  - specialize (Hin1 _ H); apply in_or_app; intuition.
  - specialize (Hin2 _ H); apply in_or_app; intuition.
Qed.

Section Domain.
  Variable m: Modules type.
  Variable newRegsDomain: RegsInDomain m.
  Theorem regsDomain r l
    (clos: LtsStepClosure m r l):
    InDomain r (map (@attrName _) (getRegInits m)).
  Proof.
    induction clos.
    - unfold InDomain, InMap, initRegs in *; intros.
      subst.
      clear -H.
      induction (getRegInits m); simpl in *.
      + unfold empty in *; intuition.
      + destruct a; destruct attrType; simpl in *.
        unfold add, unionL, find, string_eq in H.
        destruct (string_dec attrName k); intuition.
    - pose proof (@newRegsDomain _ _ _ _ _ Hlts).
      rewrite Hrs.
      apply InDomainUpd; intuition.
  Qed.
End Domain.

Section WellFormed.
  Variable m1 m2: Modules type.

  Variable newRegsDomainM1: RegsInDomain m1.
  Variable newRegsDomainM2: RegsInDomain m2.

  Variable disjRegs:
    forall r, ~ (In r (map (@attrName _) (getRegInits (type := type) m1)) /\
                 In r (map (@attrName _) (getRegInits (type := type) m2))).
  Variable r: RegsT.
  Variable l: list RuleLabelT.

  Theorem SplitLtsStepClosure:
    LtsStepClosure (ConcatMod m1 m2) r l ->
    exists r1 r2 l1 l2,
      LtsStepClosure m1 r1 l1 /\
      LtsStepClosure m2 r2 l2 /\
      disjUnion r1 r2 (map (@attrName _) (getRegInits m1)) = r /\
      ConcatLabelSeq l1 l2 l.
  Proof.
    intros clos.
    remember (ConcatMod m1 m2) as m.
    induction clos; rewrite Heqm in *; simpl in *.
    - exists (initRegs (getRegInits m1)).
             exists (initRegs (getRegInits m2)).
             unfold initRegs in *.
             rewrite (disjUnionProp (f1 := ConstT) type evalConstT
                                    (getRegInits m1) (getRegInits m2)) in *.
             exists nil; exists nil.
             repeat (constructor || intuition).
    - destruct (IHclos eq_refl) as [r1 [r2 [l1 [l2 [step1 [step2 [regs labels]]]]]]];
      clear IHclos.
      inversion Hlts; subst.
      exists (update olds1 news1).
      exists (update olds2 news2).
      exists ((Build_RuleLabelT rm1 (getDmsMod m1) dmMap1 (getCmsMod m1) cmMap1) :: l1).
      exists ((Build_RuleLabelT rm2 (getDmsMod m2) dmMap2 (getCmsMod m2) cmMap2) :: l2).
      pose proof (regsDomain newRegsDomainM1 step1) as regs1.
      pose proof (regsDomain newRegsDomainM2 step2) as regs2.
      pose proof (DisjUnionEq disjRegs regs1 regs2 HOldRegs1 HOldRegs2 Holds) as [H1 H2].
      subst.
      constructor.
      + apply (lcLtsStep (or' := update olds1 news1) step1 Hlts1 eq_refl).
      + constructor.
        * apply (lcLtsStep (or' := update olds2 news2) step2 Hlts2 eq_refl).
        * { constructor.
            - pose proof newRegsDomainM1 Hlts1 as H1.
              pose proof newRegsDomainM2 Hlts2 as H2.
              apply UpdRewrite.
            - constructor; intuition.
          }
  Qed.
End WellFormed.

(** Tactics for dealing with semantics *)

Ltac destRule Hlts :=
  match type of Hlts with
    | (LtsStep _ ?rm _ _ _ _) =>
      inv Hlts;
        repeat match goal with
                 | [H: SemMod _ _ rm _ _ _ _ |- _] =>
                   destruct rm; [inv H; repeat match goal with
                                                 | [H: In _ _ |- _] => inv H
                                               end|]
                 | [H: {| attrName := _; attrType := _ |} =
                       {| attrName := _; attrType := _ |} |- _] => inv H
               end
  end.

Ltac destRuleRep :=
  repeat match goal with
           | [H: LtsStep _ _ _ _ _ _ |- _] => destRule H
         end.

Ltac combRule :=
  match goal with
    | [H: CombineRm (Some _) (Some _) _ |- _] =>
      unfold CombineRm in H; destruct H as [[H|H] _]; inversion H
    | [H: CombineRm None (Some _) _ |- _] =>
      unfold CombineRm in H; destruct H as [_]; subst
    | [H: CombineRm (Some _) None _ |- _] =>
      unfold CombineRm in H; destruct H as [_]; subst
    | [H: CombineRm None None _ |- _] =>
      unfold CombineRm in H; destruct H as [_]; subst
  end.

Ltac callIffDef_dest :=
  repeat
    match goal with
      | [H: CallIffDef _ _ |- _] => unfold CallIffDef in H; dest
    end;
  unfold dmMap, cmMap, dms, cms in *.

Ltac filt_dest :=
  repeat
    match goal with
      | [H: FiltDm _ _ _ |- _] =>
        unfold FiltDm in H;
          unfold dmMap, cmMap, dms, cms in H;
          subst
      | [H: FiltCm _ _ _ |- _] =>
        unfold FiltCm in H;
          unfold dmMap, cmMap, dms, cms in H;
          subst
    end.

Lemma opt_some_eq: forall {A} (v1 v2: A), Some v1 = Some v2 -> v1 = v2.
Proof. intros; inv H; reflexivity. Qed.

Lemma typed_eq:
  forall {A} (a: A) (B: A -> Type) (v1 v2: B a),
    {| objType := a; objVal := v1 |} = {| objType := a; objVal := v2 |} ->
    v1 = v2.
Proof. intros; inv H; apply Eqdep.EqdepTheory.inj_pair2 in H1; assumption. Qed.

Ltac basic_dest :=
  repeat
    match goal with
      | [H: Some _ = Some _ |- _] => try (apply opt_some_eq in H; subst)
      | [H: {| objType := _; objVal := _ |} = {| objType := _; objVal := _ |} |- _] =>
        try (apply typed_eq in H; subst)
      | [H: (_, _) = (_, _) |- _] => inv H; subst
      | [H: existT _ _ _ = existT _ _ _ |- _] =>
        try (apply Eqdep.EqdepTheory.inj_pair2 in H; subst)
      | [H: Some _ = None |- _] => inversion H
      | [H: None = Some _ |- _] => inversion H
      | [H: true = false |- _] => inversion H
      | [H: false = true |- _] => inversion H
    end.

Ltac pred_dest meth :=
  repeat
    match goal with
      | [H: forall m: string, In m nil -> InMap m _ -> find m _ = find m _ |- _] =>
        clear H
      | [H: forall m: string, In m _ -> InMap m empty -> find m _ = find m _ |- _] =>
        clear H
    end;
  repeat
    match goal with
      | [H: forall m: string, In m _ -> InMap m _ -> find m _ = find m _ |- _] =>
        let Hin := type of (H meth) in
        isNew Hin; let Hs := fresh "Hs" in pose proof (H meth) as Hs
    end;
  repeat
    match goal with
      | [H: In ?m ?l -> InMap ?m _ -> find ?m _ = find ?m _ |- _] =>
        (let Hp := fresh "Hp" in
         assert (Hp: In m l) by (repeat autounfold; repeat autounfold with ModuleDefs; in_tac_ex);
         specialize (H Hp); clear Hp)
          || (clear H)
    end;
  repeat
    match goal with
      | [H: InMap ?m _ -> find ?m _ = find ?m _ |- _] => unfold InMap in H
      | [H: (Some _ = None -> False) -> _ |- _] => specialize (H (opt_discr _))
      | [H: (Some _ <> None) -> _ |- _] => specialize (H (opt_discr _))
      | [H: (None <> None) -> _ |- _] => clear H
      | [H: find _ _ = Some _ |- _] => repeat autounfold in H; map_compute H
      | [H: find _ _ = None |- _] => repeat autounfold in H; map_compute H
      | [H: find _ _ <> _ -> _ |- _] => repeat autounfold in H; map_compute H
      | [H: find _ _ <> _ |- _] => repeat autounfold in H; map_compute H
      | [H1: find _ _ <> _ -> _, H2: find _ _ <> _ |- _] =>
        progress (specialize (H1 H2))
    end.

Ltac invariant_tac :=
  repeat
    match goal with
      | [H: find _ _ = Some _ |- _] => progress (map_simpl H)
      | [H1: ?lh = Some _, H2: ?lh = Some _ |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: ?lh = Some _, H2: Some _ = ?lh |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: ?lh = true, H2: ?lh = false |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: ?lh = true, H2: false = ?lh |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: ?lh = false, H2: true = ?lh |- _] =>
        simpl in H1, H2; rewrite H1 in H2
      | [H1: if weq ?w1 ?w2 then _ else _, H2: ?w1 = ?w3 |- _] =>
        rewrite H2 in H1; simpl in H1
      | [H: ?w1 = ?w3 |- context [if weq ?w1 ?w2 then _ else _] ] =>
        rewrite H; simpl
    end.

Ltac conn_tac meth :=
  callIffDef_dest; filt_dest; pred_dest meth; repeat (invariant_tac; basic_dest).
Ltac fconn_tac meth := exfalso; conn_tac meth.

