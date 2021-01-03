//
//  PreferencesTabVC.swift
//  PlayStatus
//
//  Created by Nikhil Bolar on 12/22/20.
//  Copyright © 2020 Nikhil Bolar. All rights reserved.
//

import Cocoa

class PreferencesTabVC: NSTabViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    private lazy var tabViewSizes: [NSTabViewItem: NSSize] = [:]
    
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let tabViewItem = tabViewItem {
//            view.window?.title = tabViewItem.label
            resizeWindowToFit(tabViewItem: tabViewItem)
        }
    }
    override func viewWillAppear() {
        let theTabView = self.tabView
        theTabView.selectTabViewItem(at: 0)
    }
    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, willSelect: tabViewItem)
        // Cache the size of the tab view.
        
        preferredContentSize = (tabViewItem?.view?.frame.size)!
        if let tabViewItem = tabViewItem, let size = tabViewItem.view?.frame.size {
            tabViewSizes[tabViewItem] = size
        }
    }
    /// Resizes the window so that it fits the content of the tab.
    private func resizeWindowToFit(tabViewItem: NSTabViewItem) {
        guard let size = tabViewSizes[tabViewItem], let window = view.window else {
            return
        }
        let contentRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let contentFrame = window.frameRect(forContentRect: contentRect)
        let toolbarHeight = window.frame.size.height - contentFrame.size.height
        let newOrigin = NSPoint(x: window.frame.origin.x, y: window.frame.origin.y + toolbarHeight)
        let newFrame = NSRect(origin: newOrigin, size: contentFrame.size)
        window.setFrame(newFrame, display: true, animate: true)
    }
    
}
