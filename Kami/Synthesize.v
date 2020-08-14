Require Import Kami.Syntax Lib.Struct List String Kami.Notations.

Set Implicit Arguments.
Set Asymmetric Patterns.

Definition tyS: Kind -> Type := fun _ => nat.

Definition ExprS := Expr tyS.

Inductive ActionS (lretT: Kind) : Type :=
| MCallS (meth: string) s:
    ExprS (SyntaxKind (arg s)) ->
    nat ->
    ActionS lretT ->
    ActionS lretT
| LetS_ lretT': ExprS lretT' -> nat -> ActionS lretT -> ActionS lretT
| ReadNondetS:
    nat -> ActionS lretT -> ActionS lretT
| ReadRegS (r: string):
    nat -> ActionS lretT -> ActionS lretT
| WriteRegS (r: string) k:
    ExprS k -> ActionS lretT -> ActionS lretT
| IfElseS: ExprS (SyntaxKind Bool) -> forall k,
      ActionS k ->
      ActionS k ->
      nat ->
      ActionS lretT ->
      ActionS lretT
| AssertS_: ExprS (SyntaxKind Bool) -> ActionS lretT -> ActionS lretT
| ReturnS: ExprS (SyntaxKind lretT) -> ActionS lretT.

Fixpoint getActionS (n: nat) lret (a: ActionT tyS lret) {struct a}
  : (nat * ActionS lret) :=
  match a with
  | MCall meth s e c =>
    let (m, a') := @getActionS (S n) _ (c n) in
    (m, MCallS meth s e n a')
  | Let_ lret' e cn =>
    match lret' return (nat * ActionS lret) -> nat * ActionS lret with
    | SyntaxKind k => fun v => (fst v,
                                LetS_ e n (snd v))
    | NativeKind _ _ => fun _ => (n, ReturnS (Const tyS (getDefaultConst _)))
    end (@getActionS (S n) _ (cn match lret' with
                                 | SyntaxKind k => n
                                 | NativeKind t c => c
                                 end))
  | ReadNondet k cn =>
    match k return (nat * ActionS lret) -> nat * ActionS lret with
    | SyntaxKind k => fun v => (fst v,
                                ReadNondetS n (snd v))
    | NativeKind _ _ => fun _ => (n, ReturnS (Const tyS (getDefaultConst _)))
    end (@getActionS (S n) _ (cn match k with
                                 | SyntaxKind _ => n
                                 | NativeKind t c => c
                                 end))
  | ReadReg r k cn =>
    match k return (nat * ActionS lret) -> nat * ActionS lret with
    | SyntaxKind k => fun v => (fst v,
                                ReadRegS r n (snd v))
    | NativeKind _ _ => fun _ => (n, ReturnS (Const tyS (getDefaultConst _)))
    end (@getActionS (S n) _ (cn match k with
                                 | SyntaxKind _ => n
                                 | NativeKind t c => c
                                 end))
  | WriteReg r _ e c =>
    let (m, a') := @getActionS n _ c in
    (m, WriteRegS r e a')
  | IfElse e _ ta fa c =>
    let (tm, ta') := @getActionS n _ ta in
    let (fm, fa') := @getActionS tm _ fa in
    let (m, a') := @getActionS (S fm) _ (c fm) in
    (m, IfElseS e ta' fa' fm a')
  | Assert_ e c =>
    let (m, a') := @getActionS n _ c in
    (m, AssertS_ e a')
  | Displ ls c => @getActionS n _ c
  | Return e => (n, ReturnS e)
  end.

Definition MethodTS sig := ActionS (ret sig).

Definition DefMethTS := Attribute (sigT MethodTS).

Record PrimitiveModuleS :=
  { pms_name: string;
    (* [pm_args] is not used in Kami at all;
     * it's just to provide information to the pretty-printer. *)
    pms_args: list (Attribute Kind);
    pms_regInits: list RegInitT;
    pms_rules: list (Attribute (ActionS Void));
    pms_methods: list DefMethTS }.

Inductive ModulesS: Type :=
| PrimModS (prim: PrimitiveModuleS)
| ModS (regs: list RegInitT)
       (rules: list (Attribute (ActionS Void)))
       (dms: list DefMethTS)
| ConcatModsS (m1 m2: ModulesS).

Definition getMethS (x: sigT MethodT): sigT MethodTS :=
  match x with
  | existT arg meth => existT _ arg (snd (getActionS 1 (meth tyS 0)))
  end.

Fixpoint getModuleS (m: Modules): ModulesS :=
  match m with
  | PrimMod prim =>
    PrimModS {| pms_name := pm_name prim;
                pms_args := pm_args prim;
                pms_regInits := pm_regInits prim;
                pms_rules :=
                  map (fun a: Attribute (Action Void) =>
                         (attrName a :: snd (getActionS 0 (attrType a tyS)))%struct)
                      (pm_rules prim);
                pms_methods :=
                  map (fun a => (attrName a :: getMethS (attrType a))%struct)
                      (pm_methods prim) |}
  | Mod regs rules dms =>
    ModS regs
         (map (fun a: Attribute (Action Void) =>
                 (attrName a :: snd (getActionS 0 (attrType a tyS)))%struct)
              rules)
         (map (fun a => (attrName a :: getMethS (attrType a))%struct) dms)
  | ConcatMod m1 m2 =>
    ConcatModsS (getModuleS m1) (getModuleS m2)
  end.
