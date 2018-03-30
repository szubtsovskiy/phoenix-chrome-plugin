module Main exposing (main)

import Clipboard
import Dict exposing (Dict)
import Dom.Scroll as Scroll
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onWithOptions)
import Json.Decode
import Json.Encode as Json
import Phoenix
import Preview
import Task


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
  = In Json.Value
  | Out String


type alias Frame =
  { event : String
  , message : Message
  , selected : Bool
  }


type Msg
  = NoOp
  | ConnectAndJoin
  | Send String String
  | ToggleFrameSelection Int
  | CopyToClipboard String
  | OnConnected String
  | OnJoined String
  | OnMessage String Json.Value


type alias Model =
  { state : State
  , frames : Dict Int Frame
  , nextFrameID : Int
  }


main : Program Never Model Msg
main =
  Html.program { init = init, update = update, view = view, subscriptions = subscriptions }


init : ( Model, Cmd Msg )
init =
  let
    model =
      { state = Disconnected (Just (Candidate "ws://localhost:4000/ws")) (Just "larder:1")
      , frames = Dict.empty
      , nextFrameID = 0
      }
  in
  model ! [ Preview.show previewContainerID Json.null ]


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    NoOp ->
      model ! []

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

    Send event message ->
      case model.state of
        Joined _ _ ->
          let
            frameID =
              model.nextFrameID

            newFrames =
              Dict.insert frameID (Frame event (Out message) False) model.frames
          in
          { model | frames = newFrames, nextFrameID = frameID + 1 } ! [ Phoenix.send ( event, message ) ]

        _ ->
          model ! []

    CopyToClipboard message ->
      model ! [ Clipboard.copy message ]

    ToggleFrameSelection id ->
      let
        toggleFrameSelection toggleID currentID frame ( frames, dataToPreview ) =
          if toggleID == currentID then
            if frame.selected then
              ( Dict.insert currentID { frame | selected = False } frames, Json.null )

            else
              case frame.message of
                In data ->
                  ( Dict.insert currentID { frame | selected = True } frames, data )

                Out data ->
                  ( Dict.insert currentID { frame | selected = True } frames, Json.string data )

          else
            ( Dict.insert currentID { frame | selected = False } frames, dataToPreview )

        ( newFrames, dataToPreview ) =
          Dict.foldr (toggleFrameSelection id) ( Dict.empty, Json.null ) model.frames
      in
      { model | frames = newFrames } ! [ Preview.show previewContainerID dataToPreview ]

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
        let
          frameID =
            model.nextFrameID

          newFrames =
            Dict.insert frameID (Frame event (In payload) False) model.frames

          scroll =
            Task.attempt (always NoOp) (Scroll.toBottom framesContainerID)
        in
        { model | frames = newFrames, nextFrameID = frameID + 1 } ! [ scroll ]

      else
        model ! []


view : Model -> Html Msg
view model =
  let
    frameView id frame frameViews =
      let
        ( data, mod ) =
          case frame.message of
            In data ->
              ( Json.encode 0 data, "frame-in" )

            Out data ->
              ( data, "frame-out" )

        classes =
          [ ( "frame", True )
          , ( mod, True )
          , ( "frame-selected", frame.selected )
          ]

        onClickNoPropagation =
          onWithOptions "click" { stopPropagation = True, preventDefault = False } << Json.Decode.succeed

        frameView =
          div [ classList classes, onClick (ToggleFrameSelection id) ]
            [ div [ class "frame-event" ]
                [ div [ class "frame-icon" ] []
                , text frame.event
                ]
            , div [ class "frame-data" ] [ text data ]
            , div [ class "frame-actions" ]
                [ button [ class "btn btn-xs btn-secondary frame-repeat", type_ "button", onClickNoPropagation (Send frame.event data) ]
                    []
                , button [ class "btn btn-xs btn-secondary frame-copy", type_ "button", onClickNoPropagation (CopyToClipboard data) ]
                    []
                ]
            ]
      in
      frameView :: frameViews
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
            , button [ class "btn btn-primary fw-150", type_ "button", onClick (Send "create" """{"project-item": {"name": "An item", "project-id": 3}}""") ] [ text "Send" ]
            ]
        ]
    , div [ class "row no-gutters mt-4" ]
        [ div [ class "col-8 pr-2" ]
            [ div [ class "card fixed-height" ]
                [ div [ class "card-header" ] [ text "Frames" ]
                , div [ id framesContainerID, class "card-body p-0 frames" ] (Dict.foldr frameView [] model.frames)
                ]
            ]
        , div [ class "col-4" ]
            [ div [ class "card fg-1 fixed-height" ]
                [ div [ class "card-header" ] [ text "Preview" ]
                , div [ id previewContainerID, class "card-body message-preview" ]
                    []
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


framesContainerID : String
framesContainerID =
  "frames"


previewContainerID : String
previewContainerID =
  "message-preview"


validateUrl : String -> Result String String
validateUrl candidate =
  if String.startsWith "ws://" candidate || String.startsWith "wss://" candidate then
    Ok candidate

  else
    Err "URL must start with ws:// or ws://"
