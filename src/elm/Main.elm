module Main exposing (main)

import AutoComplete
import Clipboard
import Dict exposing (Dict)
import Dom.Scroll as Scroll
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, onWithOptions)
import Icons
import Json.Decode
import Json.Encode as Json
import LocalStorage
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
  | OnLoadHistory String (Result LocalStorage.Error (Maybe (List String)))
  | OnUpdateHistory String (List String) (Result LocalStorage.Error ())


type alias Model =
  { state : PhoenixConnectionState
  , url : String
  , topic : String
  , event : String
  , message : String
  , error : Maybe String
  , frames : Dict Int Frame
  , nextFrameID : Int
  , history : Dict String (List String)
  }


main : Program Never Model Msg
main =
  Html.program { init = init, update = update, view = view, subscriptions = subscriptions }


init : ( Model, Cmd Msg )
init =
  let
    model =
      { state = Disconnected
      , url = ""
      , topic = ""
      , event = ""
      , message = ""
      , error = Nothing
      , frames = Dict.empty
      , nextFrameID = 0
      , history = Dict.empty
      }

    initPreview =
      Preview.show previewContainerID Json.null

    loadHistory field =
      let
        historyDecoder =
          Json.Decode.list Json.Decode.string
      in
      [ AutoComplete.init field
      , Task.attempt (OnLoadHistory field) <| LocalStorage.getJson historyDecoder ("history." ++ field)
      ]

    commands =
      initPreview :: List.concatMap loadHistory [ urlInputID, topicInputID, eventInputID, messageInputID ]
  in
  model ! commands


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
            let
              commands =
                [ Phoenix.connect ( url, model.topic )
                , updateHistory urlInputID url model.history
                , updateHistory topicInputID model.topic model.history
                ]
            in
            { model | state = Connecting, error = Nothing } ! commands

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

          commands =
            [ Phoenix.send ( event, message )
            , updateHistory eventInputID event model.history
            , updateHistory messageInputID message model.history
            ]
        in
        { model | frames = newFrames, nextFrameID = frameID + 1, event = "", message = "" } ! commands

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

    OnLoadHistory field result ->
      onLoadHistory field result model

    OnUpdateHistory field values result ->
      case result of
        Ok _ ->
          { model | history = Dict.insert field values model.history } ! [ AutoComplete.choices ( field, values ) ]

        Err err ->
          let
            _ =
              Debug.log ("Error updating history for " ++ field) err
          in
          model ! []


onLoadHistory : String -> Result LocalStorage.Error (Maybe (List String)) -> Model -> ( Model, Cmd Msg )
onLoadHistory field result model =
  case result of
    Ok maybeHistory ->
      case maybeHistory of
        Just history ->
          { model | history = Dict.insert field history model.history } ! [ AutoComplete.choices ( field, history ) ]

        Nothing ->
          model ! []

    Err err ->
      let
        _ =
          Debug.log ("Error loading history for " ++ field) err
      in
      model ! []


updateHistory : String -> String -> Dict String (List String) -> Cmd Msg
updateHistory field value history =
  let
    existingValues =
      Dict.get field history
        |> Maybe.withDefault []
        |> List.filter ((/=) value)

    newValues =
      List.take 10 (value :: existingValues)

    key =
      "history." ++ field
  in
  Task.attempt (OnUpdateHistory field newValues) <| LocalStorage.setJson key (Json.list (List.map Json.string newValues))


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
            [ div [ class "col-5 pr-2" ]
                [ input [ id urlInputID, class ("form-control " ++ urlValidationState), tabindex 1, autofocus True, type_ "text", placeholder "URL", value model.url, title (Maybe.withDefault "" model.error), readonly (model.state /= Disconnected), onInput ChangeUrl ] []
                , div [ class "invalid-feedback" ] [ text (Maybe.withDefault "" model.error) ]
                ]
            , div [ class "col-5 pr-2" ]
                [ input [ id topicInputID, class "form-control", tabindex 2, type_ "text", placeholder "Topic", value model.topic, readonly (model.state /= Disconnected), onInput ChangeTopic ] []
                ]
            , div [ class "col-2" ]
                [ button [ class ("btn full-width " ++ connectButtonClass), tabindex 0, type_ "submit", onClick connectButtonMsg, disabled (not connectButtonEnabled) ]
                    [ text connectButtonText ]
                ]
            ]
        ]
    , Html.form [ onSubmit NoOp ]
        [ div [ class "form-row mt-4" ]
            [ div [ class "col-5 pr-2" ]
                [ input [ id eventInputID, class "form-control", tabindex 3, type_ "text", placeholder "Event", value model.event, readonly (model.state /= Connected), onInput ChangeEvent ] []
                ]
            , div [ class "col-5 pr-2" ]
                [ input [ id messageInputID, class "form-control", tabindex 4, type_ "text", placeholder "Message", value model.message, readonly (model.state /= Connected), onInput ChangeMessage ] []
                ]
            , div [ class "col-2" ]
                [ button [ class "btn btn-primary full-width", tabindex 0, type_ "submit", disabled (not sendButtonEnabled), onClick (Send model.event model.message) ] [ text "Send" ]
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


urlInputID : String
urlInputID =
  "url"


topicInputID : String
topicInputID =
  "topic"


eventInputID : String
eventInputID =
  "event"


messageInputID : String
messageInputID =
  "message"


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
