module Main exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)


type alias Model =
  {}


type Msg
  = NoOp


main : Program Never Model Msg
main =
  Html.program { init = init, update = update, view = view, subscriptions = subscriptions }


init : ( Model, Cmd Msg )
init =
  {} ! []


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  model ! []


view : Model -> Html Msg
view model =
  div [ class "btn-group" ]
    [ button [ class "btn btn-primary", type_ "button" ]
        [ text "Connect" ]
    , button [ class "btn btn-primary dropdown-toggle dropdown-toggle-split", attribute "data-toggle" "dropdown", type_ "button" ]
        []
    , div [ class "dropdown-menu dropdown-menu-right" ]
        [ a [ class "dropdown-item", href "#" ]
            [ text "Connect&Join" ]
        ]
    ]


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none
