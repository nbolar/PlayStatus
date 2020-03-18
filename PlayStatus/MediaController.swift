//
//  MediaController.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 3/12/20.
//  Copyright © 2020 Nikhil Bolar. All rights reserved.
//

import Cocoa

@NSApplicationMain
class MediaController: NSApplication, NSApplicationDelegate {
    
    override func sendEvent(_ event: NSEvent)
    {
        if  event.type == .systemDefined &&
            event.subtype == .screenChanged
        {
            let keyCode : Int32 = (Int32((event.data1 & 0xFFFF0000) >> 16))
            let keyFlags = (event.data1 & 0x0000FFFF)
            let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA

            self.mediaKeyEvent(withKeyCode: keyCode, andState: keyState)
            return
        }

        super.sendEvent(event)
    }

    private func mediaKeyEvent(withKeyCode keyCode : Int32, andState state : Bool)
    {
        
        switch keyCode
        {
            // Play pressed
            case NX_KEYTYPE_PLAY:
                if state == false
                {
//                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: "loadingSplash"), object: nil)
                }
                break
            // Next
            case NX_KEYTYPE_FAST:
                if state == true
                {
                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: "loadingSplash"), object: nil)
                }
                break

            // Previous
            case NX_KEYTYPE_REWIND:
                if state == true
                {
                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: "loadingSplash"), object: nil)
                }

                break
            default:
                break
        }
    }

}
