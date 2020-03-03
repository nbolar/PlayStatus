//
//  TrackDurationCell.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 1/1/20.
//  Copyright © 2020 Nikhil Bolar. All rights reserved.
//

import Cocoa

class TrackDurationCell: NSSliderCell {
    override var knobThickness: CGFloat {
        return knobWidth
    }
    
    let knobWidth: CGFloat = 0.0
    let knobHeight: CGFloat = 0.0
    let knobRadius: CGFloat = 0.0
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    var percentage: CGFloat {
        get {
                return CGFloat((self.doubleValue - self.minValue) / (self.maxValue - self.minValue))
        }
    }
    
    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        var rect = aRect
        rect.size.height = CGFloat(10)
        let barRadius = CGFloat(0)
        let value = CGFloat((self.doubleValue - self.minValue) / (self.maxValue - self.minValue))
        let finalWidth = CGFloat(value * (self.controlView!.frame.size.width - 8))
        var leftRect = rect
        leftRect.size.width = finalWidth
        let bg = NSBezierPath(roundedRect: rect, xRadius: barRadius, yRadius: barRadius)
        NSColor.gray.withAlphaComponent(0.5).setFill()
        bg.fill()
        let active = NSBezierPath(roundedRect: leftRect, xRadius: barRadius, yRadius: barRadius)
        NSColor.white.withAlphaComponent(0.4).setFill()
        active.fill()
    }
    
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.setFill()
        NSColor.white.setStroke()
        
        let rect = NSMakeRect(round(knobRect.origin.x),
                              knobRect.origin.y + 0.5 * (knobRect.height - knobHeight),
                              knobRect.width,
                              knobHeight)
        let path = NSBezierPath(roundedRect: rect, xRadius: knobRadius, yRadius: knobRadius)
        path.fill()
        path.stroke()
    }
    
    override func knobRect(flipped: Bool) -> NSRect {
        let pos = percentage * (self.controlView!.frame.size.width - 8)
        let rect = super.knobRect(flipped: flipped)
        return NSMakeRect(pos, rect.origin.y, knobWidth, rect.height)
    }

}
