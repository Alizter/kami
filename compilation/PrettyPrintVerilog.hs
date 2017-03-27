import Target
import Data.List
import Data.List.Split
import Control.Monad.State.Lazy

ppVecLen :: Int -> String
ppVecLen n = "[" ++ show (2^n-1) ++ ":0]"

finToInt :: T -> Int
finToInt (F1 _) = 0
finToInt (FS _ x) = succ (finToInt x)

vectorToList :: T0 a -> [a]
vectorToList Nil = []
vectorToList (Cons x _ xs) = x : vectorToList xs

ilistToList :: Ilist a b -> [b]
ilistToList Inil = []
ilistToList (Icons _ _ _ b vs) = b: ilistToList vs

vecToList :: Vec a -> [a]
vecToList (Vec0 a) = [a]
vecToList (VecNext _ xs ys) = vecToList xs ++ vecToList ys

{-
instance Show a => Show (Attribute a) where
  show (Build_Attribute x y) = "(" ++ show x ++ ", " ++ show y ++ ")"

instance Show Kind where
  show Bool = "Bool"
  show (Bit n) = "(Bit " ++ show n ++ ")"
  show (Vector k i) = "(Vector " ++ show k ++ " " ++ show i ++ ")"
  show (Struct n vec) = "(Struct " ++ show (vectorToList vec) ++ ")"
-}

ppType1 :: Kind -> String
ppType1 (Struct _ _) = "struct packed "
ppType1 _ = "logic "

ppType2 :: Kind -> String
ppType2 Bool = ""
ppType2 (Bit i) = if i > 0
                  then "[" ++ show (i-1) ++ ":0]"
                  else ""
ppType2 (Vector k i) = ppVecLen i ++ ppType2 k
ppType2 (Struct n v) = '{' : concatMap (\x -> ppDeclType (ppName $ attrName x) (attrType x) ++ "; ") (vectorToList v) ++ "}"

ppName :: String -> String
ppName s =
  map (\x -> case x of
               '#' -> '$'
               c -> c)
  (if elem '.' s
   then concat $ case splitOneOf ".#" s of
                   x : y : xs -> y : x : xs
                   ys -> ys
   else s)


ppDeclType :: String -> Kind -> String
ppDeclType s k = ppType1 k ++ ppType2 k ++ " " ++ s

ppPrintVar :: (String, [Int]) -> String
ppPrintVar (s, vs) = ppName $ s ++ concatMap (\v -> '#' : show v) vs

ppWord :: [Bool] -> String
ppWord [] = []
ppWord (b : bs) = (if b then '1' else '0') : ppWord bs

ppConst :: ConstT -> String
ppConst (ConstBool b) = if b then "1'b1" else "1'b0"
ppConst (ConstBit sz w) = if sz == 0 then "1'b0" else show sz ++ "\'b" ++ ppWord w
ppConst (ConstVector k _ vs) = '{' : intercalate ", " (map ppConst (vecToList vs)) ++ "}"
ppConst (ConstStruct _ _ is) = '{' : intercalate ", " (map ppConst (ilistToList is)) ++ "}"

