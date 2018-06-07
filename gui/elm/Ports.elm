port module Ports exposing (..)

import Model
    exposing
        ( DiskSpace
        , Progress
        , RemoteWarning
        , UserActionRequiredError
        )
import Model.File exposing (File)
import Model.SyncFolderConfig exposing (SyncFolderConfig)


port autoLauncher : Bool -> Cmd msg


port autolaunch : (Bool -> msg) -> Sub msg


port buffering : (Bool -> msg) -> Sub msg


port cancelUnlink : (Bool -> msg) -> Sub msg


port chooseFolder : () -> Cmd msg


port closeApp : () -> Cmd msg


port diskSpace : (DiskSpace -> msg) -> Sub msg


port focus : String -> Cmd msg


port folder : (SyncFolderConfig -> msg) -> Sub msg


port folderError : (String -> msg) -> Sub msg


port gotocozy : () -> Cmd msg


port gotofolder : () -> Cmd msg


port gototab : (String -> msg) -> Sub msg


port mail : (Maybe String -> msg) -> Sub msg


port newRelease : (( String, String ) -> msg) -> Sub msg


port offline : (Bool -> msg) -> Sub msg


port openFile : String -> Cmd msg


port quitAndInstall : () -> Cmd msg


port registerRemote : String -> Cmd msg


port registrationDone : (Bool -> msg) -> Sub msg


port registrationError : (String -> msg) -> Sub msg


port remoteWarnings : (List RemoteWarning -> msg) -> Sub msg


port remove : (File -> msg) -> Sub msg


port sendMail : String -> Cmd msg


port showHelp : () -> Cmd msg


port squashPrepMerge : (Bool -> msg) -> Sub msg


port startSync : String -> Cmd msg


port syncError : (String -> msg) -> Sub msg


port synchonization : (( String, String ) -> msg) -> Sub msg


port syncing : (Int -> msg) -> Sub msg


port transfer : (File -> msg) -> Sub msg


port unlinkCozy : () -> Cmd msg


port updateDownloading : (Maybe Progress -> msg) -> Sub msg


port updateError : (String -> msg) -> Sub msg


port updated : (Bool -> msg) -> Sub msg


port userActionRequired : (UserActionRequiredError -> msg) -> Sub msg
