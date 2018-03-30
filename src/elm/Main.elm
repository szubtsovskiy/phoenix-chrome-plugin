module Main exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Json.Encode as Json
import Phoenix


{-| Union type to handle string entered by user

      Acceptable <value> - a value which has not been validated or valid value
      Malformed <value> <error> - an invalid value together with optional error message

-}
type StringInput
  = Candidate String
  | Malformed String (Maybe String)


{-| Union type to handle connection state

      Disconnected <url> <topic> - WS client is disconnected, URL and/or might be entered
      Connected <url> <topic> - WS client is connected to the endpoint but no channel has been joined, though topic name might be present
      Joined <url> <topic> - WS client is connected and joined to a channel

-}
type State
  = Disconnected (Maybe StringInput) (Maybe String)
  | Connecting String (Maybe String)
  | Connected String (Maybe String)
  | Joining String String
  | Joined String String


type Message
  = In String Json.Value
  | Out String String


type Msg
  = ConnectAndJoin
  | Send
  | OnConnected String
  | OnJoined String
  | OnMessage String Json.Value


type alias Model =
  { state : State
  , frames : List Message
  }


main : Program Never Model Msg
main =
  Html.program { init = init, update = update, view = view, subscriptions = subscriptions }


init : ( Model, Cmd Msg )
init =
  { state = Disconnected (Just (Candidate "ws://localhost:4000/ws")) (Just "larder:1"), frames = [] } ! []


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    ConnectAndJoin ->
      case model.state of
        Disconnected (Just (Candidate candidate)) maybeChannel ->
          case validateUrl candidate of
            Ok url ->
              { model | state = Connecting url maybeChannel } ! [ Phoenix.connect url ]

            Err err ->
              { model | state = Disconnected (Just <| Malformed candidate <| Just err) maybeChannel } ! []

        _ ->
          model ! []

    Send ->
      case model.state of
        Joined _ _ ->
          let
            ( event, message ) =
              ( "create", """{"project-item": {"name": "An item", "project-id": 3}}""" )
          in
          { model | frames = Out event message :: model.frames } ! [ Phoenix.send ( event, message ) ]

        _ ->
          model ! []

    OnConnected _ ->
      case model.state of
        Connecting url (Just topic) ->
          let
            _ =
              Debug.log "Connected" url
          in
          { model | state = Joining url topic } ! [ Phoenix.join topic ]

        _ ->
          model ! []

    OnJoined topic ->
      case model.state of
        Joining url topic ->
          let
            _ =
              Debug.log "Joined" topic
          in
          { model | state = Joined url topic } ! []

        _ ->
          model ! []

    OnMessage event payload ->
      if not <| String.startsWith "chan_reply_" event then
        { model | frames = In event payload :: model.frames } ! []

      else
        model ! []


view : Model -> Html Msg
view model =
  let
    frameView message =
      let
        ( event, data, mod ) =
          case message of
            In event data ->
              ( event, Json.encode 0 data, "frame-in" )

            Out event data ->
              ( event, data, "frame-out" )
      in
      div [ class ("frame " ++ mod) ]
        [ div [ class "frame-event" ]
            [ div [ class "frame-icon" ] []
            , text event
            ]
        , div [ class "frame-data" ] [ text data ]
        ]
  in
  div [ class "container d-flex flex-column" ]
    [ div [ class "form-inline justify-content-between" ]
        [ input [ class "form-control mr-2 fg-2", type_ "text", placeholder "URL" ] []
        , input [ class "form-control mr-2 fg-1", type_ "text", placeholder "Topic" ] []
        , div [ class "d-flex fw-150" ]
            [ button [ class "btn btn-primary", type_ "button", onClick ConnectAndJoin ]
                [ text "Connect & Join" ]
            , button [ class "btn btn-primary dropdown-toggle dropdown-toggle-split", attribute "data-toggle" "dropdown", type_ "button" ]
                []
            , div [ class "dropdown-menu dropdown-menu-right" ]
                [ a [ class "dropdown-item", href "#" ]
                    [ text "Connect&Join" ]
                ]
            ]
        ]
    , div [ class "row no-gutters mt-4" ]
        [ div [ class "col-12 d-flex flex-row" ]
            [ div [ class "input-group mr-2" ]
                [ input [ class "form-control col-3", type_ "text", placeholder "Event" ] []
                , input [ class "form-control col-9", type_ "text", placeholder "Message" ] []
                ]
            , button [ class "btn btn-primary fw-150", type_ "button", onClick Send ] [ text "Send" ]
            ]
        ]
    , div [ class "row no-gutters mt-4" ]
        [ div [ class "col-8 pr-2" ]
            [ div [ class "card fixed-height" ]
                [ div [ class "card-header" ] [ text "Frames" ]
                , div [ class "card-body p-0" ] (List.reverse <| List.map frameView model.frames)
                ]
            ]
        , div [ class "col-4" ]
            [ div [ class "card fg-1 fixed-height" ]
                [ div [ class "card-header" ] [ text "Preview" ]
                , div [ class "card-body p-0 d-flex" ]
                    [ div [ class "fully-centered" ] [ text "Nothing selected" ]
                    ]
                ]
            ]
        ]
    ]


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ Phoenix.connected OnConnected
    , Phoenix.joined OnJoined
    , Phoenix.onMessage OnMessage
    ]


validateUrl : String -> Result String String
validateUrl candidate =
  if String.startsWith "ws://" candidate || String.startsWith "wss://" candidate then
    Ok candidate

  else
    Err "URL must start with ws:// or ws://"
