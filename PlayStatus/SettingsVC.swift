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
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        updateButton.isHidden = false
        login.state = LoginServiceKit.isExistLoginItems() ? .on : .off
        if let info = Bundle.main.infoDictionary {
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            versionText.stringValue = "Version \(version)"
            versionText.textColor = .lightGray
        }
    }
    
    @IBAction func launchButtonClicked(_ sender: Any) {
        if login.state == .on {
            LoginServiceKit.addLoginItems()
        }else{
            LoginServiceKit.removeLoginItems()
        }
    }
    
    @IBAction func updateButtonClicked(_ sender: Any) {
        let updater = SUUpdater.shared()
        updater?.feedURL = URL(string: "https://s3.us-east-2.amazonaws.com/com.bolar.playstatus/appcast.xml")
        updater?.checkForUpdates(self)
    }
    
}
