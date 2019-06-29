//
//  SearchVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 6/26/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa

class SearchVC: NSViewController {

    @IBOutlet weak var searchTextField: NSTextField!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.borderColor = .black
        view.layer?.borderWidth = 1
        searchTextField.wantsLayer = true
        searchTextField.layer?.backgroundColor = CGColor.clear
        searchTextField.layer?.borderWidth = 1
        searchTextField.layer?.borderColor = .black
        searchTextField.textColor = NSColor.white
        searchTextField.drawsBackground = false
        searchTextField.resignFirstResponder()
        
    }
    
    override func viewDidAppear() {
        searchTextField.placeholderString = "Search to play a song from your iTunes library"
    }


    
    @IBAction func searchSong(_ sender: Any) {
        let currentDurationScpt = """
        tell application "iTunes"
        set search_results to (search library playlist 1 for "\(searchTextField.stringValue)")
        repeat with t in search_results
        play t
        end repeat
        end tell
        """
        
        
        if let scriptObject = NSAppleScript(source: currentDurationScpt) {
            scriptObject.executeAndReturnError(nil)
        }
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "loadAlbum"), object: nil)
        searchTextField.placeholderString = "Playing \(currentSongArtist ?? "") - \(currentSongName ?? "...")"
        searchTextField.placeHolderColor = .init(white: 1.0, alpha: 0.6)
        searchTextField.stringValue = ""
        
    }
}
