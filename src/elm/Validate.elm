module Validate exposing (..)

import Tableau exposing (..)
import Formula
import Parser
import Errors
import Zipper


type ProblemType
    = Syntax
    | Semantics


type alias Problem =
    { typ : ProblemType
    , msg : String
    , zip : Zipper.Zipper
    }


syntaxProblem z s =
    [ { typ = Syntax, msg = s, zip = z } ]


semanticsProblem z s =
    [ { typ = Semantics, msg = s, zip = z } ]


error : x -> Result x a -> x
error def r =
    case r of
        Err x ->
            x

        Ok _ ->
            def


(<++) : ( List Problem, Zipper.Zipper ) -> (Zipper.Zipper -> List Problem) -> ( List Problem, Zipper.Zipper )
(<++) ( lp, z ) f =
    ( lp ++ f z, z )


(<++?) : ( List Problem, Zipper.Zipper ) -> (Zipper.Zipper -> Result (List Problem) a) -> ( List Problem, Zipper.Zipper )
(<++?) ( lp, z ) f =
    ( lp ++ error [] (f z), z )


second =
    curry Tuple.second


always3 r _ _ _ =
    r


always2 r _ _ =
    r


isCorrectTableau : Zipper.Zipper -> Result (List Problem) Zipper.Zipper
isCorrectTableau z =
    Errors.merge2 (always2 z)
        (isCorrectNode z)
        (List.foldl
            (Errors.merge2 (always2 z))
            (Ok z)
            (List.map isCorrectTableau (Zipper.children z))
        )


isValidNode : Zipper.Zipper -> Result (List Problem) Zipper.Zipper
isValidNode z =
    Errors.merge3 (always3 z)
        (isValidFormula z)
        (isValidNodeRef z)
        (areValidCloseRefs z)


isCorrectNode : Zipper.Zipper -> Result (List Problem) Zipper.Zipper
isCorrectNode z =
    isValidNode z
        |> Result.andThen
            (\_ ->
                Errors.merge2 (second)
                    (isCorrectRule z)
                    (areCorrectCloseRefs z)
            )


{-| Just for the formula dislplay -- don't check the ref for syntax
-}
isCorrectFormula : Zipper.Zipper -> Result (List Problem) Zipper.Zipper
isCorrectFormula z =
    isValidFormula z
        |> Result.andThen isCorrectRule


isValidFormula : Zipper.Zipper -> Result (List Problem) Zipper.Zipper
isValidFormula z =
    z |> Zipper.zNode |> .formula |> Result.mapError (parseProblem z) |> Result.map (always z)


isValidNodeRef z =
    isValidRef "The" (Zipper.zNode z).reference z


areValidCloseRefs z =
    case (Zipper.zTableau z).ext of
        Closed r1 r2 ->
            Errors.merge2 (always2 z)
                (isValidRef "First close" r1 z)
                (isValidRef "Second close" r2 z)

        _ ->
            Ok z


isValidRef str r z =
    r.up
        |> Result.fromMaybe (syntaxProblem z (str ++ " reference is invalid."))
        |> Result.map (always z)


areCorrectCloseRefs z =
    case (Zipper.zTableau z).ext of
        Closed r1 r2 ->
            areCloseRefsComplementary r1 r2 z |> Result.map (always z)

        _ ->
            Ok z


parseProblem : Zipper.Zipper -> Parser.Error -> List Problem
parseProblem z =
    Formula.errorString >> syntaxProblem z


validateFormula : Zipper.Zipper -> Result (List Problem) (Formula.Signed Formula.Formula)
validateFormula z =
    z |> Zipper.zNode |> .formula |> Result.mapError (parseProblem z)


validateReffedFormula : Zipper.Zipper -> Result (List Problem) (Formula.Signed Formula.Formula)
validateReffedFormula z =
    z |> Zipper.zNode |> .formula |> Result.mapError (\e -> semanticsProblem z "Referenced formula is invalid")


validateRef str r z =
    case r.up of
        Nothing ->
            syntaxProblem z str

        _ ->
            []


validateNodeRef z =
    validateRef "Invalid reference" (Zipper.zNode z).reference z


checkFormula str z =
    z
        |> Zipper.zNode
        |> .formula
        |> Result.mapError (\_ -> semanticsProblem z (str ++ " is invalid."))


checkReffedFormula : String -> Tableau.Ref -> Zipper.Zipper -> Result (List Problem) (Formula.Signed Formula.Formula)
checkReffedFormula str r z =
    z
        |> Zipper.getReffed r
        |> Result.fromMaybe (semanticsProblem z (str ++ " reference is invalid."))
        |> Result.andThen (checkFormula (str ++ " referenced formula"))


areCloseRefsComplementary r1 r2 z =
    Errors.merge2 Formula.isSignedComplementary
        (checkReffedFormula "First close" r1 z)
        (checkReffedFormula "Second close" r2 z)
        |> Result.andThen (resultFromBool z (semanticsProblem z "Closing formulas are not complementary."))


