//
//  DesktopPictureViewController.swift
//  WhichBG
//
//  Created by Utkarsh Upadhyay on 8/3/15.
//  Copyright (c) 2015 Utkarsh Upadhyay. All rights reserved.
//

import Cocoa
import Foundation

class DesktopPictureViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    
    var errorString: String?
    var wallpaperPaths: [String] = []
    
    private var scrollView: NSScrollView?
    private var collectionView: NSCollectionView?
    private var errorLabelView: NSTextField?
    
    @objc func exitAction(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
    
    @objc func helpAction(_ sender: Any) {
        if let url = URL(string: "https://github.com/SamPom100/whichbg") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func refreshAction(_ sender: Any) {
        loadWallpapers()
    }
    
    override func loadView() {
        let popoverWidth: CGFloat = 440
        let popoverHeight: CGFloat = 520
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: popoverWidth, height: popoverHeight))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 36, width: popoverWidth, height: popoverHeight - 36))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let flowLayout = NSCollectionViewFlowLayout()
        let cardWidth = popoverWidth - 24
        flowLayout.itemSize = NSSize(width: cardWidth, height: round(cardWidth * (9.0 / 16.0)))
        flowLayout.minimumInteritemSpacing = 12
        flowLayout.minimumLineSpacing = 14
        flowLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        
        let cv = NSCollectionView(frame: scrollView.bounds)
        cv.collectionViewLayout = flowLayout
        cv.dataSource = self
        cv.delegate = self
        cv.isSelectable = true
        cv.backgroundColors = [.clear]
        cv.register(WallpaperItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("WallpaperItem"))
        
        scrollView.documentView = cv
        containerView.addSubview(scrollView)
        self.scrollView = scrollView
        self.collectionView = cv
        
        // Bottom bar
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: popoverWidth, height: 36))
        bottomBar.wantsLayer = true
        containerView.addSubview(bottomBar)
        
        let quitButton = NSButton(title: "Quit", target: self, action: #selector(exitAction))
        quitButton.bezelStyle = .rounded
        quitButton.frame = NSRect(x: (popoverWidth - 70) / 2, y: 5, width: 70, height: 26)
        bottomBar.addSubview(quitButton)
        
        let helpButton = NSButton(frame: NSRect(x: popoverWidth - 32, y: 6, width: 24, height: 24))
        helpButton.bezelStyle = .helpButton
        helpButton.title = ""
        helpButton.target = self
        helpButton.action = #selector(helpAction)
        bottomBar.addSubview(helpButton)
        
        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshAction))
        refreshButton.bezelStyle = .inline
        refreshButton.frame = NSRect(x: 10, y: 6, width: 75, height: 24)
        bottomBar.addSubview(refreshButton)
        
        self.view = containerView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWallpaperUpdate),
            name: WallpaperStore.didUpdateNotification,
            object: nil
        )
        
        loadWallpapers()
    }
    
    @objc private func handleWallpaperUpdate() {
        loadWallpapers()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        loadWallpapers()
    }
    
    func loadWallpapers() {
        loadViewIfNeeded()
        let files = WallpaperStore.shared.getWallpapers()
        if files.isEmpty {
            self.wallpaperPaths = []
            showError("No wallpaper files found.")
        } else {
            self.errorLabelView?.removeFromSuperview()
            self.errorLabelView = nil
            self.scrollView?.isHidden = false
            self.wallpaperPaths = files
            self.collectionView?.reloadData()
        }
    }
    
    private func showError(_ message: String) {
        self.scrollView?.isHidden = true
        if errorLabelView == nil {
            let label = NSTextField(labelWithString: message)
            label.alignment = .center
            label.font = NSFont.systemFont(ofSize: 15)
            label.frame = NSRect(x: 20, y: 220, width: 400, height: 40)
            self.view.addSubview(label)
            self.errorLabelView = label
        } else {
            self.errorLabelView?.stringValue = message
        }
    }
    
    // NSCollectionViewDataSource
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return wallpaperPaths.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("WallpaperItem"), for: indexPath)
        if let wallpaperItem = item as? WallpaperItem {
            let path = wallpaperPaths[indexPath.item]
            wallpaperItem.setup(path: path)
        }
        return item
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if let indexPath = indexPaths.first {
            let path = wallpaperPaths[indexPath.item]
            print("Showing wallpaper in Finder: \(path)")
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

class WallpaperItem: NSCollectionViewItem {
    var path: String?
    private var imageLayer: CALayer?
    
    override func loadView() {
        let cardWidth: CGFloat = 416
        let cardHeight: CGFloat = round(cardWidth * (9.0 / 16.0))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 1
        
        let imgLayer = CALayer()
        imgLayer.frame = container.bounds
        imgLayer.contentsGravity = .resizeAspectFill
        imgLayer.masksToBounds = true
        container.layer?.addSublayer(imgLayer)
        self.imageLayer = imgLayer
        
        self.view = container
    }
    
    func setup(path: String) {
        loadViewIfNeeded()
        self.path = path
        self.view.toolTip = (path as NSString).lastPathComponent + "\n" + path
        if let img = NSImage(byReferencingFile: path) {
            self.imageLayer?.contents = img
        }
    }
    
    override var isSelected: Bool {
        didSet {
            self.view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
            self.view.layer?.borderWidth = isSelected ? 3 : 1
            if isSelected, let path = self.path {
                let url = URL(fileURLWithPath: path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
