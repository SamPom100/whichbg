//
//  AppDelegate.swift
//  WhichBG
//
//  Created by Utkarsh Upadhyay on 6/20/15.
//  Copyright (c) 2015 Utkarsh Upadhyay. All rights reserved.
//

import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusBarItem: NSStatusItem?
    var outsideClickHandler: GlobalEventMonitor?
    let popOver = NSPopover()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Start live OS log streaming and wallpaper cache in background
        WallpaperStore.shared.startListening()
        
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem?.button {
            let statusIconPath = Bundle.main.path(forResource: "StatusIcon", ofType: "png") ?? ""
            if let image = NSImage(named: "StatusIcon") ?? NSImage(contentsOfFile: statusIconPath) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            } else if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "WhichBG")
            } else {
                button.title = "WhichBG"
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        let viewController = DesktopPictureViewController()
        popOver.contentViewController = viewController
        popOver.behavior = .transient
        
        outsideClickHandler = GlobalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, strongSelf.popOver.isShown {
                strongSelf.closePopover(event)
            }
        }
        outsideClickHandler?.start()
    }
    
    func showPopover(_ sender: Any?) {
        if let button = statusBarItem?.button {
            (popOver.contentViewController as? DesktopPictureViewController)?.loadWallpapers()
            popOver.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    func closePopover(_ sender: Any?) {
        popOver.performClose(sender)
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if popOver.isShown {
            closePopover(sender)
            outsideClickHandler?.stop()
        } else {
            showPopover(popOver)
            outsideClickHandler?.start()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("Exiting WhichBG.")
    }
}
