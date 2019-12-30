//
//  Scripts.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 12/30/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Foundation

extension NSAppleScript {
    static func go(code: String, completionHandler: (Bool, NSAppleEventDescriptor?, NSDictionary?) -> Void) {
        var error: NSDictionary?
        let script = NSAppleScript(source: code)
        let output = script?.executeAndReturnError(&error)
        
        if let out = output {
            completionHandler(true, out, nil)
        }
        else {
            completionHandler(false, nil, error)
        }
    }
}
extension NSAppleScript {
        static func checkStatus()-> String{
            return """
            if application "\(itunesMusicName!)" is running then
                tell application "\(itunesMusicName!)"
                    if player state is playing then
                        return "playing"
                    else
                        return "not playing"
                    end if
                end tell
                checkSpotify()
            else if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return "playing"
                    else
                        return "not playing"
                    end if
                end tell
            else
                return "not playing"
            end if
            on checkSpotify()
                if application "Spotify" is running then
                    tell application "Spotify"
                         if player state is playing then
                            return "playing"
                        else
                            return "not playing"
                        end if
                    end tell
                end if
            end checkSpotify
            """
        }
    
    static func loadAlbumArtwork() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
        -- get the raw bytes of the artwork into a var
            tell application "\(itunesMusicName!)" to tell artwork 1 of current track
                set srcBytes to raw data
            -- figure out the proper file extension
                if format is «class PNG » then
                    set ext to ".png"
                else
                    set ext to ".jpg"
                end if
            end tell
            -- get the filename to ~/Desktop/cover.ext
            set fileName to (((path to desktop) as text) & "cover" & ext)
            set saveName to fileName
            -- write to file
            set outFile to open for access file fileName with write permission
            -- truncate the file
            set eof outFile to 0
            -- write the image bytes to the file
            write srcBytes to outFile
            close access outFile
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return artwork url of current track
                else
                    return ""
                end if
            end tell
        end if
        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return artwork url of current track
                    else
                        return ""
                    end if
                end tell
            end if
        end checkSpotify
            on convertPathToPOSIXString(thePath)
                tell application "System Events"
                    try
                        set thePath to path of disk item (thePath as string)
                    on error
                        set thePath to path of thePath
                    end try
                end tell
                return POSIX path of thePath
            end convertPathToPOSIXString
            set thePath to convertPathToPOSIXString(fileName)
            return thePath
        """
    }
    
    static func deleteAlbum() -> String{
        """
        if application "\(itunesMusicName!)" is running then
            -- get the raw bytes of the artwork into a var
                tell application "\(itunesMusicName!)" to tell artwork 1 of current track
                    set srcBytes to raw data
            -- figure out the proper file extension
                    if format is «class PNG » then
                        set ext to ".png"
                    else
                        set ext to ".jpg"
                    end if
                end tell

            -- get the filename to ~/Desktop/cover.ext
            set fileName to (((path to desktop) as text) & "cover" & ext)

            tell application "System Events"
                delete alias fileName
            end tell
        end if
        """
    }
    static func prevTrack() -> String{
       return  """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    play (previous track)
                else
                    return ""
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    play (previous track)
                else
                    return ""
                end if
            end tell
        else
            return ""
        end if
        on checkSpotify()
            if application "Spotify" is running then
                    tell application "Spotify"
                        if player state is playing then
                            play (previous track)
                        else
                            return ""
                        end if
                    end tell
                else
                    return ""
            end if
        end checkSpotify
        """
    
    }
    static func nextTrack() -> String{
       return  """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    play (next track)
                else
                    return ""
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    play (next track)
                else
                    return ""
                end if
            end tell
        else
            return ""
        end if
        on checkSpotify()
            if application "Spotify" is running then
                    tell application "Spotify"
                        if player state is playing then
                            play (next track)
                        else
                            return ""
                        end if
                    end tell
                else
                    return ""
            end if
        end checkSpotify
        """
    
    }
    
    static func playPause() -> String{
        """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    pause current track
                else
                    if current track exists then
                        play current track
                    else
                        set shuffle enabled to true
                        play
                    end if
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                playpause
            end tell
        else
            tell application "\(itunesMusicName!)" to activate
            delay 5
            tell application "\(itunesMusicName!)" to set shuffle enabled to true
            tell application "\(itunesMusicName!)" to play
        end if

        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                    playpause
                end tell
            end if
        end checkSpotify
        """
    }
    
    static func skipBack() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    set player position to (player position - 15)
                else
                    return ""
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    set player position to (player position - 15)
                else
                    return ""
                end if
            end tell
        else
            return ""
        end if
        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                     if player state is playing then
                        set player position to (player position - 15)
                    else
                        return ""
                    end if
                end tell
            end if
        end checkSpotify
        """
    }
    static func skipAhead() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    set player position to (player position + 15)
                else
                    return ""
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    set player position to (player position + 15)
                else
                    return ""
                end if
            end tell
        else
            return ""
        end if
        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                     if player state is playing then
                        set player position to (player position + 15)
                    else
                        return ""
                    end if
                end tell
            end if
        end checkSpotify
        """
    }
    static func trackDuration() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return duration of current track
                else
                    return ""
                end if
            end tell
        else if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return duration of current track / 1000
                    else
                        return ""
                    end if
                end tell
        end if
        """
    }
    
    static func totalDuration() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return time of current track
                else
                    return ""
                end if
            end tell
        else if application "Spotify" is running then
                tell application "Spotify"
                    set tM to round (((duration of current track) / 1000) / 60) rounding down
                    set tS to round (((duration of current track) / 1000) mod 60) rounding down
                    set myTime to ((tM as text) & ":" & tS as text)
                    return myTime
                end tell
            end if
        """
    }
    
    static func scrubTrack(position: Double) -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    set player position to "\(position)"
                else
                    return ""
                end if
            end tell
        else if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        set player position to "\(position)"
                    else
                        return ""
                    end if
                end tell
        end if
        """
    }
    
    static func changeSlider() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return player position
                else
                    return ""
                end if
            end tell
        else if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return player position
                    else
                        return ""
                    end if
                end tell
        end if
        """
    }
    
    static func musicApp() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return "\(itunesMusicName!)"
                else
                    return ""
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return "Spotify"
                else
                    return ""
                end if
            end tell
        else
            return ""
        end if
        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                     if player state is playing then
                        return "Spotify"
                    else
                        return ""
                    end if
                end tell
            end if
        end checkSpotify
        """
    }
    
    static func songName() -> String{
       return  """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return name of current track
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return name of current track
                else
                    return ""
                end if
            end tell
        end if
        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return name of current track
                    else
                        return ""
                    end if
                end tell
            end if
        end checkSpotify
        """
    }
    
    static func songArtist() -> String {
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return artist of current track
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return artist of current track
                else
                    return ""
                end if
            end tell
        end if
        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return artist of current track
                    else
                        return ""
                    end if
                end tell
            end if
        end checkSpotify
        """
    }
        
        
}
