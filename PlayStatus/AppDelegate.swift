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

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

//    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var songName: String!
    var artistName: String!
    var out: NSAppleEventDescriptor?
    private var lastStatusTitle: String = ""
    let popoverView = NSPopover()
    lazy var aboutView: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "aboutWindowController") as? NSWindowController
    
    private enum Constants {
        static let statusItemIconLength: CGFloat = 30
        static let statusItemLength: CGFloat = 250
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
    
    let currentTrackNameScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
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
    let currentTrackArtistScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
//        statusItem.length = 250
//        statusItem.button?.image = NSImage(named: "icon_20")
//        statusItem.button?.imagePosition = .imageLeft
        loadSubviews()
        statusItem.button?.sendAction(on: [NSEvent.EventTypeMask.leftMouseUp, NSEvent.EventTypeMask.rightMouseUp])
        statusItem.button?.action = #selector(self.togglePopover(_:))
        _ = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(getSongName), userInfo: nil, repeats: true)


    }
    @objc func togglePopover(_ sender: AnyObject?) {
        let event = NSApp.currentEvent!
        
        if event.type == NSEvent.EventType.leftMouseUp
        {
            if popoverView.isShown
            {
                popoverView.close()
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
        if let scriptObject = NSAppleScript(source: currentTrackNameScpt) {
            var errorDict: NSDictionary? = nil
            out = scriptObject.executeAndReturnError(&errorDict)
            songName = out?.stringValue ?? ""
            

        }
        if let scriptObject = NSAppleScript(source: currentTrackArtistScpt) {
            var errorDict: NSDictionary? = nil
            out = scriptObject.executeAndReturnError(&errorDict)
            artistName = out?.stringValue ?? ""

        }
        
        let statutsItemTitle = "\(artistName!) - \(songName!)"
        
        if lastStatusTitle != statutsItemTitle {
            updateTitle(newTitle: statutsItemTitle)
        }
        
        currentSongName = songName
        currentSongArtist = artistName
        
        
//        if songName != ""
//        {

////            scrollingStatusItemView.text = "\(artistName!) - \(songName!)"
//
//            updateTitle(newTitle: "\(artistName!) - \(songName!)")
//
//
//
//        }else
//        {
//            statusItem.button?.title = ""
////            updateTitle(newTitle: "")
//        }
        
    }
    
    
    
    @objc func displayPopUp() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let vc =  storyboard.instantiateController(withIdentifier: "MusicVC") as? NSViewController else { return }
        
        popoverView.contentViewController = vc
        popoverView.behavior = .transient
        popoverView.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
        
    }
    
    
    
    // MARK: - Private methods
    
    private func loadSubviews() {
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

        
        if newTitle.count == 0 && statusItem.button != nil {
            statusItem.length = scrollingStatusItemView.hasImage ? Constants.statusItemLength : 0
        }
    }
    
    


}

