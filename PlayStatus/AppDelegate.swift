//
//  AppDelegate.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 4/25/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa
import KeyboardShortcuts
import Sparkle



class AppDelegate: NSObject, NSApplicationDelegate, CAAnimationDelegate {
    
    var songName: String!
    var artistName: String!
    var out: NSAppleEventDescriptor?
    
    let updaterController: SPUStandardUpdaterController
    
    private var lastStatusTitle: String = ""
    let popoverView = NSPopover()
    lazy var aboutView: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "aboutWindowController") as? NSWindowController
    let invisibleWindow = NSWindow(contentRect: NSMakeRect(0, 0, 20, 1), styleMask: .borderless, backing: .buffered, defer: false)
    private var musicController: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "musicViewController") as? NSWindowController
    private var timer: Timer?
    let newStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let notificationCenter = NSWorkspace.shared.notificationCenter
    private enum Constants {
        static let statusItemIconLength: CGFloat = 30
        static var statusItemLength: CGFloat = 200
    }
    private lazy var statusItem: NSStatusItem = {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = Constants.statusItemIconLength
        return statusItem
    }()
    private lazy var scrollingStatusItemView: ScrollingStatusItemView = {
        let view = ScrollingStatusItemView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.lengthHandler = handleLength
        return view
    }()
    
    private lazy var handleLength: StatusItemLengthUpdate = { length in
        if length < Constants.statusItemLength {
            self.statusItem.length = length - 15
        } else {
            self.statusItem.length = Constants.statusItemLength
        }
    }
    
    private lazy var contentView: NSView? = {
        let view = (statusItem.value(forKey: "window") as? NSWindow)?.contentView
        return view
    }()
    
    var currentTrack: String? {
        didSet {
            if oldValue != currentTrack {
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "newSong"), object: nil)
                if currentTrack != " " && UserDefaults.standard.bool(forKey: "slideTitle") == true{
                    let animation = CAKeyframeAnimation(keyPath: "position.x")
                    let animationType = 300
                    animation.values = [animationType, 0, 0]
                    animation.keyTimes = [0, 1, 0]
                    animation.duration = 1.0
                    animation.isAdditive = true
                    animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    newStatusItem.button?.layer?.add(animation, forKey: nil)
                }
                
            }else{
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "removeSplash"), object: nil)
            }
            
        }
    }
    
    override init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        if #available(OSX 10.15, *){
            itunesMusicName = "Music"
        }else{
            itunesMusicName = "iTunes"
        }
        
        
        
        
        
        timer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(getSongName), userInfo: nil, repeats: true)
        timer?.tolerance = 0.3
        notificationCenter.addObserver(self, selector: #selector(AppDelegate.wakeUpListener), name: NSWorkspace.didWakeNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(AppDelegate.sleepListener), name: NSWorkspace.willSleepNotification, object: nil)
        invisibleWindow.backgroundColor = .clear
        invisibleWindow.alphaValue = 0
        
        musicController?.window?.isOpaque = false
        musicController?.window?.backgroundColor = .clear
        musicController?.window?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        
        if UserDefaults.standard.integer(forKey: "musicApp") == 0{
            musicAppChoice = "Spotify"
            iconName = "spotify"
        }else{
            musicAppChoice = "\(itunesMusicName!)"
            iconName = "itunes"
        }
        if UserDefaults.standard.object(forKey: "slideTitle") == nil{
            UserDefaults.standard.setValue(false, forKey: "slideTitle")
            
        }
        
        if UserDefaults.standard.object(forKey: "scrollableLength") != nil{
            if let n = NumberFormatter().number(from: UserDefaults.standard.object(forKey: "scrollableLength") as! String) {
                let value = CGFloat(truncating: n)
                Constants.statusItemLength = value
            }
        }
        
        lastPausedApp = "\(musicAppChoice!)"
        loadStatusItem()
        loadHotkeys()
        
        
        
    }
    
    func loadHotkeys(){
        KeyboardShortcuts.onKeyDown(for: .playPause) { [self] in
            playPauseMenuItem(self)
        }
        KeyboardShortcuts.onKeyDown(for: .nextTrack) { [self] in
            
            nextTrackMenuItem(self)
        }
        KeyboardShortcuts.onKeyDown(for: .prevTrack) { [self] in
            
            previousTrackMenuItem(self)
        }
        KeyboardShortcuts.onKeyDown(for: .playerVolUp) { [] in
            NSAppleScript.go(code: NSAppleScript.increasePlayerVol(), completionHandler: {_,_,_ in})
        }
        KeyboardShortcuts.onKeyDown(for: .playerVolDown) { [] in
            NSAppleScript.go(code: NSAppleScript.decreasePlayerVol(), completionHandler: {_,_,_ in})
        }
        KeyboardShortcuts.onKeyDown(for: .systemVolUp) { [] in
            NSAppleScript.go(code: NSAppleScript.increaseSystemVol(), completionHandler: {_,_,_ in})
        }
        KeyboardShortcuts.onKeyDown(for: .systemVolDown) { [] in
            NSAppleScript.go(code: NSAppleScript.decreaseSystemVol(), completionHandler: {_,_,_ in})
        }
    }
    
    func loadStatusItem(){
        if UserDefaults.standard.bool(forKey: "scrollable") == false {
            newStatusItem.button?.image = NSImage(named: "\(iconName!)")
            newStatusItem.button?.imagePosition = .imageLeft
            newStatusItem.button?.sendAction(on: [NSEvent.EventTypeMask.leftMouseUp, NSEvent.EventTypeMask.rightMouseUp])
            newStatusItem.button?.action = #selector(self.togglePopover(_:))
            
        }else{
            statusItem.button?.sendAction(on: [NSEvent.EventTypeMask.leftMouseUp, NSEvent.EventTypeMask.rightMouseUp])
            statusItem.button?.action = #selector(self.togglePopover(_:))
            loadSubviews()
        }
    }
    
    
    
    func applicationWillResignActive(_ notification: Notification) {
        if musicController?.window?.isVisible == true
        {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "close"), object: nil)
            musicController?.close()
        }
    }
    
    
    @objc func togglePopover(_ sender: Any?) {
        let event = NSApp.currentEvent!
        
        if event.type == NSEvent.EventType.leftMouseUp
        {
            if musicController?.window?.isVisible == true
            {
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "close"), object: nil)
                musicController?.close()
            }else{
                if UserDefaults.standard.bool(forKey: "scrollable") == false {
                    displayPopUp(status: newStatusItem)
                }else{
                    displayPopUp(status: statusItem)
                }
            }
            
        }else if event.type == NSEvent.EventType.rightMouseUp{
            
            var appVersion: String? {
                return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            }
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "PlayStatus version \(appVersion ?? "")", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Report Issues", action: #selector(issues), keyEquivalent: "")
            menu.addItem(withTitle: "About", action: #selector(aboutMenu), keyEquivalent: "")
            menu.addItem(NSMenuItem(title: "Quit PlayStatus", action: #selector(self.quitApp), keyEquivalent: "q"))
            
            if UserDefaults.standard.bool(forKey: "scrollable") == false {
                newStatusItem.menu = menu
                newStatusItem.button?.performClick(nil)
                newStatusItem.menu = nil
                
            }else{
                statusItem.menu = menu
                statusItem.button?.performClick(nil)
                statusItem.menu = nil
                
            }
            
            
        }
        
    }
    @IBAction func playPauseMenuItem(_ sender: Any) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "playPause"), object: nil)
        
    }
    
    @IBAction func nextTrackMenuItem(_ sender: Any) {
        
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "nextTrack"), object: nil)
    }
    
    
    @IBAction func previousTrackMenuItem(_ sender: Any) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "previousTrack"), object: nil)
    }
    
    @IBAction func searchMenuItem(_ sender: Any) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "search"), object: nil)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    @objc func aboutMenu()
    {
        aboutView?.showWindow(self)
        aboutView?.window?.makeKeyAndOrderFront(self)
        aboutView?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func issues()
    {
        let url = URL(string: "https://github.com/nbolar/PlayStatus/issues")!
        NSWorkspace.shared.open(url)
    }
    
    @objc func quitApp()
    {
        NSApp.terminate(self)
        
    }
    
    @objc func clearTimer(){
        timer?.invalidate()
        timer = nil
    }
    
    
    
    @objc func getSongName()
    {
        
        loadStatusItem()
        
        NSAppleScript.go(code: NSAppleScript.musicApp(), completionHandler: {_,out,_ in
            if out?.stringValue == "Spotify"{
                iconName = "spotify"
                
            }
            else if out?.stringValue == itunesMusicName{
                iconName = "itunes"
            }
            activeMusicApp = out?.stringValue ?? ""
            
            getNowPlayingSong()
        })
        
        
    }
    
    func getNowPlayingSong(){
        
        let check = MusicController.shared.checkPlayerStatus()
        var statutsItemTitle: String! = ""
        if check == 1 {
            NSAppleScript.go(code: NSAppleScript.songName(), completionHandler: {_,out,_ in
                songName = out?.stringValue ?? ""
                currentSongName = songName
                
                ///Ignore Parenthetical
                if UserDefaults.standard.bool(forKey: "parenthesis") == true{
                    songName = songName.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
                }else{
                    songName = out?.stringValue ?? ""
                }
                
                
            })
            NSAppleScript.go(code: NSAppleScript.songArtist(), completionHandler: {_,out,_ in
                artistName = out?.stringValue ?? ""
                currentSongArtist = artistName
                
            })
            NSAppleScript.go(code: NSAppleScript.albumName(), completionHandler: {_,out,_ in
                currentAlbumName = out?.stringValue ?? ""
                
            })
            statutsItemTitle = musicBarTitle()
        }
        else{
            statutsItemTitle = " "
        }
        
        
        
        
        if lastStatusTitle != statutsItemTitle && statutsItemTitle.count > 0{
            
            if statutsItemTitle != "  - "{
                updateTitle(newTitle: statutsItemTitle)
            }else{
                updateTitle(newTitle: " ")
            }
        }
    }
    
    
    func scrollableTitleChanged(scrollableLength: CGFloat){
        let statutsItemTitle = musicBarTitle()
        if scrollableLength != -1.0
        {
            Constants.statusItemLength = scrollableLength
        }
        
        if statutsItemTitle != "  - "{
            updateTitle(newTitle: statutsItemTitle)
        }else{
            updateTitle(newTitle: " ")
        }
        
    }
    
    func musicBarTitle()->String{
        switch UserDefaults.standard.integer(forKey: "options") {
        case 0:
            return " \(artistName ?? "")"
        case 1:
            return " \(songName ?? "")"
        case 2:
            return " \(artistName ?? "") - \(songName ?? "")"
        case 3:
            return " "
        default:
            return " \(artistName ?? "") - \(songName ?? "")"
        }
    }
    
    
    @objc func displayPopUp(status: NSStatusItem) {
        
        let rectWindow = status.button?.window?.convertToScreen((status.button?.frame)!)
        let menubarHeight = rectWindow?.height ?? 22
        let height = musicController?.window?.frame.height ?? 300
        let xOffset = ((musicController?.window?.contentView?.frame.midX)! - (status.button?.frame.midX)!)
        let x = (rectWindow?.origin.x)! - xOffset
        xWidth = x
        let y = (rectWindow?.origin.y)!
        yHeight = y-height+menubarHeight - 42
        musicController?.window?.setFrameOrigin(NSPoint(x: x, y: y+menubarHeight-height))
        musicController?.showWindow(self)
        NSRunningApplication.current.activate(options: NSApplication.ActivationOptions.activateIgnoringOtherApps)
        
    }
    
    
    
    
    // MARK: - Private methods
    
    @objc private func loadSubviews() {
        guard let contentView = contentView else { return }
        
        contentView.addSubview(scrollingStatusItemView)
        NSLayoutConstraint.activate([
            scrollingStatusItemView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollingStatusItemView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            scrollingStatusItemView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollingStatusItemView.rightAnchor.constraint(equalTo: contentView.rightAnchor)])
    }
    
    
    private func updateTitle(newTitle: String) {
        
        if UserDefaults.standard.bool(forKey: "scrollable") == false {
            loadStatusItem()
            scrollingStatusItemView.removeFromSuperview()
            newStatusItem.button?.title = newTitle
            currentTrack = newTitle
            newStatusItem.button?.image = NSImage(named: "\(iconName!)")
            newStatusItem.button?.imagePosition = .imageLeft
            
            
        }else{
            loadStatusItem()
            loadSubviews()
            currentTrack = newTitle
            lastStatusTitle = newTitle
            scrollingStatusItemView.icon = NSImage(named: "\(iconName!)")
            scrollingStatusItemView.text = newTitle
            if newTitle.count == 0 && statusItem.button != nil {
                statusItem.length = scrollingStatusItemView.hasImage ? Constants.statusItemLength : 0
            }
        }
        
        
    }
    @objc func wakeUpListener(){
        
        timer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(getSongName), userInfo: nil, repeats: true)
        timer?.tolerance = 0.3
        
    }
    @objc func sleepListener(){
        
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    
}
