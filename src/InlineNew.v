Require Import Bool List String.
Require Import Lib.CommonTactics Lib.Struct Lib.StringBound Lib.ilist Lib.Word Lib.FMap.
Require Import Syntax Wf Equiv.

Require Import FunctionalExtensionality.

Set Implicit Arguments.

Section PhoasUT.
  Definition typeUT (k: Kind): Type := unit.
  Definition fullTypeUT := fullType typeUT.
  Definition getUT (k: FullKind): fullTypeUT k :=
    match k with
      | SyntaxKind _ => tt
      | NativeKind t c => c
    end.

  Fixpoint getCalls {retT} (a: ActionT typeUT retT) (cs: list DefMethT)
  : list DefMethT :=
    match a with
      | MCall name _ _ cont =>
        match getAttribute name cs with
          | Some dm => dm :: (getCalls (cont tt) cs)
          | None => getCalls (cont tt) cs
        end
      | Let_ _ ar cont => getCalls (cont (getUT _)) cs
      | ReadReg reg k cont => getCalls (cont (getUT _)) cs
      | WriteReg reg _ e cont => getCalls cont cs
      | IfElse ce _ ta fa cont =>
        (getCalls ta cs) ++ (getCalls fa cs) ++ (getCalls (cont tt) cs)
      | Assert_ ae cont => getCalls cont cs
      | Return e => nil
    end.

  Lemma getCalls_nil: forall {retT} (a: ActionT typeUT retT), getCalls a nil = nil.
  Proof.
    induction a; intros; simpl; intuition.
    rewrite IHa1, IHa2, (H tt); reflexivity.
  Qed.

  Lemma getCalls_sub: forall {retT} (a: ActionT typeUT retT) cs ccs,
                        getCalls a cs = ccs -> SubList ccs cs.
  Proof.
    induction a; intros; simpl; intuition; try (eapply H; eauto; fail).
    - simpl in H0.
      remember (getAttribute meth cs); destruct o.
      + pose proof (getAttribute_Some_body _ _ Heqo); subst.
        unfold SubList; intros.
        inv H0; [assumption|].
        eapply H; eauto.
      + eapply H; eauto.
    - simpl in H0; subst.
      unfold SubList; intros.
      apply in_app_or in H0; destruct H0; [|apply in_app_or in H0; destruct H0].
      + eapply IHa1; eauto.
      + eapply IHa2; eauto.
      + eapply H; eauto.
    - simpl in H; subst.
      unfold SubList; intros; inv H.
  Qed.

  Lemma getCalls_sub_name: forall {retT} (a: ActionT typeUT retT) cs ccs,
                             getCalls a cs = ccs -> SubList (namesOf ccs) (namesOf cs).
  Proof.
    induction a; intros; simpl; intuition; try (eapply H; eauto; fail).
    - simpl in H0.
      remember (getAttribute meth cs); destruct o.
      + pose proof (getAttribute_Some_body _ _ Heqo); subst.
        unfold SubList; intros.
        inv H0; [apply in_map; auto|].
        eapply H; eauto.
      + eapply H; eauto.
    - simpl in H0; subst.
      unfold SubList; intros.
      unfold namesOf in H0; rewrite map_app in H0.
      apply in_app_or in H0; destruct H0.
      + eapply IHa1; eauto.
      + rewrite map_app in H0; apply in_app_or in H0; destruct H0.
        * eapply IHa2; eauto.
        * eapply H; eauto.
    - simpl in H; subst.
      unfold SubList; intros; inv H.
  Qed.

  Section Exts.
    Definition getRuleCalls (r: Attribute (Action Void)) (cs: list DefMethT)
    : list DefMethT :=
      getCalls (attrType r typeUT) cs.

    Fixpoint getMethCalls (dms: list DefMethT) (cs: list DefMethT)
    : list DefMethT :=
      match dms with
        | nil => nil
        | dm :: dms' =>
          (getCalls (objVal (attrType dm) typeUT tt) cs)
            ++ (getMethCalls dms' cs)
      end.
  End Exts.

  Section Tree.
    Fixpoint isLeaf {retT} (a: ActionT typeUT retT) (cs: list string) :=
      match a with
        | MCall name _ _ cont =>
          if in_dec string_dec name cs then false else isLeaf (cont tt) cs
        | Let_ _ ar cont => isLeaf (cont (getUT _)) cs
        | ReadReg reg k cont => isLeaf (cont (getUT _)) cs
        | WriteReg reg _ e cont => isLeaf cont cs
        | IfElse ce _ ta fa cont => (isLeaf ta cs) && (isLeaf fa cs) && (isLeaf (cont tt) cs)
        | Assert_ ae cont => isLeaf cont cs
        | Return e => true
      end.

    Definition noCallDm (dm: DefMethT) (tgt: DefMethT) :=
      isLeaf (objVal (attrType dm) typeUT tt) [attrName tgt].

    Fixpoint noCallDms (dms: list DefMethT) (tgt: DefMethT) :=
      match dms with
        | nil => true
        | dm :: dms' =>
          if noCallDm dm tgt
          then noCallDms dms' tgt
          else false
      end.

    Fixpoint noCallRules (rules: list (Attribute (Action Void)))
             (tgt: DefMethT) :=
      match rules with
        | nil => true
        | r :: rules' =>
          if isLeaf (attrType r typeUT) [attrName tgt]
          then noCallRules rules' tgt
          else false
      end.

    Fixpoint noCall (m: Modules) (tgt: DefMethT) :=
      match m with
        | Mod _ rules dms =>
          (noCallRules rules tgt) && (noCallDms dms tgt)
        | ConcatMod m1 m2 => (noCall m1 tgt) && (noCall m2 tgt)
      end.

    Fixpoint noCalls' (m: Modules) (dms: list DefMethT) :=
      match dms with
        | nil => true
        | dm :: dms' =>
          (noCall m dm) && (noCalls' m dms')
      end.

    Definition noCalls (m: Modules) :=
      noCalls' m (getDmsBodies m).

  End Tree.

End PhoasUT.

Section Base.
  Variable type: Kind -> Type.

  Definition inlineArg {argT retT} (a: Expr type (SyntaxKind argT))
             (m: type argT -> ActionT type retT): ActionT type retT :=
    Let_ a m.

  Fixpoint getMethod (n: string) (dms: list DefMethT) :=
    match dms with
      | nil => None
      | {| attrName := mn; attrType := mb |} :: dms' =>
        if string_dec n mn then Some mb else getMethod n dms'
    end.
  
  Definition getBody (n: string) (dm: DefMethT) (sig: SignatureT):
    option (sigT (fun x: DefMethT => objType (attrType x) = sig)) :=
    if string_dec n (attrName dm) then
      match SignatureT_dec (objType (attrType dm)) sig with
        | left e => Some (existT _ dm e)
        | right _ => None
      end
    else None.

  Fixpoint inlineDm {retT} (a: ActionT type retT) (dm: DefMethT): ActionT type retT :=
    match a with
      | MCall name sig ar cont =>
        match getBody name dm sig with
          | Some (existT dm e) =>
            appendAction (inlineArg ar ((eq_rect _ _ (objVal (attrType dm)) _ e)
                                          type))
                         (fun ak => inlineDm (cont ak) dm)
          | None => MCall name sig ar (fun ak => inlineDm (cont ak) dm)
        end
      | Let_ _ ar cont => Let_ ar (fun a => inlineDm (cont a) dm)
      | ReadReg reg k cont => ReadReg reg k (fun a => inlineDm (cont a) dm)
      | WriteReg reg _ e cont => WriteReg reg e (inlineDm cont dm)
      | IfElse ce _ ta fa cont => IfElse ce (inlineDm ta dm) (inlineDm fa dm)
                                         (fun a => inlineDm (cont a) dm)
      | Assert_ ae cont => Assert_ ae (inlineDm cont dm)
      | Return e => Return e
    end.

End Base.

Section Exts.
  Definition inlineDmToRule (r: Attribute (Action Void)) (leaf: DefMethT)
  : Attribute (Action Void) :=
    {| attrName := attrName r;
       attrType := fun type => inlineDm (attrType r type) leaf |}.

  Definition inlineDmToRules (rules: list (Attribute (Action Void))) (leaf: DefMethT) :=
    map (fun r => inlineDmToRule r leaf) rules.

  Definition inlineDmToDm (dm leaf: DefMethT): DefMethT.
    refine {| attrName := attrName dm;
              attrType := {| objType := objType (attrType dm);
                             objVal := _ |} |}.
    unfold MethodT; intros.
    exact (inlineDm (objVal (attrType dm) ty X) leaf).
  Defined.

  Definition inlineDmToDms (dms: list DefMethT) (leaf: DefMethT) :=
    map (fun d => inlineDmToDm d leaf) dms.

  Fixpoint inlineDmToMod (m: Modules) (leaf: string) :=
    match getAttribute leaf (getDmsBodies m) with
      | Some dm =>
        if noCallDm dm dm then
          match m with
            | Mod regs rules dms =>
              Mod regs (inlineDmToRules rules dm) (inlineDmToDms dms dm)
            | ConcatMod m1 m2 =>
              ConcatMod (inlineDmToMod m1 leaf) (inlineDmToMod m2 leaf)
          end
        else m
      | None => m
    end.

  Fixpoint inlineDms' (m: Modules) (dms: list string) :=
    match dms with
      | nil => m
      (* | dm :: dms' => inlineDmToMod (inlineDms' m dms') dm *)
      | dm :: dms' => inlineDms' (inlineDmToMod m dm) dms'
    end.

  Definition inlineDms (m: Modules) := inlineDms' m (namesOf (getDmsBodies m)).

  Definition merge (m: Modules) := Mod (getRegInits m) (getRules m) (getDmsBodies m).
  Definition filterDms (dms: list DefMethT) (filt: list string) :=
    filter (fun dm => if in_dec string_dec (attrName dm) filt then false else true) dms.
  Definition inline (m: Modules) :=
    let mm := merge m in
    let im := inlineDms mm in
    Mod (getRegInits im) (getRules im) (filterDms (getDmsBodies im) (getCmsMod m)).

End Exts.

Require Import SemanticsNew.

Section HideExts.
  Definition hideMeth {A} (l: LabelTP A) (dmn: string) (m: Modules): LabelTP A :=
    match getAttribute dmn (getDmsBodies m) with
      | Some dm =>
        if noCallDm dm dm then
          match M.find dmn (dms l), M.find dmn (cms l) with
            | Some v1, Some v2 =>
              match signIsEq v1 v2 with
                | left _ => {| ruleMeth := ruleMeth l;
                               dms := M.remove dmn (dms l);
                               cms := M.remove dmn (cms l) |}
                | _ => l
              end
            | _, _ => l
          end
        else l
      | _ => l
    end.

  Fixpoint hideMeths {A} (l: LabelTP A) (dms: list string) (m: Modules): LabelTP A :=
    match dms with
      | nil => l
      (* | dm :: dms' => hideMeth (hideMeths l dms' m) dm m *)
      | dm :: dms' => hideMeths (hideMeth l dm m) dms' (inlineDmToMod m dm)
    end.

  Definition wellHiddenMeth {A} (l: LabelTP A) (dm: string) :=
    M.find dm (dms l) = None /\ M.find dm (cms l) = None.

  Lemma hideMeth_preserves_hide:
    forall {A} (l: LabelTP A) dm m,
      hide (hideMeth l dm m) = hide l.
  Proof.
    intros; destruct l as [rm dms cms].
    admit.
  Qed.

  Lemma wellHidden_wellHiddenMeth:
    forall {A} m (l: LabelTP A) dm,
      In dm (namesOf (getDmsBodies m)) ->
      wellHidden (hide l) m ->
      wellHiddenMeth (hideMeth l dm m) dm.
  Proof.
    admit.
  Qed.

  Lemma wellHiddenMeth_find:
    forall {A} (l: LabelTP A) dm m,
      wellHiddenMeth (hideMeth l dm m) dm <->
      M.find dm (dms l) = M.find dm (cms l).
  Proof.
    admit. (* easy *)
  Qed.

End HideExts.

Section Facts.

  Lemma inlineDm_SemAction_intact:
    forall {retK} dmn dmb or a nr calls (retV: Semantics.type retK),
      Semantics.SemAction or a nr calls retV ->
      None = M.find dmn calls ->
      Semantics.SemAction or (inlineDm a (dmn :: dmb)%struct) nr calls retV.
  Proof.
    admit. (* Semantics proof *)
  Qed.

  Lemma noCallDm_SemAction_calls:
    forall mn mb or nr calls argV retV,
      noCallDm (mn :: mb)%struct (mn :: mb)%struct = true ->
      Semantics.SemAction or (objVal mb Semantics.type argV) nr calls retV ->
      M.find (elt:=Typed Semantics.SignT) mn calls = None.
  Proof.
    admit. (* Semantics proof *)
  Qed.

  (* NOTE: inlining should be targeted only for basic modules *)
  Definition BasicMod (m: Modules) :=
    match m with
      | Mod _ _ _ => True
      | _ => False
    end.

  Lemma inlineDmToMod_correct_UnitStep_1:
    forall m (Hm: BasicMod m) (Hdms: NoDup (namesOf (getDmsBodies m))) dm or u l,
      UnitStep m or u l ->
      M.find dm (dms l) = M.find dm (cms l) ->
      UnitStep (inlineDmToMod m dm) or u (hideMeth l dm m).
  Proof.
    induction 3; intros; simpl in *.

    - unfold hideMeth; simpl.
      destruct (getAttribute dm meths); try destruct (noCallDm a a);
      constructor; auto.

    - unfold hideMeth; simpl.
      remember (getAttribute dm meths) as odm; destruct odm; [|eapply SingleRule; eauto].
      remember (noCallDm a a) as ocall; destruct ocall; [|eapply SingleRule; eauto].
      pose proof (getAttribute_Some_name _ _ Heqodm); subst.
      
      apply SingleRule with
      (ruleBody:= attrType (inlineDmToRule (ruleName :: ruleBody)%struct a))
        (retV:= retV); auto.
      + apply in_map with (f:= fun r => inlineDmToRule r a) in i.
        assumption.
      + simpl; rewrite MF.find_empty in H.
        destruct a; apply inlineDm_SemAction_intact; auto.

    - admit. (* proof deprecated due to the change of hideMeth *)

      (* remember (getAttribute dm meths) as odm; destruct odm; *)
      (* [|elim (getAttribute_None _ _ Heqodm); apply in_map; auto]. *)
      (* destruct dm as [dmn dmb]; simpl in *. *)
      (* rewrite <-(in_NoDup_getAttribute _ _ _ H H0) in Heqodm. *)
      (* inv Heqodm. *)

      (* destruct (string_dec dmn meth). *)
      (* + subst; exfalso. *)
      (*   destruct meth as [mn mb]; simpl in *. *)
      (*   rewrite MF.find_add_1 in H2. *)
      (*   assert (mb = dmb) by admit; subst. (* NoDup property *) *)
      (*   rewrite (noCallDm_SemAction_calls _ _ _ H1 s) in H2. *)
      (*   discriminate. *)
      (* + unfold hideMeth; simpl. *)
      (*   rewrite MF.find_add_2 by assumption. *)
      (*   rewrite MF.find_empty. *)
      (*   apply SingleMeth with (meth:= inlineDmToDm meth (dmn :: dmb)%struct) *)
      (*                           (argV:= argV) (retV:= retV); auto. *)
      (*   * apply in_map with (f:= fun dm => inlineDmToDm dm (dmn :: dmb)%struct) in i. *)
      (*     assumption. *)
      (*   * simpl. *)
      (*     rewrite MF.find_add_2 in H2 by assumption. *)
      (*     rewrite MF.find_empty in H2. *)
      (*     apply inlineDm_SemAction_intact; auto. *)

    - exfalso; auto.
    - exfalso; auto.
  Qed.

  (* Lemma inlineDmToMod_correct_UnitSteps_sub: *)
  (*   forall m or u1 u2 rm1 rm2 dm1 dm2 cm1 cm2 (dm: DefMethT) t l1 l2, *)
  (*     l1 = {| ruleMeth := rm1; dms := dm1; cms := cm1 |} -> *)
  (*     l2 = {| ruleMeth := rm2; dms := dm2; cms := cm2 |} -> *)
  (*     UnitSteps m or u1 l1 -> UnitSteps m or u2 l2 -> *)
  (*     MF.Disj u1 u2 -> NotBothRule rm1 rm2 -> MF.Disj dm1 dm2 -> MF.Disj cm1 cm2 -> *)
  (*     Some t = M.find dm dm1 -> Some t = M.find dm cm2 -> *)
  (*     UnitSteps (inlineDmToMod m dm) or (MF.union u1 u2) *)
  (*               {| ruleMeth := match rm1 with *)
  (*                                | Some r => Some r *)
  (*                                | None => rm2 *)
  (*                              end; *)
  (*                  dms := M.remove (elt:=Typed Semantics.SignT) dm (MF.union dm1 dm2); *)
  (*                  cms := M.remove (elt:=Typed Semantics.SignT) dm (MF.union cm1 cm2) |}. *)
  (* Proof. *)
  (*   admit. *)
  (* Qed. *)

  Lemma inlineDmToMod_correct_UnitSteps:
    forall m (Hm: BasicMod m) or nr l dm,
      NoDup (namesOf (getDmsBodies m)) ->
      UnitSteps m or nr l ->
      M.find dm (dms l) = M.find dm (cms l) ->
      UnitSteps (inlineDmToMod m dm) or nr (hideMeth l dm m).
  Proof.
    induction 3; intros; [constructor; apply inlineDmToMod_correct_UnitStep_1; auto|].

    destruct l1 as [rm1 dm1 cm1], l2 as [rm2 dm2 cm2]; simpl in *.
    remember (M.find dm (MF.union dm1 dm2)) as odmv.
    destruct odmv.

    - unfold hideMeth; simpl.
      rewrite <-Heqodmv, <-H0; simpl.
      destruct (signIsEq t t); [clear e|elim n; auto].
      unfold CanCombine in c; dest; simpl in *.
      rewrite MF.find_union in Heqodmv; rewrite MF.find_union in H0.
      remember (M.find dm dm1) as odmv1; destruct odmv1.

      + inv Heqodmv.
        remember (M.find dm cm1) as ocmv1; destruct ocmv1.
        * inv H0; specialize (IHX1 eq_refl).
          admit. (* one-side inlined *)
        * admit. (* eapply inlineDmToMod_correct_UnitSteps_sub; eauto. *)

    + remember (M.find dm cm1) as ocmv1; destruct ocmv1.
      * clear IHX1 IHX2; inv H0.
        replace (MF.union u1 u2) with (MF.union u2 u1)
          by (apply MF.union_comm; apply MF.Disj_comm; auto).
        replace (match rm1 with | Some r => Some r | None => rm2 end) with
        (match rm2 with | Some r => Some r | None => rm1 end)
          by (destruct rm1, rm2; intuition idtac; destruct H2; discriminate).
        replace (MF.union dm1 dm2) with (MF.union dm2 dm1)
          by (apply MF.union_comm; apply MF.Disj_comm; auto).
        replace (MF.union cm1 cm2) with (MF.union cm2 cm1)
          by (apply MF.union_comm; apply MF.Disj_comm; auto).
        (* eapply inlineDmToMod_correct_UnitSteps_sub; eauto; try (apply MF.Disj_comm; auto). *)
        (* destruct H3; unfold NotBothRule; intuition auto. *)
        admit.
      * specialize (IHX1 eq_refl).
        admit. (* one-side inlined *)

    - unfold hideMeth in *; simpl in *; rewrite <-Heqodmv.
      rewrite MF.find_union in Heqodmv.
      destruct (M.find dm dm1); [discriminate|].
      destruct (M.find dm dm2); [discriminate|].
      rewrite MF.find_union in H0.
      destruct (M.find dm cm1); [discriminate|].
      destruct (M.find dm cm2); [discriminate|].
      specialize (IHX1 eq_refl); specialize (IHX2 eq_refl).

      destruct (getAttribute dm (getDmsBodies m));
        try destruct (noCallDm a a);
        match goal with
            [ |- UnitSteps _ _ _ ?l] =>
            replace l with (mergeLabel {| ruleMeth:= rm1; dms:= dm1; cms:= cm1 |}
                                       {| ruleMeth:= rm2; dms:= dm2; cms:= cm2 |})
              by reflexivity
        end;
        apply UnitStepsUnion; auto.
  Qed.

  Lemma inlineDmToMod_wellHidden:
    forall {A} (l: LabelTP A) m a,
      wellHidden l m ->
      wellHidden l (inlineDmToMod m a).
  Proof.
    admit. (* Inlining proof *)
  Qed.

  Lemma inlineDms'_correct_UnitSteps:
    forall cdms m (Hm: BasicMod m) (Hdms: NoDup (namesOf (getDmsBodies m)))
           (Hcdms: SubList cdms (namesOf (getDmsBodies m)))
           or nr l,
      UnitSteps m or nr l ->
      wellHidden (hide l) m ->
      UnitSteps (inlineDms' m cdms) or nr (hideMeths l cdms m).
  Proof.
    induction cdms; [auto|].
    intros; simpl.

    apply SubList_cons_inv in Hcdms; dest.

    apply IHcdms; auto.
    - admit. (* easy *)
    - admit. (* easy *)
    - admit. (* easy *)
    - apply inlineDmToMod_correct_UnitSteps; auto.
      apply (proj1 (wellHiddenMeth_find _ _ m)).
      apply wellHidden_wellHiddenMeth; auto.
    - apply inlineDmToMod_wellHidden.
      rewrite hideMeth_preserves_hide; auto.
  Qed.

  Lemma hideMeths_UnitSteps_hide:
    forall m or nr l,
      UnitSteps m or nr l ->
      hideMeths l (namesOf (getDmsBodies m)) m = hide l.
  Proof.
    admit. (* not trivial; dig into this first *)
  Qed.

  Lemma inlineDms_correct_UnitSteps:
    forall m (Hm: BasicMod m) (Hdms: NoDup (namesOf (getDmsBodies m))) or nr l,
      UnitSteps m or nr l ->
      wellHidden (hide l) m ->
      UnitSteps (inlineDms m) or nr (hide l).
  Proof.
    intros.
    erewrite <-hideMeths_UnitSteps_hide; eauto.
    apply inlineDms'_correct_UnitSteps; auto.
    apply SubList_refl.
  Qed.

  Lemma inlineDms_wellHidden:
    forall {A} (l: LabelTP A) m,
      wellHidden l m ->
      wellHidden l (inlineDms m).
  Proof.
    intros; unfold inlineDms.
    remember (namesOf (getDmsBodies m)) as dms; clear Heqdms.
    generalize dependent m; induction dms; intros; [assumption|].
    apply IHdms; auto.
    apply inlineDmToMod_wellHidden; auto.
  Qed.

  Lemma hide_idempotent:
    forall {A} (l: LabelTP A), hide l = hide (hide l).
  Proof.
    admit. (* Semantics proof *)
  Qed.

  Lemma inlineDms_correct:
    forall m (Hm: BasicMod m) (Hdms: NoDup (namesOf (getDmsBodies m))) or nr l,
      Step m or nr l ->
      Step (inlineDms m) or nr l.
  Proof.
    induction 3; intros.
    subst; pose proof (inlineDms_correct_UnitSteps Hm Hdms u w).

    apply MkStep with (l:= hide l); auto.
    - apply hide_idempotent.
    - apply inlineDms_wellHidden; auto.
  Qed.

  Lemma merge_preserves_step:
    forall m or nr l,
      Step m or nr l ->
      Step (merge m) or nr l.
  Proof.
    admit. (* Semantics proof *)
  Qed.

  Lemma filter_preserves_step:
    forall regs rules dmsAll or nr l filt,
      Step (Mod regs rules dmsAll) or nr l ->
      MF.NotOnDomain (dms l) filt ->
      Step (Mod regs rules (filterDms dmsAll filt)) or nr l.
  Proof.
    admit. (* Semantics proof *)
  Qed.

  Theorem inline_correct:
    forall m (Hdms: NoDup (namesOf (getDmsBodies m))) or nr l,
      Step m or nr l ->
      Step (inline m) or nr l.
  Proof.
    intros; unfold inline.
    apply filter_preserves_step; [|admit (* Semantics proof *)].
    apply merge_preserves_step.
    apply inlineDms_correct.
    - unfold BasicMod, merge; auto.
    - admit. (* easy *)
    - apply merge_preserves_step; auto.
  Qed.

End Facts.
