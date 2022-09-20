//
//  SettingsVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 1/1/20.
//  Copyright © 2020 Nikhil Bolar. All rights reserved.
//

import Cocoa
import Sparkle
import LaunchAtLogin


class SettingsVC: NSViewController {
    
    @IBOutlet weak var login: NSButton!
    @IBOutlet weak var updateButton: NSButton!
    @IBOutlet weak var versionText: NSTextField!
    @IBOutlet weak var artistButton: NSButton!
    @IBOutlet weak var songButton: NSButton!
    @IBOutlet weak var artistSongButton: NSButton!
    @IBOutlet weak var logoButton: NSButton!
    @IBOutlet weak var scrollableTextButton: NSButton!
    @IBOutlet weak var spotifyButton: NSButton!
    @IBOutlet weak var appleMusicButton: NSButton!
    @IBOutlet weak var ignoreParensButton: NSButton!
    @IBOutlet weak var restartAppButton: NSButton!
    @IBOutlet weak var slideTitleButton: NSButton!
    @IBOutlet weak var textLengthField: NSTextField!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        // Do view setup here.
        //        self.view.wantsLayer = true
        restartAppButton.isHidden = true
        //        self.view.layer?.backgroundColor = .clear
        let array = [artistButton, songButton, artistSongButton, logoButton]
        let appArray = [spotifyButton, appleMusicButton]
        
        slideTitleButton.state = UserDefaults.standard.bool(forKey: "slideTitle") ? .on :.off
        
        
        if UserDefaults.standard.object(forKey: "options") == nil{
            UserDefaults.standard.set(2, forKey:"options")
            artistSongButton.state = .on
        }else{
            let options = UserDefaults.standard.integer(forKey: "options")
            let name = array[options]
            name?.state = .on
        }
        if UserDefaults.standard.object(forKey: "musicApp") == nil{
            UserDefaults.standard.set(1, forKey: "musicApp")
            appleMusicButton.state = .on
        }else{
            let options = UserDefaults.standard.integer(forKey: "musicApp")
            let name = appArray[options]
            name?.state = .on
        }
        
        if UserDefaults.standard.object(forKey: "scrollableLength") == nil{
            UserDefaults.standard.set("300", forKey: "scrollableLength")
            textLengthField.placeholderString = "300"
        }else{
            let options = UserDefaults.standard.object(forKey: "scrollableLength")
            textLengthField.placeholderString = "\(options ?? "300")"
        }
        
        if UserDefaults.standard.object(forKey: "scrollable") == nil{
            scrollableTextButton.state = .on
            textLengthField.isHidden  = false
        }else if UserDefaults.standard.bool(forKey: "scrollable") == false {
            scrollableTextButton.state = .off
        }else{
            textLengthField.isHidden  = false
            scrollableTextButton.state = .on
        }
        
        if UserDefaults.standard.object(forKey: "parenthesis") == nil{
            ignoreParensButton.state = .off
        }else if UserDefaults.standard.bool(forKey: "parenthesis") == false {
            ignoreParensButton.state = .off
        }else{
            ignoreParensButton.state = .on
            textLengthField.isHidden  = false
        }
        
        updateButton.isHidden = false
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        if let info = Bundle.main.infoDictionary {
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            versionText.stringValue = "Version \(version)"
            versionText.textColor = .lightGray
        }
    }
    override func viewWillAppear() {
        self.preferredContentSize = NSMakeSize(self.view.frame.size.width, self.view.frame.size.height)
    }
    
    
    @IBAction func launchButtonClicked(_ sender: Any) {
        if login.state == .on {
            LaunchAtLogin.isEnabled = true
        }else{
            LaunchAtLogin.isEnabled = false
        }
        
    }
    
    @IBAction func updateButtonClicked(_ sender: Any) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        updateButton.target = appDelegate.updaterController
        updateButton.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        
        
    }
    
    @IBAction func radioButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(sender.tag, forKey: "options")
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        
    }
    @IBAction func scrollableButtonClicked(_ sender: Any) {
        UserDefaults.standard.set(scrollableTextButton.state, forKey: "scrollable")
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.scrollableTitleChanged(scrollableLength: -1.0)
        restartAppButton.isHidden = false
        textLengthField.isHidden = false
        
    }
    @IBAction func scrollableTextLengthChanged(_ sender: NSTextField) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        if let n = NumberFormatter().number(from: textLengthField.stringValue) {
            let value = CGFloat(truncating: n)
            appDelegate.scrollableTitleChanged(scrollableLength: abs(value))
            UserDefaults.standard.set(textLengthField.stringValue, forKey: "scrollableLength")
        }
        
    }
    
    @IBAction func musicPlayerClicked(_ sender: NSButton) {
        UserDefaults.standard.set(sender.tag, forKey: "musicApp")
        if sender.tag == 0 {
            iconName = "spotify"
        }else{
            iconName = "itunes"
        }
        
    }
    @IBAction func ignoreParensButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state, forKey: "parenthesis")
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        
    }
    
    @IBAction func restartAppButtonClicked(_ sender: Any) {
        NSAppleScript.go(code: NSAppleScript.restartApp(), completionHandler: {_,out,_ in})
    }
    @IBAction func slideTitleButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state, forKey: "slideTitle")
    }
}


