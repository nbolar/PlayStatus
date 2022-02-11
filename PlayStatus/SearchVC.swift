//
//  SearchVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 6/26/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa

class SearchVC: NSViewController {
    var itunesMusicName: String!
    var segmentedButtonValue: Int = 0
    
    @IBOutlet weak var searchTextField: NSTextField!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        view.wantsLayer = true
        view.layer?.cornerRadius = 5
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.borderColor = NSColor.controlDarkShadowColor.cgColor
        view.layer?.borderWidth = 1
        searchTextField.wantsLayer = true
        searchTextField.layer?.backgroundColor = NSColor.clear.cgColor
        searchTextField.textColor = NSColor.white
        searchTextField.drawsBackground = false
        if #available(OSX 10.15, *){
            itunesMusicName = "Music"
        }else{
            itunesMusicName = "iTunes"
        }
        
    }
    
    override func viewDidAppear() {
        
        searchTextField.refusesFirstResponder = true
        searchTextField.placeholderString = "Search to play a song"
        searchTextField.placeHolderColor = .lightGray
    }
    
    
    @IBAction func segmentedButtonClicked(_ sender: NSSegmentedControl) {
        segmentedButtonValue = sender.selectedSegment
        searchTextField.placeholderString = "Search to play a song"
    }
    
    @IBAction func searchSong(_ sender: Any) {
        
        if segmentedButtonValue == 0 {
            let currentDurationScpt = """
            tell application "\(itunesMusicName!)"
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
        else{
            let currentDurationScpt2 = """
        tell application "\(itunesMusicName!)"
            activate
        end tell
        
        tell application "System Events"
            tell process "\(itunesMusicName!)"
                keystroke "f" using command down
                keystroke "\(searchTextField.stringValue)"
                delay 0.1
                key code 36
            end tell
        end tell
        """
            
            searchTextField.placeholderString = "Search to play a song"
            if let scriptObject = NSAppleScript(source: currentDurationScpt2) {
                scriptObject.executeAndReturnError(nil)
            }
            searchTextField.stringValue = ""
            
        }
        
    }
}
extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}
