port module Folder exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icons exposing (..)
import Helpers exposing (Helpers)


-- MODEL


type alias Model =
    { folder : String
    , error : Maybe String
    }


init : String -> Model
init folder =
    { folder = folder
    , error = Nothing
    }


isValid : Model -> Bool
isValid model =
    case model.error of
        Nothing ->
            True

        Just _ ->
            False



-- UPDATE


type Msg
    = ChooseFolder
    | FillFolder Model
    | SetError String
    | StartSync


port chooseFolder : () -> Cmd msg


port startSync : String -> Cmd msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case
        msg
    of
        ChooseFolder ->
            ( model, chooseFolder () )

        FillFolder model ->
            ( model, Cmd.none )

        SetError error ->
            ( { model
                | error =
                    if error == "" then
                        Nothing
                    else
                        Just error
              }
            , Cmd.none
            )

        StartSync ->
            ( model, startSync model.folder )



-- VIEW


view : Helpers -> Model -> Html Msg
view helpers model =
    div
        [ classList
            [ ( "step", True )
            , ( "step-folder", True )
            , ( "step-error", not (isValid model) )
            ]
        ]
        [ div
            [ class "step-content" ]
            [ Icons.bigTick
            , p [ class "error-message" ]
                [ text <| helpers.t <| Maybe.withDefault "" model.error ]
            , img
                [ src "images/done.svg"
                , class "done"
                ]
                []
            , h1 [] [ text (helpers.t "Folder All done") ]
            , case model.error of
                Nothing ->
                    p [ class "folder-helper" ]
                        [ text (helpers.t "Folder Select a location for your Cozy folder:") ]
                Just error ->
                    p [ class "error-message" ]
                        [ text (helpers.t error) ]
            , div [ class "coz-form-group" ]
                [ a
                    [ class "folder__selector"
                    , href "#"
                    , onClick ChooseFolder
                    ]
                    [ text model.folder ]
                ]
            , a
                [ class "btn"
                , href "#"
                , onClick StartSync
                ]
                [ text (helpers.t "Folder Use Cozy Drive") ]
            ]
        ]
