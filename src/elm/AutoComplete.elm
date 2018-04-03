port module AutoComplete exposing (choices, init)


port autoComplete : String -> Cmd msg


port choices : ( String, List String ) -> Cmd msg


init : String -> Cmd msg
init domID =
  autoComplete domID
