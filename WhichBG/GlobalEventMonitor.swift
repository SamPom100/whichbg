//
//  GlobalEventMonitor.swift
//  WhichBG
//
//  Created by Utkarsh Upadhyay on 8/4/15.
//  Copyright (c) 2015 Utkarsh Upadhyay. All rights reserved.
//

import Cocoa

open class GlobalEventMonitor {
    fileprivate var monitor: Any?
    fileprivate let mask: NSEvent.EventTypeMask
    fileprivate let handler: (NSEvent?) -> Void
    
    public init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    open func start() {
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        }
    }
    
    open func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
