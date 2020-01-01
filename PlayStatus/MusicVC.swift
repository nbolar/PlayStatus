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
import CircularProgressMac


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
    @IBOutlet weak var trackDurationSliderCell: NSSlider!
    @IBOutlet weak var startTime: NSTextField!
    @IBOutlet weak var endTime: NSTextField!
    @IBOutlet weak var artistName: NSTextField!
    @IBOutlet weak var songName: NSTextField!
    @IBOutlet weak var musicButton: NSButton!
    @IBOutlet weak var searchButton: NSButton!
    @IBOutlet weak var settingsButton: NSButton!
    @IBOutlet weak var visualEffectView: NSVisualEffectView!
    lazy var searchView: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "searchWindowController") as? NSWindowController
    var out: NSAppleEventDescriptor?
    var check: Int!
    var songNameString = ""
    var artistNameString = ""
    private enum FadeType {
        case fadeIn, fadeOut
    }
    let circularProgress = CircularProgress(size: 28)
    

    
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
        trackDurationSliderCell.isHidden = false
        startTime.isHidden = true
        endTime.isHidden = true
        songName.isHidden = true
        artistName.isHidden = true
        musicButton.isHidden = true
        searchButton.isHidden = true
        settingsButton.isHidden = true
         let labelXPostion:CGFloat = view.bounds.midX - 10
        let labelYPostion:CGFloat = 3
        let labelWidth:CGFloat = 28
        let labelHeight:CGFloat = 28
        circularProgress.isIndeterminate = true
        circularProgress.frame = CGRect(x: labelXPostion, y: labelYPostion, width: labelWidth, height: labelHeight)
        circularProgress.color = .white
        
        let area = NSTrackingArea.init(rect: albumArt.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        albumArt.addTrackingArea(area)
        
        
        _ = NSColor(
            calibratedHue: 230/360,
            saturation: 0.35,
            brightness: 0.85,
            alpha: 0.3)
        
        NotificationCenter.default.addObserver(self, selector: #selector(loadAlbumArtwork), name: NSNotification.Name(rawValue: "loadAlbum"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(close), name: NSNotification.Name(rawValue: "close"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(searchButtonClicked(_:)), name: NSNotification.Name(rawValue: "search"), object: nil)
        checkStatus()
        loadAlbumArtwork()
        fade()

        _ = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(changeSliderPosition), userInfo: nil, repeats: true)
    
        
    }

    @objc func close(){
        if searchView?.window?.isVisible == true
        {
            searchView?.resignFirstResponder()
            searchView?.close()
        }
    }
    
    @IBAction func searchButtonClicked(_ sender: Any) {
        if searchView?.window?.isVisible == true
        {
            searchView?.resignFirstResponder()
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
        NSAppleScript.go(code: NSAppleScript.checkStatus(), completionHandler: {_,out,_ in
            let status = out?.stringValue ?? ""
            
            if status == "playing"
            {
                check = 1
                
            }else if status == "not playing"
            {
                check = 2
                
            }
        })

        
    }
    func hideUnhide(hide: Bool){
        songDetails.isHidden = hide
        
        prevButton.isHidden = hide
        nextButton.isHidden = hide
        quitButton.isHidden = hide
        skipBack.isHidden = hide
        skipAhead.isHidden = hide
        musicSlider.isHidden = hide
        trackDurationSliderCell.isHidden = !hide
        startTime.isHidden = hide
        endTime.isHidden = hide
        songName.isHidden = hide
        artistName.isHidden = hide
        musicButton.isHidden = hide
        searchButton.isHidden = hide
        settingsButton.isHidden = hide
    }
    override func mouseEntered(with event: NSEvent) {
        fade(type: .fadeIn)
        if check == 1{
            hideUnhide(hide: false)
            pauseButton.isHidden = false
            
        }else if check == 2{
            playButton.isHidden = false
            hideUnhide(hide: false)
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
        trackDurationSliderCell.isHidden = false
        startTime.isHidden = true
        endTime.isHidden = true
        songName.isHidden = true
        artistName.isHidden = true
        musicButton.isHidden = true
        searchButton.isHidden = true
        settingsButton.isHidden = true
    }
    
    @objc func loadAlbumArtwork()
    {
        checkStatus()
        trackDuration()
        songName.stringValue = currentSongName ?? ""
        artistName.stringValue = currentSongArtist ?? ""
        NSAppleScript.go(code: NSAppleScript.loadAlbumArtwork(), completionHandler: {_,out,_ in
            let imageName = out?.stringValue ?? ""
            if songName.stringValue == ""
            {
                albumArt.image = NSImage(named: "wallpaper2")
                //                songDetails.stringValue = "No Music Playing"
                artistName.stringValue = "No Music Playing"
            }else if imageName.contains("https://"){
                songDetails.stringValue = ""
                let url = URL(string: imageName)
                albumArt.image = NSImage(contentsOf: url!)
                circularProgress.removeFromSuperview()
            }else if imageName != ""{
                songDetails.stringValue = ""
                albumArt.image = NSImage(contentsOfFile: imageName)
                circularProgress.removeFromSuperview()
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
                    self.circularProgress.removeFromSuperview()
                }
                
            }
            
        } )
        deleteAlbum()
    }
    
    func deleteAlbum()
    {

        NSAppleScript.go(code: NSAppleScript.deleteAlbum(), completionHandler: {_,_,_ in })
    }
    
    @IBAction func previousButtonClicked(_ sender: Any) {
        view.addSubview(circularProgress)
        NSAppleScript.go(code: NSAppleScript.prevTrack(), completionHandler: {_,_,_ in })
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    @IBAction func nextButtonClicked(_ sender: Any) {
        view.addSubview(circularProgress)
        NSAppleScript.go(code: NSAppleScript.nextTrack(), completionHandler: {_,_,_ in })
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
        
    }
    
    @IBAction func playPauseButtonClicked(_ sender: Any) {
        if pauseButton.isHidden == true{
            view.addSubview(circularProgress)
            playButton.isHidden = true
            pauseButton.isHidden = false
        } else if pauseButton.isHidden == false
        {
            playButton.isHidden = false
            pauseButton.isHidden = true
        }
        NSAppleScript.go(code: NSAppleScript.playPause(), completionHandler: {_,_,_ in })
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
        
    }
    
    @IBAction func skipBackButtonClicked(_ sender: Any) {
        NSAppleScript.go(code: NSAppleScript.skipBack(), completionHandler: {_,_,_ in })
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    
    @IBAction func skipAheadButtonClicked(_ sender: Any) {
        NSAppleScript.go(code: NSAppleScript.skipAhead(), completionHandler: {_,_,_ in })
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        loadAlbumArtwork()
    }
    
    func trackDuration()
    {
        NSAppleScript.go(code: NSAppleScript.trackDuration(), completionHandler: {_,out,_ in
            musicSlider.maxValue = Double(out?.stringValue ?? "") ?? 100
            trackDurationSliderCell.maxValue = Double(out?.stringValue ?? "") ?? 100
        })
        
        NSAppleScript.go(code: NSAppleScript.totalDuration(), completionHandler: {_,out,_ in
            endTime.stringValue = out?.stringValue ?? ""
        })
        

    }
    @IBAction func musicSliderChanged(_ sender: Any) {
        NSAppleScript.go(code: NSAppleScript.scrubTrack(position: musicSlider.doubleValue), completionHandler: {_,_,_ in })
        loadAlbumArtwork()
    }
    
    @objc func changeSliderPosition()
    {
    
        NSAppleScript.go(code: NSAppleScript.changeSlider(), completionHandler: {_,out,_ in
            musicSlider.stringValue = out?.stringValue ?? ""
            trackDurationSliderCell.stringValue = out?.stringValue ?? ""
            if Double(musicSlider.stringValue)! >= 3600{
                startTime.stringValue = String(Int(Double(musicSlider.stringValue)! / 60) / 60) + ":" + String(format: "%02d", Int(Double(musicSlider.stringValue)! / 60) % 60) + ":" +  String(format: "%02d", Int(Double(musicSlider.stringValue)!.truncatingRemainder(dividingBy: 60)))
            }else{
                startTime.stringValue = String(Int(Double(musicSlider.stringValue)! / 60) % 60) + ":" +  String(format: "%02d", Int(Double(musicSlider.stringValue)!.truncatingRemainder(dividingBy: 60)))
            }
        })
    }
    
    @IBAction func musicButtonClicked(_ sender: Any) {
        NSAppleScript.go(code: NSAppleScript.musicApp(), completionHandler: {_,out,_ in
            if out?.stringValue == "\(itunesMusicName!)"
            {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/\(itunesMusicName!).app"))
                self.dismiss(nil)
                
            } else if out?.stringValue == "Spotify"
            {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Spotify.app"))
                self.dismiss(nil)
            }
        })
        
        
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
