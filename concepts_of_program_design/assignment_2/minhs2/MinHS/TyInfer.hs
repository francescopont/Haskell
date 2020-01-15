module MinHS.TyInfer where

import qualified MinHS.Env as E
import MinHS.Syntax
import MinHS.Subst
import MinHS.TCMonad

import Data.Monoid (Monoid (..), (<>))
import Data.Foldable (foldMap)
import Data.List (nub, union, (\\))

primOpType :: Op -> QType
primOpType Gt   = Ty $ Base Int `Arrow` (Base Int `Arrow` Base Bool)
primOpType Ge   = Ty $ Base Int `Arrow` (Base Int `Arrow` Base Bool)
primOpType Lt   = Ty $ Base Int `Arrow` (Base Int `Arrow` Base Bool)
primOpType Le   = Ty $ Base Int `Arrow` (Base Int `Arrow` Base Bool)
primOpType Eq   = Ty $ Base Int `Arrow` (Base Int `Arrow` Base Bool)
primOpType Ne   = Ty $ Base Int `Arrow` (Base Int `Arrow` Base Bool)
primOpType Neg  = Ty $ Base Int `Arrow` Base Int
primOpType Fst  = Forall "a" $ Forall "b" $ Ty $ (TypeVar "a" `Prod` TypeVar "b") `Arrow` TypeVar "a"
primOpType Snd  = Forall "a" $ Forall "b" $ Ty $ (TypeVar "a" `Prod` TypeVar "b") `Arrow` TypeVar "b"
primOpType _    = Ty $ Base Int `Arrow` (Base Int `Arrow` Base Int) -- this is for add and stuff, they all have the same type

constType :: Id -> Maybe QType
constType "True"  = Just $ Ty $ Base Bool
constType "False" = Just $ Ty $ Base Bool
constType "()"    = Just $ Ty $ Base Unit
constType "Pair"  = Just
                  $ Forall "a"
                  $ Forall "b"
                  $ Ty
                  $ TypeVar "a" `Arrow` (TypeVar "b" `Arrow` (TypeVar "a" `Prod` TypeVar "b"))
constType "Inl"   = Just
                  $ Forall "a"
                  $ Forall "b"
                  $ Ty
                  $ TypeVar "a" `Arrow` (TypeVar "a" `Sum` TypeVar "b")
constType "Inr"   = Just
                  $ Forall "a"
                  $ Forall "b"
                  $ Ty
                  $ TypeVar "b" `Arrow` (TypeVar "a" `Sum` TypeVar "b")
constType _       = Nothing

--Inr and Inl are the constructors of the sum tpe
-- () and Pair are the constructors of the Prod type
--True and False are the constructors of the sBool type
type Gamma = E.Env QType

initialGamma :: Gamma
initialGamma = E.empty

tv :: Type -> [Id]   -- tv sono le free variables: a che cosa possono servire??? boh boh
tv = tv'
 where
   tv' (TypeVar x) = [x]
   tv' (Prod  a b) = tv a `union` tv b -- usando queste apici si può usare in forma infissa, molto più leggibile
   tv' (Sum   a b) = tv a `union` tv b
   tv' (Arrow a b) = tv a `union` tv b
   tv' (Base c   ) = []

tvQ :: QType -> [Id]
tvQ (Forall x t) = filter (/= x) $ tvQ t
tvQ (Ty t) = tv t

tvGamma :: Gamma -> [Id]
tvGamma = nub . foldMap tvQ

