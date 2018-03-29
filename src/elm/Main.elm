module Main exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)


{-| Union type to handle string entered by user

      Acceptable <value> - a value which has not been validated or valid value
      Malformed <value> <error> - an invalid value together with optional error message

-}
type StringInput
  = Acceptable String
  | Malformed String (Maybe String)


{-| Union type to handle connection state

      Disconnected <url> <topic> - WS client is disconnected, URL and/or might be entered
      Connected <url> <topic> - WS client is connected to the endpoint but no channel has been joined, though topic name might be present
      Joined <url> <topic> - WS client is connected and joined to a channel

-}
type State
  = Disconnected (Maybe StringInput) (Maybe String)
  | Connected String (Maybe String)
  | Joined String String


type alias Model =
  { state : State
  }


type Msg
  = NoOp


main : Program Never Model Msg
main =
  Html.program { init = init, update = update, view = view, subscriptions = subscriptions }


init : ( Model, Cmd Msg )
init =
  { state = Disconnected Nothing Nothing } ! []


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  model ! []


view : Model -> Html Msg
view model =
  div [ class "container d-flex flex-column" ]
    [ div [ class "form-inline justify-content-between" ]
        [ input [ class "form-control mr-2", type_ "text", placeholder "URL" ] []
        , input [ class "form-control mr-2", type_ "text", placeholder "Topic" ] []
        , div [ class "d-flex fixed-width" ]
            [ button [ class "btn btn-primary", type_ "button" ]
                [ text "Connect & Join" ]
            , button [ class "btn btn-primary dropdown-toggle dropdown-toggle-split", attribute "data-toggle" "dropdown", type_ "button" ]
                []
            , div [ class "dropdown-menu dropdown-menu-right" ]
                [ a [ class "dropdown-item", href "#" ]
                    [ text "Connect&Join" ]
                ]
            ]
        ]
    , div [ class "row no-gutters mt-4 d-flex" ]
        [ input [ class "form-control mr-2", type_ "text", placeholder "Message" ] []
        , button [ class "btn btn-primary fixed-width", type_ "button" ] [ text "Send" ]
        ]
    , div [ class "row no-gutters mt-4 d-flex flex-row" ]
        [ div [ class "card fg-2 mr-2 fixed-height" ]
            [ div [ class "card-header" ] [ text "Frames" ]
            , div [ class "card-body" ] []
            ]
        , div [ class "card fg-1 fixed-height" ]
            [ div [ class "card-header" ] [ text "Preview" ]
            , div [ class "card-body d-flex" ]
                [ div [ class "fully-centered" ] [ text "Nothing selected" ]
                ]
            ]
        ]
    ]


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none
