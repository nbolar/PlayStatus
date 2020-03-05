//
//  AboutVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 5/3/19.
//  Copyright © 2019 Nikhil Bolar. All rights reserved.
//

import Cocoa

class AboutVC: NSViewController {
    @IBOutlet weak var versionText: NSTextField!
    @IBOutlet weak var descriptionField: NSTextField!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        if let info = Bundle.main.infoDictionary {
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            versionText.stringValue = "Version \(version)"
        }
        
        descriptionField.stringValue = """
    MIT License

    Copyright (c) 2020 Nikhil Bolar

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
    }
    @IBAction func repoClicked(_ sender: NSClickGestureRecognizer) {
        if let url = URL(string: "https://github.com/nbolar/PlayStatus") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @IBAction func iconsClicked(_ sender: Any) {
        if let url = URL(string: "https://icons8.com/") {
            NSWorkspace.shared.open(url)
        }
        
    }
}
