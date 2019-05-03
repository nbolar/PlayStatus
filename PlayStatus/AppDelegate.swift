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

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var songName: String!
    var artistName: String!
    var out: NSAppleEventDescriptor?
    lazy var aboutView: NSWindowController? = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "aboutWindowController") as? NSWindowController
    
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

        statusItem.button?.image = NSImage(named: "icon_20")
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.sendAction(on: [NSEvent.EventTypeMask.leftMouseUp, NSEvent.EventTypeMask.rightMouseUp])
        statusItem.button?.action = #selector(self.togglePopover(_:))
        _ = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(getSongName), userInfo: nil, repeats: true)


    }
    @objc func togglePopover(_ sender: AnyObject?) {
        let event = NSApp.currentEvent!
        
        if event.type == NSEvent.EventType.leftMouseUp
        {
            displayPopUp()
        }else if event.type == NSEvent.EventType.rightMouseUp{
            
            var appVersion: String? {
                return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            }
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "PlayStatus version \(appVersion ?? "")", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "About", action: #selector(aboutMenu), keyEquivalent: "")
            menu.addItem(NSMenuItem(title: "Quit PlayStatus", action: #selector(self.quitApp), keyEquivalent: "q"))
            
//            statusItem.menu = menu
            statusItem.popUpMenu(menu)

            
//            statusItem.menu = nil
            
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
        if songName != ""
        {
            currentSongName = songName
            currentSongArtist = artistName
            statusItem.button?.title = "\(artistName!) - \(songName!)"
            
        }else
        {
            statusItem.button?.title = ""
        }
        
    }
    
    
    
    @objc func displayPopUp() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let vc =  storyboard.instantiateController(withIdentifier: "MusicVC") as? NSViewController else { return }
        let popoverView = NSPopover()
        popoverView.contentViewController = vc
        popoverView.behavior = .transient
        popoverView.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
        
    }


}

