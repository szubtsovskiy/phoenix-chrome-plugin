module Main exposing (main)

import Clipboard
import Dict exposing (Dict)
import Dom.Scroll as Scroll
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, onWithOptions)
import Icons
import Json.Decode
import Json.Encode as Json
import Phoenix
import Preview
import Task


{-| Union type to handle connection state

      Disconnected <url> <topic> - WS client is disconnected, URL and/or might be entered
      Connected <url> <topic> - WS client is connected to the endpoint but no channel has been joined, though topic name might be present
      Joined <url> <topic> - WS client is connected and joined to a channel

-}
type PhoenixConnectionState
  = Disconnected
  | Connecting
  | Connected


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
  | ChangeUrl String
  | ChangeTopic String
  | ChangeEvent String
  | ChangeMessage String
  | Connect
  | Disconnect
  | Send String String
  | ToggleFrameSelection Int
  | CopyToClipboard String
  | OnConnection (Maybe String)
  | OnMessage ( String, Json.Value )


type alias Model =
  { state : PhoenixConnectionState
  , url : String
  , topic : String
  , event : String
  , message : String
  , error : Maybe String
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
      { state = Disconnected
      , url = "ws://localhost:4000/ws"
      , topic = "larder:1"
      , event = ""
      , message = ""
      , error = Nothing
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

    ChangeUrl url ->
      { model | url = url, error = Nothing } ! []

    ChangeTopic topic ->
      { model | topic = topic } ! []

    Connect ->
      case validateUrl model.url of
        Ok url ->
          if isNotBlank model.topic then
            { model | state = Connecting, error = Nothing } ! [ Phoenix.connect ( url, model.topic ) ]

          else
            { model | error = Nothing } ! []

        Err err ->
          { model | state = Disconnected, error = Just err } ! []

    Disconnect ->
      { model | state = Disconnected } ! [ Phoenix.disconnect () ]

    ChangeEvent event ->
      { model | event = event } ! []

    ChangeMessage message ->
      { model | message = message } ! []

    Send event message ->
      if isNotBlank event && isNotBlank message then
        let
          frameID =
            model.nextFrameID

          newFrames =
            Dict.insert frameID (Frame event (Out message) False) model.frames
        in
        { model | frames = newFrames, nextFrameID = frameID + 1 } ! [ Phoenix.send ( event, message ) ]

      else
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

    OnConnection maybeError ->
      case maybeError of
        Nothing ->
          { model | state = Connected, error = Nothing } ! []

        Just err ->
          { model | state = Disconnected, error = Just err } ! []

    OnMessage ( event, payload ) ->
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
    urlValidationState =
      Maybe.map (always "is-invalid") model.error
        |> Maybe.withDefault ""

    ( connectButtonClass, connectButtonText, connectButtonMsg, connectButtonEnabled ) =
      case model.state of
        Disconnected ->
          ( "btn-primary", "Connect & Join", Connect, isNotBlank model.url && isNotBlank model.topic )

        Connecting ->
          ( "btn-primary", "Connect & Join", NoOp, False )

        Connected ->
          ( "btn-warning", "Leave & Disconnect", Disconnect, True )

    sendButtonEnabled =
      model.state == Connected && isNotBlank model.event && isNotBlank model.message

    frameView id frame frameViews =
      let
        ( data, mod, icon ) =
          case frame.message of
            In data ->
              let
                jsonToString data =
                  if data == Json.null then
                    ""

                  else
                    Json.encode 0 data

                mod =
                  if frame.event == "phx_error" then
                    "frame-error"

                  else
                    "frame-in"
              in
              ( jsonToString data, mod, Icons.arrowDown )

            Out data ->
              ( data, "frame-out", Icons.arrowUp )

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
                [ div [ class "frame-icon" ] [ icon ]
                , text frame.event
                ]
            , div [ class "frame-data" ] [ text data ]
            , div [ class "frame-actions" ]
                [ button [ class "btn btn-xs btn-secondary frame-repeat", type_ "button", title "Send again", onClickNoPropagation (Send frame.event data) ]
                    [ Icons.repeat ]
                , button [ class "btn btn-xs btn-secondary frame-copy", type_ "button", title "Copy to clipboard", onClickNoPropagation (CopyToClipboard data) ]
                    [ Icons.clippy ]
                ]
            ]
      in
      frameView :: frameViews
  in
  div [ class "container d-flex flex-column" ]
    [ Html.form [ onSubmit NoOp ]
        [ div [ class "form-row" ]
            [ div [ class "col-6 pr-2" ]
                [ input [ class ("form-control " ++ urlValidationState), type_ "text", placeholder "URL", value model.url, title (Maybe.withDefault "" model.error), readonly (model.state /= Disconnected), onInput ChangeUrl ] []
                , div [ class "invalid-feedback" ] [ text (Maybe.withDefault "" model.error) ]
                ]
            , div [ class "col-4 pr-2" ]
                [ input [ class "form-control", type_ "text", placeholder "Topic", value model.topic, readonly (model.state /= Disconnected), onInput ChangeTopic ] []
                ]
            , div [ class "col-2" ]
                [ button [ class ("btn full-width " ++ connectButtonClass), type_ "submit", onClick connectButtonMsg, disabled (not connectButtonEnabled) ]
                    [ text connectButtonText ]
                ]
            ]
        ]
    , Html.form [ onSubmit NoOp ]
        [ div [ class "form-row mt-4" ]
            [ div [ class "col-10" ]
                [ div [ class "input-group mr-2" ]
                    [ input [ class "form-control col-3", type_ "text", placeholder "Event", value model.event, readonly (model.state /= Connected), onInput ChangeEvent ] []
                    , input [ class "form-control col-9", type_ "text", placeholder "Message", value model.message, readonly (model.state /= Connected), onInput ChangeMessage ] []
                    ]
                ]
            , div [ class "col-2" ]
                [ button [ class "btn btn-primary full-width", type_ "submit", disabled (not sendButtonEnabled), onClick (Send model.event model.message) ] [ text "Send" ]
                ]
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
    [ Phoenix.connections OnConnection
    , Phoenix.messages OnMessage
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
    Err "URL must start with ws:// or wss://"


isNotBlank : String -> Bool
isNotBlank s =
  String.length (String.trim s) > 0