ppRtlExpr :: String -> RtlExpr -> State [(Int, Kind, String)] String
ppRtlExpr who e =
  case e of
    RtlReadReg k s -> return (ppName s)
    RtlReadInput k var -> return $ ppPrintVar var
    RtlReadWire k var -> return $ ppPrintVar var
    RtlConst k c -> return $ ppConst c
    RtlUniBool Neg e -> uniExpr "~" e
    RtlBinBool And e1 e2 -> binExpr e1 "&" e2
    RtlBinBool Or e1 e2 -> binExpr e1 "|" e2
    RtlUniBit _ _ (Inv _) e -> uniExpr "~" e
    RtlUniBit sz retSz (ConstExtract lsb ret msb) e -> createTrunc (Bit sz) e (sz - msb - 1) lsb
    RtlUniBit sz retSz (Trunc _ _) e -> createTrunc (Bit sz) e (retSz - 1) 0
    RtlUniBit sz retSz (TruncLsb lsb _) e -> createTrunc (Bit sz) e (sz - 1) lsb
    RtlUniBit sz retSz (ZeroExtendTrunc _ _) e -> if sz < retSz
                                                  then
                                                    do
                                                      x <- ppRtlExpr who e
                                                      return $ '{' : show (retSz - sz) ++ "'b0, " ++ x ++ "}"
                                                  else createTrunc (Bit sz) e (retSz - 1) 0
    RtlUniBit sz retSz (SignExtendTrunc _ _) e -> if sz < retSz
                                                  then
                                                    do
                                                      (new, rest) <- optionAddToTrunc (Bit sz) e ('[' : show (sz - 1) ++ "]")
                                                      return $ "{{" ++ show (retSz - sz) ++ '{' : new ++ rest ++ "}}, " ++ new ++ "}"
                                                  else createTrunc (Bit sz) e (retSz - 1) 0
    RtlBinBit _ _ _ (Add _) e1 e2 -> binExpr e1 "+" e2
    RtlBinBit _ _ _ (Sub _) e1 e2 -> binExpr e1 "-" e2
    RtlBinBit _ _ _ (Mul _) e1 e2 -> binExpr e1 "*" e2
    RtlBinBit _ _ _ (Band _) e1 e2 -> binExpr e1 "&" e2
    RtlBinBit _ _ _ (Bor _) e1 e2 -> binExpr e1 "|" e2
    RtlBinBit _ _ _ (Bxor _) e1 e2 -> binExpr e1 "^" e2
    RtlBinBit _ _ _ (Sll _ _) e1 e2 -> binExpr e1 "<<" e2
    RtlBinBit _ _ _ (Srl _ _) e1 e2 -> binExpr e1 ">>" e2
    RtlBinBit _ _ _ (Sra _ _) e1 e2 ->
      do
        x1 <- ppRtlExpr who e1
        x2 <- ppRtlExpr who e2
        return $ "($signed(" ++ x1 ++ ") >>> " ++ x2 ++ ")"
    RtlBinBit _ _ _ (Concat _ _) e1 e2 ->
      do
        x1 <- ppRtlExpr who e1
        x2 <- ppRtlExpr who e2
        return $ '{' : x1 ++ ", " ++ x2 ++ "}"
    RtlBinBitBool _ _ (Lt _) e1 e2 -> binExpr e1 "<" e2
    RtlITE _ p e1 e2 -> triExpr p "?" e1 ":" e2
    RtlEq _ e1 e2 -> binExpr e1 "==" e2
    RtlReadIndex n k idx vec ->
      do
        xidx <- ppRtlExpr who idx
        xvec <- ppRtlExpr who vec
        (new, rest) <- optionAddToTrunc (Vector k n) vec ('[' : xidx ++ "]")
        return $ new ++ rest
    RtlReadField _ fields idx e ->
      do
        x <- ppRtlExpr who e
        return $ x ++ '.' : attrName (vectorToList fields !! finToInt idx)
    RtlBuildVector _ _ vs ->
      do
        strs <- mapM (ppRtlExpr who) (vecToList vs)
        return $ '{': intercalate ", " strs ++ "}"
    RtlBuildStruct _ _ es ->
      do
        strs <- mapM (ppRtlExpr who) (ilistToList es)
        return $ '{': intercalate ", " strs ++ "}"
    RtlUpdateVector n _ v idx val ->
      do
        xv <- ppRtlExpr who v
        xidx <- ppRtlExpr who idx
        xval <- ppRtlExpr who val
        return $  '{' : intercalate ", "
          (map (\i -> xidx ++ "==" ++ show n ++ "'d" ++ show i ++ " ? " ++ xval ++
                 ":" ++ xv ++ "[" ++ show i ++ "]")
           [0 .. ((2^n)-1)]) ++ "}"
  where
    optionAddToTrunc :: Kind -> RtlExpr -> String -> State [(Int, Kind, String)] (String, String)
    optionAddToTrunc k e rest =
      case e of
        RtlReadReg k s -> return $ (ppName s, rest)
        RtlReadInput k var -> return $ (ppPrintVar var, rest)
        RtlReadWire k var -> return $ (ppPrintVar var, rest)
        _ -> do
          x <- ppRtlExpr who e
          new <- addToTrunc k x
          return $ (new, rest)
    createTrunc :: Kind -> RtlExpr -> Int -> Int -> State [(Int, Kind, String)] String
    createTrunc k e msb lsb =
      do
        (new, rest) <- optionAddToTrunc k e ('[' : show msb ++ ':' : show lsb ++ "]")
        return $ new ++ rest
    addToTrunc :: Kind -> String -> State [(Int, Kind, String)] String
    addToTrunc k s =
      do
        x <- get
        case Data.List.find (\(_, k', s') -> s' == s) x of
          Just (pos, _, _) -> return $ "_trunc$" ++ who ++ "$" ++ show pos
          Nothing ->
            do
              put ((Data.List.length x, k, s) : x)
              return $ "_trunc$" ++ who ++ "$" ++ show (Data.List.length x)
    uniExpr op e =
      do
        x <- ppRtlExpr who e
        return $ '(' : " " ++ op ++ " " ++ x ++ ")"
    binExpr e1 op e2 =
      do
        x1 <- ppRtlExpr who e1
        x2 <- ppRtlExpr who e2
        return $ '(' : x1 ++ " " ++ op ++ " " ++ x2 ++ ")"
    triExpr e1 op1 e2 op2 e3 =
      do
        x1 <- ppRtlExpr who e1
        x2 <- ppRtlExpr who e2
        x3 <- ppRtlExpr who e3
        return $ '(' : x1 ++ " " ++ op1 ++ " " ++ x2 ++ " " ++ op2 ++ " " ++ x3 ++ ")"

{-
ppRegFileInstance :: (String, String, String, ((Int, Kind), RegInitValue)) -> String
ppRegFileInstance (name, read, write, ((idxType, dataType), init)) =
  ppName name ++ " " ++
  (case init of
      RegInitCustom (SyntaxKind k, SyntaxConst _ v) -> "#(.init(" ++ ppConst v ++ "))) "
        _ -> "") ++
  ppName name ++ "$inst(.CLK(CLK), .RESET(RESET), ." ++
  ppName read ++ "$en(" ++ ppName read ++ "$en), ." ++
  ppName read ++ "$arg(" ++ ppName read ++ "$arg), ." ++
  ppName read ++ "$ret(" ++ ppName read ++ "$ret), ." ++
  ppName read ++ "$g(" ++ ppName read ++ "$g), ." ++
  ppName write ++ "$g(" ++ ppName write ++ "$g)" ++
  ppName write ++ "$en(" ++ ppName write ++ "$en)" ++
  ppName write ++ "$arg(" ++ ppName write ++ "$arg));\n\n"
  
ppRegFileModule :: (String, String, String, ((Int, Kind), RegInitValue)) -> String
ppRegFileModule (name, read, write, ((idxType, dataType), init)) =
  "module " ++ name ++ "(" ++
  "  input " ++ ppDeclType (ppName read ++ "$en") Bool ++ ",\n" ++
  "  input " ++ ppDeclType (ppName read ++ "$arg") (Bit idxType) ++ ",\n" ++
  "  output " ++ ppDeclType (ppName read ++ "$ret") dataType ++ ",\n" ++
  "  input " ++ ppDeclType (ppName write ++ "$en") Bool ++ ",\n" ++
  "  input " ++ ppDeclType (ppName write ++ "$en") Bool ++ ",\n" ++
  "  input logic CLK,\n" ++
  "  input logic RESET\n" ++
  ");\n"
  -}
  
                 


ppRtlModule :: RtlModule -> String
ppRtlModule m@(Build_RtlModule regFs ins' outs' regInits' regWrites' assigns') =
  "module top(\n" ++
  concatMap (\(nm, ty) -> "  input " ++ ppDeclType (ppPrintVar nm) ty ++ ",\n") ins ++ "\n" ++
  concatMap (\(nm, ty) -> "  output " ++ ppDeclType (ppPrintVar nm) ty ++ ",\n") outs ++ "\n" ++
  "  input CLK,\n" ++
  "  input RESET\n" ++
  ");\n" ++
  concatMap (\(nm, (ty, init)) -> "  " ++ ppDeclType (ppName nm) ty ++ ";\n") regInits ++ "\n" ++

  concatMap (\(nm, (ty, expr)) -> "  " ++ ppDeclType (ppPrintVar nm) ty ++ ";\n") assigns ++ "\n" ++
  
  concatMap (\(pos, ty, sexpr) -> "  " ++ ppDeclType ("_trunc$wire$" ++ show pos) ty ++ ";\n") assignTruncs ++ "\n" ++
  concatMap (\(pos, ty, sexpr) -> "  " ++ ppDeclType ("_trunc$reg$" ++ show pos) ty ++ ";\n") regTruncs ++ "\n" ++

  concatMap (\(pos, ty, sexpr) -> "  assign " ++ "_trunc$wire$" ++ show pos ++ " = " ++ sexpr ++ ";\n") assignTruncs ++ "\n" ++
  concatMap (\(pos, ty, sexpr) -> "  assign " ++ "_trunc$reg$" ++ show pos ++ " = " ++ sexpr ++ ";\n") regTruncs ++ "\n" ++
  
  concatMap (\(nm, (ty, sexpr)) -> "  assign " ++ ppPrintVar nm ++ " = " ++ sexpr ++ ";\n") assignExprs ++ "\n" ++
  
  "  always @(posedge CLK) begin\n" ++
  "    if(RESET) begin\n" ++
  concatMap (\(nm, (ty, init)) -> case init of
                                    Nothing -> ""
                                    Just i -> "      " ++ ppName nm ++ " <= " ++ ppConst i ++ ";\n") regInits ++
  "    end\n" ++
  "    else begin\n" ++
  concatMap (\(nm, (ty, sexpr)) -> "      " ++ ppName nm ++ " <= " ++ sexpr ++ ";\n") regExprs ++
  "    end\n\n" ++
  "  end\n\n" ++
  "endmodule\n"
  where
    ins = nubBy (\(a, _) (b, _) -> a == b) ins'
    outs = nubBy (\(a, _) (b, _) -> a == b) outs'
    regInits = nubBy (\(a, _) (b, _) -> a == b) regInits'
    regWrites = nubBy (\(a, _) (b, _) -> a == b) regWrites'
    assigns = nubBy (\(a, _) (b, _) -> a == b) assigns'
    convAssigns =
      mapM (\(nm, (ty, expr)) ->
              do
                s <- ppRtlExpr "wire" expr
                return (nm, (ty, s))) assigns
    convRegs =
      mapM (\(nm, (ty, expr)) ->
              do
                s <- ppRtlExpr "reg" expr
                return (nm, (ty, s))) regWrites
    (assignExprs, assignTruncs) = runState convAssigns []
    (regExprs, regTruncs) = runState convRegs []


main = putStrLn $ ppRtlModule target
