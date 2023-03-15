//
//  MusicVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 4/25/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa
import CircularProgress


class MusicVC: NSViewController {
    static let shared = MusicVC()
    
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
    private var settingsController: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "settingsWindowController") as? NSWindowController
    private var preferencesController: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "preferencesWindowController") as? NSWindowController
    lazy var searchView: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "searchWindowController") as? NSWindowController
    var out: NSAppleEventDescriptor?
    var check: Int!
    var songNameString = ""
    var artistNameString = ""
    private var timer : Timer!
    private enum FadeType {
        case fadeIn, fadeOut
    }
    private enum SongType {
        case newSong, oldSong
    }
    private enum AppType {
        case spotify, itunes
    }
    let circularProgress = CircularProgress(size: 28)
    var newSong = false
    var pausedSong = ""
    var pausedArtist = ""
    private var app: AppType = .itunes
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        setupObservers()
        setupUI()
        
    }
    
    
    override func viewDidAppear() {
        loadAlbumArtwork()
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(changeSliderPosition), userInfo: nil, repeats: true)
        timer.fire()
        
    }
    
    override func viewDidDisappear() {
        timer.invalidate()
        timer = nil
    }
    
    func setupObservers(){
        NotificationCenter.default.addObserver(self, selector: #selector(newSongArtwork), name: NSNotification.Name(rawValue: "newSong"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(close), name: NSNotification.Name(rawValue: "close"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(searchButtonClicked(_:)), name: NSNotification.Name(rawValue: "search"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playPauseButtonClicked(_:)), name: NSNotification.Name(rawValue: "playPause"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(previousButtonClicked(_:)), name: NSNotification.Name(rawValue: "previousTrack"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(nextButtonClicked(_:)), name: NSNotification.Name(rawValue: "nextTrack"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(loadingSplash), name: NSNotification.Name(rawValue: "loadingSplash"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(removeSplash), name: NSNotification.Name(rawValue: "removeSplash"), object: nil)
    }
    
    
    func setupUI(){
        self.view.wantsLayer = true
        self.view.layer?.cornerRadius = 8
        self.view.layer?.backgroundColor = .black
        songDetails.wantsLayer = true
        songDetails.layer?.borderColor = .black
        songDetails.layer?.borderWidth = 1
        songDetails.layer?.cornerRadius = 8
        visualEffectView.layer?.cornerRadius = 8
        songDetails.layer?.masksToBounds = true
        songDetails.layerUsesCoreImageFilters = true
        songDetails.layer?.needsDisplayOnBoundsChange = true
        trackDurationSliderCell.isHidden = true
        
        let labelXPostion:CGFloat = view.bounds.midX - 10
        let labelYPostion:CGFloat = 3
        let labelWidth:CGFloat = 28
        let labelHeight:CGFloat = 28
        circularProgress.isIndeterminate = true
        circularProgress.frame = CGRect(x: labelXPostion, y: labelYPostion, width: labelWidth, height: labelHeight)
        circularProgress.color = .white
        view.layer?.backgroundColor = NSColor.init(white: 1, alpha: 0.8).cgColor
        let area = NSTrackingArea.init(rect: albumArt.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        albumArt.addTrackingArea(area)
        hideEverything()
    }
    
    func hideEverything(){
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
        visualEffectView.isHidden = true
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
        searchView?.window?.setFrameOrigin(NSPoint(x: xWidth, y: yHeight - 27))
        searchView?.showWindow(self)
    }
    
    @IBAction func quitButtonClicked(_ sender: Any) {
        NSApp.terminate(self)
    }
    
    func checkStatus()
    {
        check = MusicController.shared.checkPlayerStatus()
        NSAppleScript.go(code: NSAppleScript.musicApp(), completionHandler: {_,out,_ in
            if out?.stringValue == "Spotify"{
                app = .spotify
                
            }
            else if out?.stringValue == itunesMusicName{
                app = .itunes
            }
        })
        
    }
    func hideUnhide(hide: Bool){
        songDetails.isHidden = hide
        
        prevButton.isHidden = hide
        nextButton.isHidden = hide
        quitButton.isHidden = hide
        //        skipBack.isHidden = hide
        //        skipAhead.isHidden = hide
        trackDurationSliderCell.isHidden = !hide
        songName.isHidden = hide
        artistName.isHidden = hide
        musicButton.isHidden = hide
        musicButton.image = NSImage(named: "\(iconName!)2")
        visualEffectView.isHidden = hide
        settingsButton.isHidden = hide
        if app == .spotify {
            searchButton.isHidden = true
        }else{
            searchButton.isHidden = false
        }
        
    }
    override func mouseEntered(with event: NSEvent) {
        
        fade(type: .fadeIn)
        if check == 1{
            hideUnhide(hide: false)
            pauseButton.isHidden = false
            startTime.isHidden = false
            endTime.isHidden = false
            musicSlider.isHidden = false
            
        }else if check == 2{
            playButton.isHidden = false
            startTime.isHidden = true
            endTime.isHidden = true
            musicSlider.isHidden = false
            hideUnhide(hide: false)
        }
        
    }
    
    private func fade(type: FadeType = .fadeOut, duration: SongType = .oldSong) {
        
        let from = type == .fadeOut ? 1 : 0.1
        let to = 1 - from
        
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = from
        fadeAnim.toValue = to
        fadeAnim.duration = duration == .oldSong ? 0.3 : 2
        visualEffectView.layer?.add(fadeAnim, forKey: "opacity")
        
        visualEffectView.alphaValue = CGFloat(to)
        
        //        /// Made changes to artwork fading
        //        if duration == .newSong{
        //            let fadeAnimNew = CABasicAnimation(keyPath: "opacity")
        //            fadeAnimNew.fromValue = to
        //            fadeAnimNew.toValue = from
        //            fadeAnimNew.duration = duration == .oldSong ? 0.3 : 1
        //            self.albumArt.layer?.add(fadeAnimNew, forKey: "opacity")
        //            self.albumArt.alphaValue = CGFloat(from)
        //        }
        
    }
    
    override func mouseExited(with event: NSEvent) {
        
        fade()
        hideEverything()
    }
    
    @objc func newSongArtwork(){
        newSong = true
        if view.window!.isVisible {
            loadAlbumArtwork()
        }
        
    }
    @objc func loadingSplash(){
        
        view.addSubview(circularProgress)
    }
    
    @objc func removeSplash(){
        
        circularProgress.removeFromSuperview()
    }
    
    @objc func loadAlbumArtwork()
    {
        checkStatus()
        trackDuration()
        
        if currentSongName == "" {
            songName.stringValue = pausedSong
            artistName.stringValue = pausedArtist
        }else{
            songName.stringValue = currentSongName
            artistName.stringValue = currentSongArtist
        }
        
        
        if songName.stringValue != ""
        {
            if MusicController.shared.musicApp() == "Spotify"{
                spotifyArtwork()
                
            }else if MusicController.shared.musicApp() == "\(itunesMusicName!)"{
                iTunesArtwork()
            }else{
                if lastPausedApp == "Spotify"{
                    spotifyArtwork()
                }else{
                    iTunesArtwork()
                }
            }
            
        }else{
            DispatchQueue.main.async {
                self.noArtwork()
            }
            //            albumArt.image = NSImage(named: "artwork")
        }
    }
    
    func noArtwork(){
        musicButton.image = NSImage(named: "\(iconName!)2")
        self.fade(type: .fadeIn, duration: .newSong)
        if currentSongName != ""{
            self.albumArt.image = NSImage(named: "artwork")
        }else{
            //            self.albumArt.image = NSImage(named: "playstatus_back")
        }
        
        self.fade(type: .fadeOut, duration: .newSong)
        self.circularProgress.removeFromSuperview()
    }
    
    func newArtworkURL(url: URL){
        self.fade(type: .fadeIn, duration: .newSong)
        self.albumArt.image = NSImage(contentsOf: url)
        self.fade(type: .fadeOut, duration: .newSong)
        self.newSong = false
    }
    
    func spotifyArtwork(){
        musicButton.image = NSImage(named: "\(iconName!)2")
        app = .spotify
        NSAppleScript.go(code: NSAppleScript.loadSpotifyAlbumArtwork(), completionHandler: {_,out,_ in
            
            let imageURL = URL(string: (out?.stringValue ?? ""))
            if out?.stringValue == nil{
                downloadMusicArtwork()
            }else{
                if imageURL?.absoluteString == ""
                {
                    noArtwork()
                }
                else{
                    if newSong{
                        newArtworkURL(url: imageURL!)
                    }else{
                        self.albumArt.image = NSImage(contentsOf: imageURL!)
                    }
                }
            }

            
            self.circularProgress.removeFromSuperview()
        })
    }
    
    func iTunesArtwork(){
        musicButton.image = NSImage(named: "\(iconName!)2")
        NSAppleScript.go(code: NSAppleScript.itunesArtwork(), completionHandler: {_,output,_ in
            if output?.data.count != 0{
                self.circularProgress.removeFromSuperview()
                if self.newSong{
                    self.fade(type: .fadeIn, duration: .newSong)
                    self.albumArt.image = NSImage(data: (output?.data)!)
                    self.fade(type: .fadeOut, duration: .newSong)
                    self.newSong = false
                }else{
                    self.albumArt.image = NSImage(data: (output?.data)!)
                }
                self.circularProgress.removeFromSuperview()
            }else{
                downloadMusicArtwork()
            }
            
        })
    }
    
    func downloadMusicArtwork(){
        let editedSongArtist = currentSongArtist.replacingOccurrences(of: "&", with: "+", options: .literal, range: nil)
        let safeArtistURL = editedSongArtist.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) ?? ""
        let safeSongURL = currentSongName.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) ?? ""
        let safeAlbumURL = currentAlbumName.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) ?? ""
        let stringURL = "https://itunes.apple.com/search?term=\(safeArtistURL)+\(safeAlbumURL)+\(safeSongURL)&country=us&limit=1"
        let editedStringURL = stringURL.replacingOccurrences(of: " ", with: "+", options: .literal, range: nil)
        
        let url = URL(string: editedStringURL)
        URLSession.shared.dataTask(with:url!, completionHandler: {(data, response, error) in
            guard let data = data, error == nil else { return }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String:Any]
                let posts = json!["results"] as? [[String: Any]] ?? []
                if posts.count != 0{
                    let originalURL = posts[0]["artworkUrl100"] as! String
                    let editedURL = originalURL.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg", options: .literal, range: nil)
                    let imageURL = URL(string: editedURL)!
                    DispatchQueue.main.async {
                        if self.newSong{
                            self.newArtworkURL(url: imageURL)
                        }else{
                            self.albumArt.image = NSImage(contentsOf: imageURL)
                        }
                        self.circularProgress.removeFromSuperview()
                    }
                }else{
                    DispatchQueue.main.async {
                        self.noArtwork()
                    }
                }
                
                
            } catch {
                print(error)
            }
        }).resume()
    }
    
    @IBAction func previousButtonClicked(_ sender: Any) {
        view.addSubview(circularProgress)
        NSAppleScript.go(code: NSAppleScript.prevTrack(), completionHandler: {_,_,_ in })
        
    }
    
    @IBAction func nextButtonClicked(_ sender: Any) {
        view.addSubview(circularProgress)
        NSAppleScript.go(code: NSAppleScript.nextTrack(), completionHandler: {_,_,_ in })
        
    }
    
    /// Method to perform ease in animation
    private func performAnimation(type: FadeType = .fadeIn){
        fade(type: .fadeIn, duration: .newSong)
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        let animationType = type == .fadeIn ? 350 : -350
        animation.values = [animationType, 0, 0]
        animation.keyTimes = [0, 1, 0]
        animation.duration = 1
        animation.isAdditive = true
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        albumArt.layer?.add(animation, forKey: nil)
        
    }
    
    @IBAction func playPauseButtonClicked(_ sender: Any) {
        if pauseButton.isHidden == true{
            view.addSubview(circularProgress)
            if !songDetails.isHidden {
                playButton.isHidden = true
                pauseButton.isHidden = false
            }
            
        } else if pauseButton.isHidden == false
        {
            pausedSong = currentSongName
            pausedArtist = currentSongArtist
            if !songDetails.isHidden{
                playButton.isHidden = false
                pauseButton.isHidden = true
            }
            
        }
        if (trackDurationSliderCell.doubleValue != 0){
            circularProgress.removeFromSuperview()
        }
        if UserDefaults.standard.integer(forKey: "musicApp") == 0{
            musicAppChoice = "Spotify"
        }else{
            musicAppChoice = "\(itunesMusicName!)"
        }
        NSAppleScript.go(code: NSAppleScript.playPause(), completionHandler: {_,out,_ in
            lastPausedApp =  out?.stringValue ?? ""

        })
        //        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        //        appDelegate.getSongName()
        if view.window!.isVisible {
            loadAlbumArtwork()
        }
        
    }
    
    /* @IBAction func skipBackButtonClicked(_ sender: Any) {
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
     }*/
    
    func trackDuration()
    {
        musicSlider.maxValue = MusicController.shared.trackDuration()
        trackDurationSliderCell.maxValue = MusicController.shared.trackDuration()
        
        endTime.stringValue = MusicController.shared.endTime()
        if endTime.stringValue != ""{
            endTime.isHidden = false
            if pauseButton.isHidden{
                musicSlider.isHidden = true
                startTime.isHidden = true
                endTime.isHidden = true
            }else{
                musicSlider.isHidden = false
                startTime.isHidden = false
                endTime.isHidden = false
            }
            
            
        }else{
            musicSlider.isHidden = true
            startTime.isHidden = true
        }
        
    }
    @IBAction func musicSliderChanged(_ sender: Any) {
        MusicController.shared.sliderChanged(musicSlider: musicSlider.doubleValue)
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
        if MusicController.shared.musicApp() == "Spotify" ||  UserDefaults.standard.integer(forKey: "musicApp") == 0
        {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Spotify.app"))
        } else if MusicController.shared.musicApp() == "iTunes" ||  UserDefaults.standard.integer(forKey: "musicApp") == 1
        {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/\(itunesMusicName!).app"))
        }
        self.dismiss(nil)
        
    }
    @IBAction func settingsButtonClicked(_ sender: Any) {
        self.view.window?.close()
        if let window = preferencesController {
            window.showWindow(self)
            window.window?.center()
            window.window?.makeKeyAndOrderFront(self)
            
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
    }
    
    
}


extension NSTextField{
    @IBInspectable var placeHolderColor: NSColor? {
        get {
            return self.placeHolderColor
        }
        set {
            self.placeholderAttributedString = NSAttributedString(string:self.placeholderString != nil ? self.placeholderString! : "", attributes:[NSAttributedString.Key.foregroundColor: newValue!, .font:NSFont.init(name: "Avenir Next Regular", size: 13) as Any])
        }
    }
}
