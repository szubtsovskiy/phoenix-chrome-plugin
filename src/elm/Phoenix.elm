port module Phoenix exposing (connect, connected, join, joined, onMessage, send)

import Json.Encode as Json


port connect : String -> Cmd msg


port connections : (String -> msg) -> Sub msg


port join : String -> Cmd msg


port joins : (String -> msg) -> Sub msg


port messages : (( String, Json.Value ) -> msg) -> Sub msg


port send : ( String, String ) -> Cmd msg


connected : (String -> msg) -> Sub msg
connected tagger =
  connections tagger


joined : (String -> msg) -> Sub msg
joined tagger =
  joins tagger


onMessage : (String -> Json.Value -> msg) -> Sub msg
onMessage tagger =
  messages (uncurry tagger)