infer :: Program -> Either TypeError Program
infer program = do (p',tau, s) <- runTC $ inferProgram initialGamma program
                   return p'


-- remove the quantifiers from a polymrphic type and rename all quantified variables
-- with fresh names.
unquantify :: QType -> TC Type
{-
Normally this implementation would be possible:

unquantify (Ty t) = return t
unquantify (Forall x t) = do x' <- fresh
                             unquantify (substQType (x =:x') t)

However as our "fresh" names are not checked for collisions with names bound in the type
we avoid capture entirely by first replacing each bound
variable with a guaranteed non-colliding variable with a numeric name,
and then substituting those numeric names for our normal fresh variables
-}

unquantify = unquantify' 0 emptySubst -- anche qua mantengo non specificato il parametro e faccio pattern matching
unquantify' :: Int -> Subst -> QType -> TC Type
unquantify' i s (Ty t) = return $ substitute s t
unquantify' i s (Forall x t) = do x' <- fresh
                                  unquantify' (i + 1)
                                              ((show i =: x') <> s)
                                              (substQType (x =:TypeVar (show i)) t)


-- Implement the functions below
-- =============================

unify :: Type -> Type -> TC Subst
unify (TypeVar v1) (TypeVar v2) = case (v1 == v2) of
                                      True -> return emptySubst
                                      False -> return (v2 =: (TypeVar v1))   
unify (Base Unit ) (Base Unit)   = return emptySubst
unify (Base Bool ) (Base Bool)   = return emptySubst
unify (Base Int ) (Base Int)   = return emptySubst
unify (Base ty1 ) (Base ty2)   =  typeError (TypeMismatch (Base ty1) (Base  ty2))
unify (Prod t11 t12) (Prod t21 t22) = do  sub1 <- unify t11 t21
                                          sub2 <-  unify t12 t22
                                          return (sub1 <> sub2)
unify (Sum t11 t12) (Sum t21 t22) = do  sub1 <- unify t11 t21
                                        sub2 <-  unify t12 t22
                                        return (sub1 <> sub2)
unify (Arrow t11 t12) (Arrow t21 t22) = do  sub1 <- unify t11 t21
                                            sub2 <-  unify t12 t22
                                            return (sub1 <> sub2)
---arbitrary type term
unify (TypeVar v) t = case occursCheck v t of
                        True -> typeError (OccursCheckFailed v t)
                        False -> return (v =: t)

unify t (TypeVar v) = unify (TypeVar v) t

occursCheck :: String -> Type -> Bool
occursCheck v (Arrow ty1 ty2) = or [(occursCheck v ty1),(occursCheck v ty2)]
occursCheck v (Prod ty1 ty2) = or [(occursCheck v ty1),(occursCheck v ty2)]
occursCheck v (Sum ty1 ty2) = or [(occursCheck v ty1),(occursCheck v ty2)]
occursCheck v (Base ty) = False
occursCheck v (TypeVar v1) =  case (v == v1) of
                              True -> True
                              False -> False


--this code is for the generalize (start from heeeereee)
generalise :: Gamma -> Type -> QType
generalise g t = quantify (filter ( notPresentIn (tvGamma g))(tv t) ) t -- check gamma now

quantify :: [Id] -> Type ->QType
quantify [] t     = Ty t
quantify [x] t    = (Forall x (Ty t))
quantify (x:xs) t = quantify'  xs (Forall x (Ty t))

quantify' :: [Id] -> QType ->QType
quantify' [] t     =  t
quantify' [x] t    = (Forall x  t)
quantify' (x:xs) t = quantify'  xs (Forall x t)


notPresentIn :: [Id] -> Id -> Bool
notPresentIn []     tauString = True
notPresentIn [x]     tauString = case (tauString /= x)of 
                                True -> True
                                False -> False
notPresentIn (x:xs) tauString = case (tauString /= x)of 
                                True -> notPresentIn xs tauString 
                                False -> False
-- end generalize code


inferProgram :: Gamma -> Program -> TC (Program, Type, Subst)
-- fix the implementation - it is not correct as it is and will work
-- only for a some cases. The code is just an example on how to use the TC type,
-- and how to add the type information to the expression.
inferProgram env [Bind m _ [] exp]
  = do
      (typedExp, t, subst) <- inferExp env exp
      return ([Bind m   (Just (generalise env t))  [] (allTypes (substQType subst) typedExp)], t, subst)
   -- ricordati che return fa una cosa specifica nelle monadi


inferExp :: Gamma -> Exp -> TC (Exp, Type, Subst)
-- constructor type (it was already here)
inferExp g exp@(Con id) = inferExpConstructor id g exp (constType id)

---- prim op type (basically the same)
inferExp g exp@(Prim op) = do
  let  qt = primOpType op
  t <- unquantify qt
  return (exp, t, emptySubst)



---- integer base type
inferExp g exp@(Num n) = return (exp,Base Int, emptySubst)

inferExp g expr@(Var varId) = case E.lookup g varId of
                              Just qt -> do 
                                          t <- unquantify qt
                                          return (expr,t, emptySubst)
                              Nothing -> typeError (NoSuchVariable varId)

inferExp g (App expr1 expr2) =       do (annotatedExpr1, ty1, subst1) <- inferExp g expr1
                                        (annotatedExpr2, ty2, subst2) <- inferExp (substGamma subst1 g)   expr2
                                        (alpha) <- fresh
                                        (finalSub) <- unify (substitute subst2 ty1) (ty2 `Arrow` alpha)
                                        return ((App annotatedExpr1 annotatedExpr2), (substitute finalSub alpha), (subst1 <> subst2 <> finalSub))

inferExp g (If expr1 expr2 expr3) =  do       (annotatedExpr1, ty1, subst1) <- inferExp g expr1
                                              (substBool) <- unify  ty1 (Base Bool)
                                              (annotatedExpr2, ty2, subst2) <- inferExp (substGamma substBool (substGamma subst1 g))   expr2
                                              (annotatedExpr3, ty3, subst3) <- inferExp (substGamma subst2(substGamma substBool (substGamma subst1 g)))   expr3
                                              (finalSub) <- unify (substitute subst3 ty2) (ty3)
                                              return ((If annotatedExpr1 annotatedExpr2 annotatedExpr3), (substitute finalSub ty3), (subst1 <> substBool <> subst2 <> subst3 <> finalSub))


inferExp g (Let [Bind varId x [] expr1] expr2) = do         (annotatedExpr1, ty1, subst1) <- inferExp g expr1
                                                            let new_g                         = substGamma subst1 g
                                                            let generalized                   = generalise new_g ty1
                                                            (annotatedExpr2, ty2, subst2) <- inferExp (  E.add new_g  (varId,generalized )) expr2
                                                            return ((Let [Bind varId (Just generalized) [] annotatedExpr1] annotatedExpr2),ty2, (subst1 <> subst2))

--inferExp g expr@(Let ((Bind varId _ [] expr1):bs) expr2) = do   (annotatedExpr1, ty1, subst1) <- inferExp g expr1
                                                                --let new_g                      = substGamma subst1 g
                                                                --(annotatedExpr2, ty2, subst2) <- inferExp ( E.add new_g (varId, (generalise new_g ty1))) (Let bs expr2)
                                                                --return ((Let ((Bind varId (Just (Ty ty2)) [] annotatedExpr1) annotatedExpr2),ty2, (subst1 <> subst2))

inferExp g (Case expr [Alt "Inl" [x] expr1, Alt "Inr" [y] expr2]) = do            (annotatedExpr, ty, subst) <- inferExp g expr
                                                                                  (alphal) <- fresh
                                                                                  (annotatedExpr1, ty1, subst1) <- inferExp (substGamma subst (E.add g (x,Ty alphal))) expr1
                                                                                  (alphar) <- fresh
                                                                                  (annotatedExpr2, ty2, subst2) <- inferExp (substGamma subst1 (substGamma subst (E.add g (y, Ty alphar)))) expr2
                                                                                  finalSub <- unify (substitute subst2 (substitute subst1 (substitute subst(Sum alphal alphar)))) (substitute subst2 (substitute subst1 (ty)))
                                                                                  finalSub' <- unify (substitute finalSub (substitute subst2 ty1)) ( substitute finalSub ty2)
                                                                                  return ((Case annotatedExpr [Alt "Inl" [x] annotatedExpr1, Alt "Inr" [y] annotatedExpr2]), (substitute finalSub' (substitute finalSub ty2)), (finalSub' <> finalSub <> subst2 <> subst1 <> subst))
                                                                            
inferExp g ((Recfun (Bind funId _  [] funExpr ))) = inferExp g funExpr
inferExp g ((Recfun (Bind funId _ [x] funExpr ))) = do            (alpha1) <- fresh
                                                                  (alpha2) <- fresh
                                                                  (annotatedExpr, ty, subst) <- inferExp (E.addAll g [(x, Ty alpha1),(funId, Ty alpha2)])  funExpr
                                                                  (finalSub) <- unify (substitute subst alpha2) ( (substitute subst alpha1) `Arrow` ty)
                                                                  let (finalty) = substitute finalSub ( (substitute subst alpha1)`Arrow` ty)
                                                                  return (((Recfun (Bind funId (Just (Ty finalty)) [x] annotatedExpr ))),finalty , (finalSub <> subst))

inferExp g (Case e _) = typeError MalformedAlternatives -- è importante capire come fare a gestire le eccezioni                                                           
inferExp g _ = error "Implement me!"    

inferExpConstructor :: String -> Gamma -> Exp -> Maybe QType -> TC (Exp,Type,Subst)
inferExpConstructor id g exp Nothing = typeError (NoSuchConstructor id)
inferExpConstructor id g exp (Just qt) = do
  t <- unquantify qt
  return (exp, t, emptySubst)



