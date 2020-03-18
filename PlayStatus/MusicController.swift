//
//  MusicController.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 3/12/20.
//  Copyright © 2020 Nikhil Bolar. All rights reserved.
//

import Foundation
import AppKit

class MusicController{
    static let shared = MusicController()
    var check = Int()
    var trackDurationTime = String()
    var endTimeValue = String()
    var musicAppName = String()
    
    func checkPlayerStatus() -> Int{
        NSAppleScript.go(code: NSAppleScript.checkStatus(), completionHandler: {_,out,_ in
            let status = out?.stringValue ?? ""
            
            if status == "playing"
            {
                check = 1
                
            }else if status == "not playing"
            {
                check = 2
                
            }
        })
        
        return check
    }
    
    func trackDuration() ->Double{
        NSAppleScript.go(code: NSAppleScript.trackDuration(), completionHandler: {_,out,_ in
            trackDurationTime = out?.stringValue ?? ""
        })
        
        return Double(trackDurationTime) ?? 0
    }
    
    func endTime() -> String{
        NSAppleScript.go(code: NSAppleScript.totalDuration(), completionHandler: {_,out,_ in
            endTimeValue = out?.stringValue ?? ""
        })
        return endTimeValue
    }
    
    func sliderChanged(musicSlider: Double){
        NSAppleScript.go(code: NSAppleScript.scrubTrack(position: musicSlider), completionHandler: {_,_,_ in })
    }
    func musicApp()->String{
        NSAppleScript.go(code: NSAppleScript.musicApp(), completionHandler: {_,out,_ in
            musicAppName = out?.stringValue ?? ""
        })
        return musicAppName
    }
    
}
