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
    
    static func itunesArtwork() ->String{
        return """
        if application "\(itunesMusicName!)" is running then
        tell application "\(itunesMusicName!)"
            if exists artworks of current track then
                return (get data of artwork 1 of current track)
            end if
        end tell
        end if
        """
    }
        static func checkStatus()-> String{
            return """
            if application "\(statusApp!)" is running then
                tell application "\(statusApp!)"
                    if player state is playing then
                        return "playing"
                    else
                        return "not playing"
                    end if
                end tell
            else
                return "not playing"
            end if
            """
        }
    
    
    static func loadSpotifyAlbumArtwork() -> String{
        return """
        if application "Spotify" is running then
            tell application "Spotify"
                    return artwork url of current track
            end tell
        end if
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
        property lastPaused : "\(lastPausedApp!)"
        if (application "\(itunesMusicName!)" is running) and (application "Spotify" is running) then
            tell application "\(itunesMusicName!)" to set itunesState to (player state as text)
            tell application "Spotify" to set spotifyState to (player state as text)
            
            if itunesState is equal to "playing" then
                tell application "\(itunesMusicName!)" to playpause
                set lastPaused to "\(itunesMusicName!)"
            else if spotifyState is equal to "playing" then
                tell application "Spotify" to playpause
                set lastPaused to "Spotify"
            else if ((itunesState is equal to "paused") and (lastPaused is equal to "\(itunesMusicName!)")) then
                tell application "\(itunesMusicName!)" to playpause
                set lastPaused to "\(itunesMusicName!)"
            else if ((spotifyState is equal to "paused") and (lastPaused is equal to "Spotify")) then
                tell application "Spotify" to playpause
                set lastPaused to "Spotify"
            end if
        else if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)" to playpause
        else if application "Spotify" is running then
            tell application "Spotify" to playpause
        else
            tell application "\(musicAppChoice!)" to activate
            delay 5
            tell application "\(musicAppChoice!)" to play
        end if
        return lastPaused
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
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return duration of current track / 1000
                    else
                        return ""
                    end if
                end tell
        end if
        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                     if player state is playing then
                        return duration of current track / 1000
                    else
                        return ""
                    end if
                end tell
            end if
        end checkSpotify
        """
    }
    
    static func totalDuration() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return time of current track
                end if
            end tell
         checkSpotify()
        else if application "Spotify" is running then
                tell application "Spotify"
                    set tM to round (((duration of current track) / 1000) / 60) rounding down
                    set tS to round (((duration of current track) / 1000) mod 60) rounding down
                    if tS < 10 then
                        set tS to (0 & tS as text)
                    end if
                    set myTime to ((tM as text) & ":" & tS as text)
                    return myTime
                end tell
            end if
        on checkSpotify()
            if application "Spotify" is running then
                tell application "Spotify"
                    set tM to round (((duration of current track) / 1000) / 60) rounding down
                    set tS to round (((duration of current track) / 1000) mod 60) rounding down
                    if tS < 10 then
                        set tS to (0 & tS as text)
                    end if
                    set myTime to ((tM as text) & ":" & tS as text)
                    return myTime
                end tell
            end if
        end checkSpotify
        """
    }
    
    static func scrubTrack(position: Double) -> String{
        return """
        if application "\(activeMusicApp!)" is running then
            tell application "\(activeMusicApp!)"
                if player state is playing then
                    set player position to "\(position)"
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
                end if
            end tell
        checkSpotify()
        else if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return player position
                    else
                        return ""
                    end if
                end tell
        end if
        on checkSpotify()
           if application "Spotify" is running then
               tell application "Spotify"
                    if player state is playing then
                        return player position
                    else
                        return ""
                   end if
               end tell
           end if
        end checkSpotify
        """
    }
    
    static func musicApp() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return "\(itunesMusicName!)"
                end if
            end tell
            checkSpotify()
        else if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return "Spotify"
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
                    end if
                end tell
            else
                return ""
            end if
        end checkSpotify
        """
    }
    static func musicAppOnly() -> String{
        return """
        if application "\(itunesMusicName!)" is running then
            tell application "\(itunesMusicName!)"
                if player state is playing then
                    return "\(itunesMusicName!)"
                else
                    return "\(lastPausedApp!)"
                end if
            end tell
        else
            return ""
        end if
        """
    }
    
    static func checkSpotifyPresence() -> String{
        return """
        try
            tell application "Finder" to get application file id "com.spotify.client"
            return true
        on error
            return false
        end try
        """
    }
    
    static func songName() -> String{
       return  """
        if application "\(activeMusicApp!)" is running then
            tell application "\(activeMusicApp!)"
                return name of current track
            end tell
        end if
        """
    }
    static func albumName() -> String{
        return """
        if application "\(activeMusicApp!)" is running then
            tell application "\(activeMusicApp!)"
                return album of current track
            end tell
        end if
        """
    }
    
    static func songArtist() -> String {
        return """
        if application "\(activeMusicApp!)" is running then
            tell application "\(activeMusicApp!)"
                return artist of current track
            end tell
        end if
        """
    }
    
    static func restartApp() -> String {
        return """
            do shell script "killall PlayStatus; open -a Playstatus"
        """
    }
    
    static func increasePlayerVol() -> String {
        return """
            tell application "\(activeMusicApp!)"
                set vol to sound volume
                set sound volume to vol + 5
            end tell
        """
    }
    
    static func decreasePlayerVol() -> String {
        return """
            tell application "\(activeMusicApp!)"
                set vol to sound volume
                set sound volume to vol - 5
            end tell
        """
    }
    
    static func increaseSystemVol() -> String {
        return """
            set vol to output volume of (get volume settings)
            set volume output volume vol + 5
        """
    }
    static func decreaseSystemVol() -> String {
        return """
            set vol to output volume of (get volume settings)
            set volume output volume vol - 5
        """
    }
        
        
}
