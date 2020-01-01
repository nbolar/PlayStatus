//
//  AppDelegate.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 4/25/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa

var currentSongName: String!
var currentSongArtist: String!
var yHeight : CGFloat!
var xWidth : CGFloat!
var itunesMusicName: String! = "iTunes"

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var songName: String!
    var artistName: String!    
    var out: NSAppleEventDescriptor?
    private var lastStatusTitle: String = ""
    let popoverView = NSPopover()
    lazy var aboutView: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "aboutWindowController") as? NSWindowController
    let invisibleWindow = NSWindow(contentRect: NSMakeRect(0, 0, 20, 1), styleMask: .borderless, backing: .buffered, defer: false)
    private var musicController: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "musicViewController") as? NSWindowController


    private enum Constants {
        static let statusItemIconLength: CGFloat = 30
        static let statusItemLength: CGFloat = 200
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
            self.statusItem.length = length
        } else {
            self.statusItem.length = Constants.statusItemLength
        }
    }
    
    private lazy var contentView: NSView? = {
        let view = (statusItem.value(forKey: "window") as? NSWindow)?.contentView
        return view
    }()
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application

        if #available(OSX 10.15, *){
            itunesMusicName = "Music"
        }else{
            itunesMusicName = "iTunes"
        }

        
        statusItem.button?.sendAction(on: [NSEvent.EventTypeMask.leftMouseUp, NSEvent.EventTypeMask.rightMouseUp])
        statusItem.button?.action = #selector(self.togglePopover(_:))
        _ = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(getSongName), userInfo: nil, repeats: true)
        loadSubviews()
        invisibleWindow.backgroundColor = .clear
        invisibleWindow.alphaValue = 0
        
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let vc =  storyboard.instantiateController(withIdentifier: "MusicVC") as? NSViewController else { return }
        musicController?.contentViewController = vc
        musicController?.window?.isOpaque = false
        musicController?.window?.backgroundColor = .clear
        musicController?.window?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))



    }
    



    @objc func togglePopover(_ sender: AnyObject?) {
        let event = NSApp.currentEvent!
        
        if event.type == NSEvent.EventType.leftMouseUp
        {
            if musicController?.window?.isVisible == true
            {
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "close"), object: nil)
                musicController?.close()
            }else{
                displayPopUp()
            }
            
        }else if event.type == NSEvent.EventType.rightMouseUp{
            
            var appVersion: String? {
                return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            }
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "PlayStatus version \(appVersion ?? "")", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "About", action: #selector(aboutMenu), keyEquivalent: "")
            menu.addItem(NSMenuItem(title: "Quit PlayStatus", action: #selector(self.quitApp), keyEquivalent: "q"))

            statusItem.popUpMenu(menu)

            
        }
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
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp()
    {
        NSApp.terminate(self)
        
    }
    
    @objc func getSongName()
    {

        loadSubviews()
        NSAppleScript.go(code: NSAppleScript.songName(), completionHandler: {_,out,_ in
            songName = out?.stringValue ?? ""
            currentSongName = songName
            
        })
        NSAppleScript.go(code: NSAppleScript.songArtist(), completionHandler: {_,out,_ in
            artistName = out?.stringValue ?? ""
            currentSongArtist = artistName
            
        })
        
        let statutsItemTitle = "\(artistName!) - \(songName!)"
        
        if lastStatusTitle != statutsItemTitle && statutsItemTitle.count > 0{
            if statutsItemTitle != " - "{
                updateTitle(newTitle: statutsItemTitle)
            }else{
                updateTitle(newTitle: " ")
            }
        }
        
    }
    
    
    
    @objc func displayPopUp() {

        let rectWindow = statusItem.button?.window?.convertToScreen((statusItem.button?.frame)!)
        let menubarHeight = rectWindow?.height ?? 22
        let height = musicController?.window?.frame.height ?? 300
        let xOffset = ((musicController?.window?.contentView?.frame.midX)! - (statusItem.button?.frame.midX)!)
        let x = (rectWindow?.origin.x)! - xOffset
        xWidth = x
        let y = (rectWindow?.origin.y)!
        yHeight = y-height+menubarHeight - 42
        musicController?.window?.setFrameOrigin(NSPoint(x: x, y: y+menubarHeight-height))
        musicController?.showWindow(self)
        NSRunningApplication.current.activate(options: NSApplication.ActivationOptions.activateIgnoringOtherApps)

        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "loadAlbum"), object: nil)
        
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
        lastStatusTitle = newTitle
        scrollingStatusItemView.icon = NSImage(named: "icon_20")
        scrollingStatusItemView.text = newTitle
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "loadAlbum"), object: nil)
        

        
        if newTitle.count == 0 && statusItem.button != nil {
            statusItem.length = scrollingStatusItemView.hasImage ? Constants.statusItemLength : 0
        }
    }
    
    


}

