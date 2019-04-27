//
//  AppDelegate.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 4/25/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var songName: String!
    var artistName: String!
    var out: NSAppleEventDescriptor?
    
    let currentTrackNameScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                return name of current track
            else
                return ""
        end if
        end tell
    else
        return ""
    end if
    """
    let currentTrackArtistScpt = """
    if application "iTunes" is running then
        tell application "iTunes"
            if player state is playing then
                return artist of current track
            else
                return ""
        end if
        end tell
    else
        return ""
    end if
    """

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application

        statusItem.button?.image = NSImage(named: "icon_20")
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.action = #selector(self.displayPopUp)
        _ = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(getSongName), userInfo: nil, repeats: true)


    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
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