isCorrectRule (( t, bs ) as z) =
    case t.node.reference.up of
        Just 0 ->
            Ok z

        -- This is a premise
        _ ->
            case bs of
                (Zipper.AlphaCrumb _) :: _ ->
                    validateAlphaRule z

                (Zipper.BetaLeftCrumb _ _) :: _ ->
                    validateBetaRuleLeft z

                (Zipper.BetaRightCrumb _ _) :: _ ->
                    validateBetaRuleRight z

                (Zipper.GammaCrumb _ _) :: _ ->
                    validateGammaRule z

                --                    validateGammaRule z
                (Zipper.DeltaCrumb _ _) :: _ ->
                    Ok z

                --                    validateDeltaRule z
                [] ->
                    Ok z



-- Top of the tableau, this must be a premise


makeSemantic =
    List.map (\p -> { p | typ = Semantics })


resultFromBool : a -> x -> Bool -> Result x a
resultFromBool a x b =
    if b then
        Ok a
    else
        Err x



{- Check the value using a predicate.
   Pass the value along if predicate returns true,
   return the give error otherwise
-}


checkPredicate : (a -> Bool) -> x -> a -> Result x a
checkPredicate pred x a =
    if pred a then
        Ok a
    else
        Err x


validateAlphaRule : Zipper.Zipper -> Result (List Problem) Zipper.Zipper
validateAlphaRule z =
    Zipper.getReffed (Zipper.zNode z).reference z
        |> Result.fromMaybe (semanticsProblem z "Invalid reference.")
        |> Result.andThen validateReffedFormula
        |> Result.andThen
            (checkPredicate Formula.isAlpha
                (semanticsProblem z "Referenced formula is not α")
            )
        |> Result.map2 (,) (checkFormula "Formula" z)
        |> Result.andThen
            (checkPredicate (uncurry Formula.isSignedSubformulaOf)
                (semanticsProblem z
                    ("Is not an α-subformula of ("
                        ++ toString (Zipper.getReffed (Zipper.zNode z).reference z |> Maybe.map (Zipper.zNode >> .id) |> Maybe.withDefault 0)
                        ++ ")."
                    )
                )
            )
        |> Result.map (always z)


validateBetaRuleLeft z =
    validateBeta z (z |> Zipper.up |> Zipper.right)


validateBetaRuleRight z =
    validateBeta z (z |> Zipper.up |> Zipper.left)


validateBeta this other =
    let
        ft =
            this |> checkFormula "Formula"

        fo =
            other |> checkFormula "The other β subformula"

        children =
            ft
                |> Result.map List.singleton
                |> Result.map2 (::) fo
                |> Result.map (List.sortBy Formula.strSigned)

        -- This is a hack, but defining an ordering on formulas...
        reffed =
            this
                |> Zipper.getReffed (Zipper.zNode this).reference
                |> Result.fromMaybe (semanticsProblem this "Invalid reference")
                |> Result.andThen validateReffedFormula
                |> Result.andThen
                    (checkPredicate Formula.isBeta
                        (semanticsProblem this "Referenced formula is not β")
                    )
                |> Result.map Formula.signedSubformulas
                |> Result.map (List.sortBy Formula.strSigned)
    in
        Errors.merge2 (==) children reffed
            |> Result.andThen (resultFromBool this (semanticsProblem this "Wrong β subformulas."))
            |> Errors.merge2 (always2 this) (betasHaveSameRef this other)


betasHaveSameRef this other =
    let
        -- The invalid refs will be reported already
        getRef =
            Zipper.zNode >> .reference >> .up >> Result.fromMaybe []

        rt =
            getRef this

        ro =
            getRef other
    in
        Errors.merge2 (==) rt ro
            |> Result.andThen
                (resultFromBool this (semanticsProblem this "β references are not the same"))


validateGammaRule z =
    Zipper.getReffed (Zipper.zNode z).reference z
        |> Result.fromMaybe (semanticsProblem z "Invalid reference.")
        |> Result.andThen validateReffedFormula
        |> Result.andThen
            (checkPredicate Formula.isGamma
                (semanticsProblem z "Referenced formula is not γ")
            )
        |> Result.map2 (,) (checkFormula "Formula" z)
        |> Result.andThen
            (checkPredicate (uncurry Formula.isSignedSubformulaOf)
                (semanticsProblem z
                    ("Is not an γ-subformula of ("
                        ++ toString (Zipper.getReffed (Zipper.zNode z).reference z |> Maybe.map (Zipper.zNode >> .id) |> Maybe.withDefault 0)
                        ++ ")."
                    )
                )
            )
        |> Result.map (always z)



{- vim: set sw=2 ts=2 sts=2 et :s -}
