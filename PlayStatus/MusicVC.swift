//
//  MusicVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 4/25/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa
import Alamofire
import SwiftyJSON


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
    @IBOutlet weak var musicSlider: NSSlider!
    @IBOutlet weak var startTime: NSTextField!
    @IBOutlet weak var endTime: NSTextField!
    @IBOutlet weak var artistName: NSTextField!
    @IBOutlet weak var songName: NSTextField!
    @IBOutlet weak var musicButton: NSButton!
    @IBOutlet weak var searchButton: NSButton!
    @IBOutlet weak var visualEffectView: NSVisualEffectView!
    lazy var searchView: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "searchWindowController") as? NSWindowController
    var out: NSAppleEventDescriptor?
    var check = 0
    var songNameString = ""
    var artistNameString = ""
    
    private enum FadeType {
        case fadeIn, fadeOut
    }
    
    
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
    let prevTrackScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
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
    let playPauseTrackScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
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
        run application "iTunes"
        delay 7
        tell application "iTunes" to set shuffle enabled to true
        tell application "iTunes" to play
    end if

    on checkSpotify()
        if application "Spotify" is running then
            tell application "Spotify"
                playpause
            end tell
        end if
    end checkSpotify
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
    
    
    let appPlayingScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                return "iTunes"
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
    
    let skipAheadScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
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
    
    let skipBackScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
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
    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        
        
        self.view.wantsLayer = true
        self.view.layer?.cornerRadius = 8
        songDetails.wantsLayer = true
        songDetails.layer?.borderColor = .black
        songDetails.layer?.borderWidth = 1
        songDetails.layer?.cornerRadius = 8
        songDetails.layer?.masksToBounds = true
        songDetails.layerUsesCoreImageFilters = true
        songDetails.layer?.needsDisplayOnBoundsChange = true
        
        playButton.isHidden = true
        pauseButton.isHidden = true
        songDetails.isHidden = true
        prevButton.isHidden = true
        nextButton.isHidden = true
        quitButton.isHidden = true
        skipBack.isHidden = true
        skipAhead.isHidden = true
        musicSlider.isHidden = true
        startTime.isHidden = true
        endTime.isHidden = true
        songName.isHidden = true
        artistName.isHidden = true
        musicButton.isHidden = true
        searchButton.isHidden = true
        
        let area = NSTrackingArea.init(rect: albumArt.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        albumArt.addTrackingArea(area)
        
        
        _ = NSColor(
            calibratedHue: 230/360,
            saturation: 0.35,
            brightness: 0.85,
            alpha: 0.3)
        
        NotificationCenter.default.addObserver(self, selector: #selector(loadAlbumArtwork), name: NSNotification.Name(rawValue: "loadAlbum"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(close), name: NSNotification.Name(rawValue: "close"), object: nil)
        checkStatus()
        loadAlbumArtwork()
        fade()
        _ = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(changeSliderPosition), userInfo: nil, repeats: true)
    
        
    }
    @objc func close(){
        if searchView?.window?.isVisible == true
        {
            searchView?.close()
        }
    }
    
    @IBAction func searchButtonClicked(_ sender: Any) {
        if searchView?.window?.isVisible == true
        {
            searchView?.close()
        }else{
            
            displayPopUp()
        }
    }
    
    @objc func displayPopUp() {
        
        searchView?.window?.styleMask = .titled
        searchView?.window?.setFrameOrigin(NSPoint(x: xWidth, y: yHeight))
        searchView?.showWindow(self)
    }
    
    @IBAction func quitButtonClicked(_ sender: Any) {
        NSApp.terminate(self)
    }
    
    func checkStatus()
    {
        if let scriptObject = NSAppleScript(source: statusScpt) {
            out = scriptObject.executeAndReturnError(nil)
            let status = out?.stringValue ?? ""
            if status == "playing"
            {
                check = 1

            }else if status == "not playing"
            {
                check = 2
            }
        }
        
        
    }
    override func mouseEntered(with event: NSEvent) {
        
        fade(type: .fadeIn)
        if check == 1{
            songDetails.isHidden = false
            pauseButton.isHidden = false
            playButton.isHidden = true
            prevButton.isHidden = false
            nextButton.isHidden = false
            quitButton.isHidden = false
            skipBack.isHidden = false
            skipAhead.isHidden = false
            musicSlider.isHidden = false
            startTime.isHidden = false
            endTime.isHidden = false
            songName.isHidden = false
            artistName.isHidden = false
            musicButton.isHidden = false
            searchButton.isHidden = false
        }else if check == 2{
            playButton.isHidden = false
            pauseButton.isHidden = true
            songDetails.isHidden = false
            prevButton.isHidden = false
            nextButton.isHidden = false
            quitButton.isHidden = false
            skipBack.isHidden = false
            skipAhead.isHidden = false
            musicSlider.isHidden = false
            startTime.isHidden = false
            endTime.isHidden = false
            songName.isHidden = false
            artistName.isHidden = false
            musicButton.isHidden = false
            searchButton.isHidden = false
        }
        
    }
    
    private func fade(type: FadeType = .fadeOut) {
        
        let from = type == .fadeOut ? 1 : 0.2
        let to = 1 - from
        
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = from
        fadeAnim.toValue = to
        fadeAnim.duration = 0.5
        visualEffectView.layer?.add(fadeAnim, forKey: "opacity")
        
        visualEffectView.alphaValue = CGFloat(to)

    }
    
    override func mouseExited(with event: NSEvent) {
        fade()
        playButton.isHidden = true
        pauseButton.isHidden = true
        songDetails.isHidden = true
        prevButton.isHidden = true
        nextButton.isHidden = true
        quitButton.isHidden = true
        skipBack.isHidden = true
        skipAhead.isHidden = true
        musicSlider.isHidden = true
        startTime.isHidden = true
        endTime.isHidden = true
        songName.isHidden = true
        artistName.isHidden = true
        musicButton.isHidden = true
        searchButton.isHidden = true
    }
    
    @objc func loadAlbumArtwork()
    {
        var out: NSAppleEventDescriptor?
        checkStatus()
        trackDuration()
        songName.stringValue = currentSongName ?? ""
        artistName.stringValue = currentSongArtist ?? ""
        if let scriptObject = NSAppleScript(source: songImageScpt) {
            out = scriptObject.executeAndReturnError(nil)
            let imageName = out?.stringValue ?? ""
            if songName.stringValue == ""
            {
                albumArt.image = NSImage(named: "wallpaper2")
//                songDetails.stringValue = "No Music Playing"
                artistName.stringValue = "No Music Playing"
            }else if imageName.contains("http://"){
                songDetails.stringValue = ""
                let url = URL(string: imageName)
                albumArt.image = NSImage(contentsOf: url!)
            }else if imageName != ""{
                songDetails.stringValue = ""
                albumArt.image = NSImage(contentsOfFile: imageName)
            }else if imageName == "" && songName.stringValue != ""
            {
                let editedSongArtist = currentSongArtist.replacingOccurrences(of: "&", with: "+", options: .literal, range: nil)
                let safeArtistURL = editedSongArtist.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed)!
                let safeSongURL = currentSongName.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed)!
                let stringURL = "https://itunes.apple.com/search?term=\(safeArtistURL)+\(safeSongURL)&country=us&limit=1"
                let editedStringURL = stringURL.replacingOccurrences(of: " ", with: "+", options: .literal, range: nil)
                
                let url = URL(string: editedStringURL)
                AF.request(url!).responseData { (response) in
                    let json = JSON(response.data as Any)
                    let originalURL = json["results"][0]["artworkUrl100"].stringValue
                    let editedURL = originalURL.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg", options: .literal, range: nil)
                    let imageURL = URL(string: editedURL)
                    self.albumArt.image = NSImage(contentsOf: imageURL ?? URL(string: "https://images-wixmp-ed30a86b8c4ca887773594c2.wixmp.com/i/e7981d38-6ee3-496d-a6c0-8710745bdbfc/db6zlbs-68b8cd4f-bf6b-4d39-b9a7-7475cade812f.png")!)
                }

            }
            
        }
        deleteAlbum()
    }
    
    func deleteAlbum()
    {
        if let scriptObject = NSAppleScript(source: deleteScpt) {
            scriptObject.executeAndReturnError(nil)
        }
    }
    
    @IBAction func previousButtonClicked(_ sender: Any) {
        if let scriptObject = NSAppleScript(source: prevTrackScpt) {
            scriptObject.executeAndReturnError(nil)

        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    @IBAction func nextButtonClicked(_ sender: Any) {
    
        if let scriptObject = NSAppleScript(source: nextTrackScpt) {
            scriptObject.executeAndReturnError(nil)
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
            scriptObject.executeAndReturnError(nil)
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
        
    }
    
    @IBAction func skipBackButtonClicked(_ sender: Any) {
        if let scriptObject = NSAppleScript(source: skipBackScpt) {
            scriptObject.executeAndReturnError(nil)
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    
    @IBAction func skipAheadButtonClicked(_ sender: Any) {
        if let scriptObject = NSAppleScript(source: skipAheadScpt) {
            scriptObject.executeAndReturnError(nil)
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    func trackDuration()
    {
        let totalDurationScpt = """
        if application "iTunes" is running then
            tell application "iTunes"
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
        if let scriptObject = NSAppleScript(source: totalDurationScpt) {
            out = scriptObject.executeAndReturnError(nil)
            musicSlider.maxValue = Double(out?.stringValue ?? "") ?? 100
        }
        
        
        let totalDurationMinsScpt = """
        if application "iTunes" is running then
            tell application "iTunes"
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
        if let scriptObject = NSAppleScript(source: totalDurationMinsScpt) {
            out = scriptObject.executeAndReturnError(nil)
            endTime.stringValue = out?.stringValue ?? ""
        }

    }
    @IBAction func musicSliderChanged(_ sender: Any) {
        scrubTrack(position: musicSlider.doubleValue)
    }
    
    func scrubTrack(position : Double){
        let currentDurationScpt = """
        if application "iTunes" is running then
            tell application "iTunes"
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


        if let scriptObject = NSAppleScript(source: currentDurationScpt) {
            scriptObject.executeAndReturnError(nil)
        }
        loadAlbumArtwork()
    }
    
    @objc func changeSliderPosition()
    {
        let currentDurationScpt = """
        if application "iTunes" is running then
            tell application "iTunes"
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
        
        
        if let scriptObject = NSAppleScript(source: currentDurationScpt) {
            out = scriptObject.executeAndReturnError(nil)
            musicSlider.stringValue = out?.stringValue ?? ""
            startTime.stringValue = String(Int(Double(musicSlider.stringValue)! / 60) % 60) + ":" +  String(format: "%02d", Int(Double(musicSlider.stringValue)!.truncatingRemainder(dividingBy: 60)))
        }
    }
    
    @IBAction func musicButtonClicked(_ sender: Any) {
        if let scriptObject = NSAppleScript(source: appPlayingScpt) {
            out = scriptObject.executeAndReturnError(nil)
            
            if out?.stringValue == "iTunes"
            {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/iTunes.app"))
                self.dismiss(nil)
                
            } else if out?.stringValue == "Spotify"
            {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Spotify.app"))
                self.dismiss(nil)
            }
        }
        
        
    }
    

    
}


extension NSTextField{
    @IBInspectable var placeHolderColor: NSColor? {
        get {
            return self.placeHolderColor
        }
        set {
            self.placeholderAttributedString = NSAttributedString(string:self.placeholderString != nil ? self.placeholderString! : "", attributes:[NSAttributedString.Key.foregroundColor: newValue!])
        }
    }
}
