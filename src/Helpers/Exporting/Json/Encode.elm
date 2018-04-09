module Helpers.Exporting.Json.Encode exposing (encode, jsonTableau)

import Json.Encode exposing (..)
import Tableau exposing (Extension(Alpha, Beta, Closed, Delta, Gamma, Open), Node, Tableau)


jsonRef : { a | str : String } -> Value
jsonRef r =
    string r.str


jsonNode : { b | id : Int, reference : { a | str : String }, value : String } -> Value
jsonNode { id, value, reference } =
    object
        [ ( "id", int id )
        , ( "value", string value )
        , ( "reference", jsonRef reference )
        ]


jsonNodeList : Node -> List ( String, Value )
jsonNodeList n =
    [ ( "node", jsonNode n ) ]


jsonSubstitution : { a | forWhat : String, what : String } -> Value
jsonSubstitution { what, forWhat } =
    object
        [ ( "what", string what )
        , ( "forWhat", string forWhat )
        ]


encodeSubstitution : Tableau.Substitution -> List ( String, Value )
encodeSubstitution s =
    [ ( "substitution", jsonSubstitution s ) ]


jsonTblList : Tableau -> List ( String, Value )
jsonTblList tableau =
    case tableau.ext of
        Open ->
            [ ( "type", string "open" ) ]
                ++ jsonNodeList tableau.node

        Closed r1 r2 ->
            [ ( "type", string "closed" ) ]
                ++ jsonNodeList tableau.node
                ++ [ ( "closed"
                     , list
                        [ jsonRef r1
                        , jsonRef r2
                        ]
                     )
                   ]

        Alpha t ->
            [ ( "type", string "alpha" ) ]
                ++ jsonNodeList tableau.node
                ++ [ ( "child", jsonTableau t ) ]

        Beta lt rt ->
            [ ( "type", string "beta" ) ]
                ++ jsonNodeList tableau.node
                ++ [ ( "leftChild", jsonTableau lt ), ( "rightChild", jsonTableau rt ) ]

        Gamma t s ->
            [ ( "type", string "gamma" ) ]
                ++ jsonNodeList tableau.node
                ++ [ ( "child", jsonTableau t ) ]
                ++ encodeSubstitution s

        Delta t s ->
            [ ( "type", string "delta" ) ]
                ++ jsonNodeList tableau.node
                ++ [ ( "child", jsonTableau t ) ]
                ++ encodeSubstitution s


jsonTableau : Tableau -> Value
jsonTableau t =
    object <| jsonTblList t


encode : Int -> Tableau -> String
encode ind t =
    Json.Encode.encode ind (jsonTableau t) ++ "\n"



{- vim: set sw=2 ts=2 sts=2 et : -}
