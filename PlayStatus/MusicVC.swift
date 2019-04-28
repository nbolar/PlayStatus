//
//  MusicVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 4/25/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa


class MusicVC: NSViewController {

    @IBOutlet weak var albumArt: NSImageView!
    @IBOutlet weak var songDetails: NSTextField!
    @IBOutlet weak var pauseButton: NSButton!
    @IBOutlet weak var playButton: NSButton!
    @IBOutlet weak var prevButton: NSButton!
    @IBOutlet weak var nextButton: NSButton!
    @IBOutlet weak var quitButton: NSButton!
    @IBOutlet weak var skipBack: NSButton!
    @IBOutlet weak var skipAhead: NSButton!
    
    var out: NSAppleEventDescriptor?
    var check = 0
    
    let songImageScpt = """
    if application "iTunes" is running then
    -- get the raw bytes of the artwork into a var
        tell application "iTunes" to tell artwork 1 of current track
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

    else if application "Spotify" is running then
        tell application "Spotify"
            if player state is playing then
                return artwork url of current track
            else
                return ""
            end if
        end tell
    end if
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
    
    
    let deleteScpt = """
    if application "iTunes" is running then
        -- get the raw bytes of the artwork into a var
            tell application "iTunes" to tell artwork 1 of current track
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
    
    let nextTrackScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                play (next track)
            else
                return ""
            end if
        end tell
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
    """
    let prevTrackScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                play (previous track)
            else
                return ""
            end if
        end tell
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
    """
    let playPauseTrackScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                pause current track
            else
                if current track exists then
                    play current track
                else
                    play some track
                end if
            end if
        end tell
    else if application "Spotify" is running then
        tell application "Spotify"
            playpause
        end tell
    else
        run application "iTunes"
        delay 7
        tell application "iTunes" to play some track
    end if
    """
    
    let statusScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                return "playing"
            else
                return "not playing"
            end if
        end tell
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
    """
    
    let skipAheadScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                set player position to (player position + 15)
            else
                return ""
            end if
        end tell
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
    """
    
    let skipBackScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                set player position to (player position - 15)
            else
                return ""
            end if
        end tell
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
    """
    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.view.wantsLayer = true
        self.view.layer?.cornerRadius = 8
        songDetails.wantsLayer = true
        songDetails.layer?.backgroundColor = CGColor.init(gray: 0.9, alpha: 0.5)
        songDetails.layer?.cornerRadius = 8
        
        playButton.isHidden = true
        pauseButton.isHidden = true
        songDetails.isHidden = true
        prevButton.isHidden = true
        nextButton.isHidden = true
        quitButton.isHidden = true
        skipBack.isHidden = true
        skipAhead.isHidden = true
        let area = NSTrackingArea.init(rect: albumArt.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        albumArt.addTrackingArea(area)
        
        checkStatus()
        loadAlbumArtwork()
        _ = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(loadAlbumArtwork), userInfo: nil, repeats: true)
        
    }
    
    @IBAction func quitButtonClicked(_ sender: Any) {
        NSApp.terminate(self)
    }
    
    func checkStatus()
    {
        if let scriptObject = NSAppleScript(source: statusScpt) {
            var errorDict: NSDictionary? = nil
            out = scriptObject.executeAndReturnError(&errorDict)
            let status = out?.stringValue ?? ""
            if status == "playing"
            {
                check = 1

            }else if status == "not playing"
            {
                check = 2
            }
            if let error = errorDict {
                print(error)
            }
        }
        
        
    }
    override func mouseEntered(with event: NSEvent) {
        
        if check == 1{
            songDetails.isHidden = false
            pauseButton.isHidden = false
            playButton.isHidden = true
            prevButton.isHidden = false
            nextButton.isHidden = false
            quitButton.isHidden = false
            skipBack.isHidden = false
            skipAhead.isHidden = false
        }else if check == 2{
            playButton.isHidden = false
            pauseButton.isHidden = true
            songDetails.isHidden = false
            prevButton.isHidden = false
            nextButton.isHidden = false
            quitButton.isHidden = false
            skipBack.isHidden = false
            skipAhead.isHidden = false

        }
        
    }
    
    override func mouseExited(with event: NSEvent) {
        playButton.isHidden = true
        pauseButton.isHidden = true
        songDetails.isHidden = true
        prevButton.isHidden = true
        nextButton.isHidden = true
        quitButton.isHidden = true
        skipBack.isHidden = true
        skipAhead.isHidden = true
    }
    
    @objc func loadAlbumArtwork()
    {
        var out: NSAppleEventDescriptor?
//        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        checkStatus()
        if let scriptObject = NSAppleScript(source: songImageScpt) {
            var errorDict: NSDictionary? = nil
            out = scriptObject.executeAndReturnError(&errorDict)
            let imageName = out?.stringValue ?? ""
//            print(imageName)
            if imageName == ""
            {
                albumArt.image = NSImage(named: "wallpaper2")
                songDetails.stringValue = "No Music Playing"
            }else if imageName.contains("http://"){
                songDetails.stringValue = ""
                let url = URL(string: imageName)
                albumArt.image = NSImage(contentsOf: url!)
            }else{
                songDetails.stringValue = ""
                albumArt.image = NSImage(contentsOfFile: imageName)
            }
            
            if let error = errorDict {
                print(error)
            }
        }
        deleteAlbum()
    }
    
    func deleteAlbum()
    {
        if let scriptObject = NSAppleScript(source: deleteScpt) {
            var errorDict: NSDictionary? = nil
            scriptObject.executeAndReturnError(&errorDict)
            
            if let error = errorDict {
                print(error)
            }
        }
        
    }
    
    @IBAction func previousButtonClicked(_ sender: Any) {
        if let scriptObject = NSAppleScript(source: prevTrackScpt) {
            var errorDict: NSDictionary? = nil
            scriptObject.executeAndReturnError(&errorDict)
            
            if let error = errorDict {
                print(error)
            }
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    @IBAction func nextButtonClicked(_ sender: Any) {
    
        if let scriptObject = NSAppleScript(source: nextTrackScpt) {
            var errorDict: NSDictionary? = nil
            scriptObject.executeAndReturnError(&errorDict)
            
            if let error = errorDict {
                print(error)
            }
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
        
    }
    
    @IBAction func playPauseButtonClicked(_ sender: Any) {
        if pauseButton.isHidden == true{
            playButton.isHidden = true
            pauseButton.isHidden = false
        } else if pauseButton.isHidden == false
        {
            playButton.isHidden = false
            pauseButton.isHidden = true
        }
        if let scriptObject = NSAppleScript(source: playPauseTrackScpt) {
            var errorDict: NSDictionary? = nil
            scriptObject.executeAndReturnError(&errorDict)
            
            if let error = errorDict {
                print(error)
            }
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
        
    }
    
    @IBAction func skipBackButtonClicked(_ sender: Any) {
        if let scriptObject = NSAppleScript(source: skipBackScpt) {
            var errorDict: NSDictionary? = nil
            scriptObject.executeAndReturnError(&errorDict)
            
            if let error = errorDict {
                print(error)
            }
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    
    @IBAction func skipAheadButtonClicked(_ sender: Any) {
        if let scriptObject = NSAppleScript(source: skipAheadScpt) {
            var errorDict: NSDictionary? = nil
            scriptObject.executeAndReturnError(&errorDict)
            
            if let error = errorDict {
                print(error)
            }
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    
}
