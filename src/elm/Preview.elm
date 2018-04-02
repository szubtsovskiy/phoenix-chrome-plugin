port module Preview exposing (show)

import Json.Encode as Json


port previews : Json.Value -> Cmd msg


show : String -> Json.Value -> Cmd msg
show containerID data =
  let
    payload =
      Json.object
        [ ( "containerID", Json.string containerID )
        , ( "data", data )
        ]
  in
  previews payload
