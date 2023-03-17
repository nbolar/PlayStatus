//
//  HotKeysVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 12/22/20.
//  Copyright © 2020 Nikhil Bolar. All rights reserved.
//

import Cocoa
import KeyboardShortcuts

class HotKeysVC: NSViewController {

    @IBOutlet weak var playPauseRecorderView: NSView!
    @IBOutlet weak var nextTrackRecorderView: NSView!
    @IBOutlet weak var prevTrackRecorderView: NSView!
    @IBOutlet weak var playerVolUpView: NSView!
    @IBOutlet weak var playerVolDownView: NSView!
    @IBOutlet weak var systemVolUpView: NSView!
    @IBOutlet weak var systemVolDownView: NSView!
    @IBOutlet weak var globalSearchView: NSView!
    private let playPausehotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .playPause)
    private let nextTrackhotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .nextTrack)
    private let prevTrackhotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .prevTrack)
    private let playerVolUphotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .playerVolUp)
    private let playerVolDownhotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .playerVolDown)
    private let systemVolUphotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .systemVolUp)
    private let systemVolDownhotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .systemVolDown)
    private let globalSearchhotkeyRecorder = KeyboardShortcuts.RecorderCocoa(for: .globalSearch)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        playPauseRecorderView.addSubview(playPausehotkeyRecorder)
        nextTrackRecorderView.addSubview(nextTrackhotkeyRecorder)
        prevTrackRecorderView.addSubview(prevTrackhotkeyRecorder)
        playerVolUpView.addSubview(playerVolUphotkeyRecorder)
        playerVolDownView.addSubview(playerVolDownhotkeyRecorder)
        systemVolUpView.addSubview(systemVolUphotkeyRecorder)
        systemVolDownView.addSubview(systemVolDownhotkeyRecorder)
        globalSearchView.addSubview(globalSearchhotkeyRecorder)
        
    }
    
    override func viewWillAppear() {
        
        self.preferredContentSize = NSMakeSize(self.view.frame.size.width, self.view.frame.size.height)
    }

    
}
extension KeyboardShortcuts.Name{
    static let playPause = Self("playPause")
    static let nextTrack = Self("nextTrack")
    static let prevTrack = Self("prevTrack")
    static let playerVolUp = Self("playerVolUp")
    static let playerVolDown = Self("playerVolDown")
    static let systemVolUp = Self("systemVolUp")
    static let systemVolDown = Self("systemVolDown")
    static let globalSearch = Self("globalSearch")
}
