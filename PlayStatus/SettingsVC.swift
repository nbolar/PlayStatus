//
//  SettingsVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 1/1/20.
//  Copyright © 2020 Nikhil Bolar. All rights reserved.
//

import Cocoa
import LoginServiceKit
import Sparkle

class SettingsVC: NSViewController {

    @IBOutlet weak var login: NSButton!
    @IBOutlet weak var updateButton: NSButton!
    @IBOutlet weak var versionText: NSTextField!
    @IBOutlet weak var artistButton: NSButton!
    @IBOutlet weak var songButton: NSButton!
    @IBOutlet weak var artistSongButton: NSButton!
    @IBOutlet weak var scrollableTextButton: NSButton!
    @IBOutlet weak var spotifyButton: NSButton!
    @IBOutlet weak var appleMusicButton: NSButton!
    @IBOutlet weak var ignoreParensButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = .clear
        let array = [artistButton, songButton, artistSongButton]
        let appArray = [spotifyButton, appleMusicButton]
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

        if UserDefaults.standard.object(forKey: "scrollable") == nil{
            scrollableTextButton.state = .on
        }else if UserDefaults.standard.bool(forKey: "scrollable") == false {
            scrollableTextButton.state = .off
        }else{
            scrollableTextButton.state = .on
        }
        
        if UserDefaults.standard.object(forKey: "parenthesis") == nil{
            ignoreParensButton.state = .off
        }else if UserDefaults.standard.bool(forKey: "parenthesis") == false {
            ignoreParensButton.state = .off
        }else{
            ignoreParensButton.state = .on
        }
        
        updateButton.isHidden = false
        login.state = LoginServiceKit.isExistLoginItems() ? .on : .off
        if let info = Bundle.main.infoDictionary {
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            versionText.stringValue = "Version \(version)"
            versionText.textColor = .lightGray
        }
    }
    override func viewWillAppear() {
        self.view.window?.makeKeyAndOrderFront(self)
    }

    
    @IBAction func launchButtonClicked(_ sender: Any) {
        if login.state == .on {
            LoginServiceKit.addLoginItems()
        }else{
            LoginServiceKit.removeLoginItems()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.dismiss(self)
        }
    }
    
    @IBAction func updateButtonClicked(_ sender: Any) {
        SUUpdater.shared().checkForUpdates(self)
//        let updater = SUUpdater.shared()
//        updater?.feedURL = URL(string: "https://s3.us-east-2.amazonaws.com/com.bolar.playstatus/appcast.xml")
//        updater?.checkForUpdates(self)
        
    }
    
    @IBAction func radioButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(sender.tag, forKey: "options")
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.dismiss(self)
        }
    }
    @IBAction func scrollableButtonClicked(_ sender: Any) {
        UserDefaults.standard.set(scrollableTextButton.state, forKey: "scrollable")
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.scrollableTitleChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.dismiss(self)
        }
    }
    
    @IBAction func musicPlayerClicked(_ sender: NSButton) {
        UserDefaults.standard.set(sender.tag, forKey: "musicApp")
        if sender.tag == 0 {
            iconName = "spotify"
        }else{
            iconName = "itunes"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.dismiss(self)
        }
    }
    @IBAction func ignoreParensButtonClicked(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state, forKey: "parenthesis")
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.getSongName()
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            self.dismiss(self)
        }
    }
    
}
