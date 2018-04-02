port module Phoenix exposing (connect, connections, disconnect, messages, send)

import Json.Encode as Json


port connect : ( String, String ) -> Cmd msg


port disconnect : () -> Cmd msg


port connections : (Maybe String -> msg) -> Sub msg


port messages : (( String, Json.Value ) -> msg) -> Sub msg


port send : ( String, String ) -> Cmd msg
