//
//  Core.swift
//  WhichBG
//
//  Created by Utkarsh Upadhyay on 8/2/15.
//  Copyright (c) 2015 Utkarsh Upadhyay. All rights reserved.
//

import Foundation
import AppKit
import SQLite3

func isDir(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    return (exists && isDir.boolValue)
}

func isFile(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    return (exists && !isDir.boolValue)
}

private func modificationDate(of path: String) -> Date {
    let url = URL(fileURLWithPath: path)
    if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
       let date = values.contentModificationDate {
        return date
    }
    return Date.distantPast
}

class WallpaperStore {
    static let shared = WallpaperStore()
    
    private(set) var recentWallpapers: [String] = []
    private var streamProcess: Process?
    private var isListening = false
    private let lock = NSLock()
    
    static let didUpdateNotification = Notification.Name("WallpaperStoreDidUpdateNotification")
    
    private init() {}
    
    func startListening() {
        guard !isListening else { return }
        isListening = true
        
        // Initial scan in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let initial = self?.performInitialScan(limit: 5) ?? []
            self?.lock.lock()
            self?.recentWallpapers = initial
            self?.lock.unlock()
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: WallpaperStore.didUpdateNotification, object: nil)
            }
            
            // Start background log stream process
            self?.startLogStream()
        }
    }
    
    func getWallpapers() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        if recentWallpapers.isEmpty {
            recentWallpapers = performInitialScan(limit: 5)
        }
        return recentWallpapers
    }
    
    private func startLogStream() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "stream",
            "--predicate",
            "subsystem == \"com.apple.wallpaper\" AND eventMessage contains \"BEGIN - Image cache lookup\"",
            "--info"
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        self.streamProcess = task
        
        do {
            try task.run()
        } catch {
            print("Failed to start log stream: \(error)")
            return
        }
        
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            
            let lines = text.components(separatedBy: .newlines)
            var newPaths = [String]()
            
            for line in lines {
                if line.contains("BEGIN - Image cache lookup - url:") {
                    if let startRange = line.range(of: "url:"),
                       let endRange = line.range(of: ", index") {
                        let rawUrl = String(line[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        let path: String
                        if rawUrl.hasPrefix("file://") {
                            if let url = URL(string: rawUrl.replacingOccurrences(of: " ", with: "%20")) ?? URL(string: rawUrl) {
                                path = url.path
                            } else {
                                path = rawUrl.replacingOccurrences(of: "file://", with: "").removingPercentEncoding ?? rawUrl
                            }
                        } else {
                            path = rawUrl
                        }
                        
                        let cleanPath = path.removingPercentEncoding ?? path
                        if isFile(cleanPath) {
                            newPaths.append(cleanPath)
                        }
                    }
                }
            }
            
            if !newPaths.isEmpty, let self = self {
                self.lock.lock()
                var updated = self.recentWallpapers
                for p in newPaths {
                    updated.removeAll(where: { $0 == p })
                    updated.insert(p, at: 0)
                }
                if updated.count > 5 {
                    updated = Array(updated.prefix(5))
                }
                self.recentWallpapers = updated
                self.lock.unlock()
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: WallpaperStore.didUpdateNotification, object: nil)
                }
            }
        }
    }
    
    private func performInitialScan(limit: Int = 5) -> [String] {
        var result = [String]()
        var seen = Set<String>()
        
        let logPaths = getRecentWallpapersFromOSLog(timeRange: "1d")
        for p in logPaths {
            if !seen.contains(p) {
                seen.insert(p)
                result.append(p)
                if result.count >= limit {
                    return result
                }
            }
        }
        
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                let p = url.path
                if isFile(p) && !seen.contains(p) {
                    seen.insert(p)
                    result.append(p)
                    if result.count >= limit {
                        return result
                    }
                }
            }
        }
        
        if result.count >= limit {
            return Array(result.prefix(limit))
        }
        
        var candidatePaths = Set<String>()
        var relativeFiles = Set<String>()
        
        if let appSupp = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first {
            let indexPlistPath = (appSupp as NSString).appendingPathComponent("com.apple.wallpaper/Store/Index.plist")
            if isFile(indexPlistPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: indexPlistPath)),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                extractPathsFromPlist(plist, candidatePaths: &candidatePaths, relativeFiles: &relativeFiles)
            }
            
            let legacyDbPath = (appSupp as NSString).appendingPathComponent("Dock/desktoppicture.db")
            if isFile(legacyDbPath) {
                extractPathsFromLegacyDB(legacyDbPath, candidatePaths: &candidatePaths, relativeFiles: &relativeFiles)
            }
        }
        
        var finalFiles = Set<String>()
        let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp", "webp", "gif"])
        var folders = Set<String>()
        
        for path in candidatePaths {
            let expanded = (path as NSString).expandingTildeInPath
            if isDir(expanded) {
                folders.insert(expanded)
            } else if isFile(expanded) {
                let ext = (expanded as NSString).pathExtension.lowercased()
                if imageExtensions.contains(ext) {
                    finalFiles.insert(expanded)
                }
            } else {
                relativeFiles.insert(expanded)
            }
        }
        
        for folder in folders {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: folder) {
                for file in contents {
                    let fullPath = (folder as NSString).appendingPathComponent(file)
                    let ext = (file as NSString).pathExtension.lowercased()
                    if imageExtensions.contains(ext) && isFile(fullPath) {
                        finalFiles.insert(fullPath)
                    }
                }
            }
        }
        
        let sortedFiles = Array(finalFiles).sorted { modificationDate(of: $0) > modificationDate(of: $1) }
        for p in sortedFiles {
            if !seen.contains(p) {
                seen.insert(p)
                result.append(p)
                if result.count >= limit {
                    break
                }
            }
        }
        
        return Array(result.prefix(limit))
    }
    
    deinit {
        streamProcess?.terminate()
    }
}

func getRecentWallpapersFromOSLog(timeRange: String = "1d") -> [String] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    task.arguments = [
        "show",
        "--predicate",
        "subsystem == \"com.apple.wallpaper\" AND eventMessage contains \"BEGIN - Image cache lookup\"",
        "--info",
        "--last",
        timeRange
    ]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return []
    }
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    
    var recentPaths = [String]()
    let lines = output.components(separatedBy: .newlines)
    
    for line in lines {
        if line.contains("BEGIN - Image cache lookup - url:") {
            if let startRange = line.range(of: "url:"),
               let endRange = line.range(of: ", index") {
                let rawUrl = String(line[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let path: String
                if rawUrl.hasPrefix("file://") {
                    if let url = URL(string: rawUrl.replacingOccurrences(of: " ", with: "%20")) ?? URL(string: rawUrl) {
                        path = url.path
                    } else {
                        path = rawUrl.replacingOccurrences(of: "file://", with: "").removingPercentEncoding ?? rawUrl
                    }
                } else {
                    path = rawUrl
                }
                
                let cleanPath = path.removingPercentEncoding ?? path
                if isFile(cleanPath) {
                    recentPaths.append(cleanPath)
                }
            }
        }
    }
    
    recentPaths.reverse()
    
    var dedup = [String]()
    var seen = Set<String>()
    for p in recentPaths {
        if !seen.contains(p) {
            seen.insert(p)
            dedup.append(p)
        }
    }
    
    return dedup
}

func getWallpaperPaths(limit: Int = 5) -> [String] {
    return WallpaperStore.shared.getWallpapers()
}

private func extractPathsFromPlist(_ object: Any, candidatePaths: inout Set<String>, relativeFiles: inout Set<String>) {
    if let dict = object as? [String: Any] {
        for (key, value) in dict {
            if key == "relative", let str = value as? String {
                processPathString(str, candidatePaths: &candidatePaths, relativeFiles: &relativeFiles)
            } else if let str = value as? String {
                processPathString(str, candidatePaths: &candidatePaths, relativeFiles: &relativeFiles)
            } else if let data = value as? Data,
                      let subPlist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                extractPathsFromPlist(subPlist, candidatePaths: &candidatePaths, relativeFiles: &relativeFiles)
            } else {
                extractPathsFromPlist(value, candidatePaths: &candidatePaths, relativeFiles: &relativeFiles)
            }
        }
    } else if let array = object as? [Any] {
        for item in array {
            extractPathsFromPlist(item, candidatePaths: &candidatePaths, relativeFiles: &relativeFiles)
        }
    }
}

private func processPathString(_ str: String, candidatePaths: inout Set<String>, relativeFiles: inout Set<String>) {
    if str.hasPrefix("file://") {
        if let url = URL(string: str) {
            candidatePaths.insert(url.path)
        }
    } else if str.hasPrefix("/") || str.hasPrefix("~") {
        candidatePaths.insert(str)
    } else if str.contains(".") {
        relativeFiles.insert(str)
    }
}

private func extractPathsFromLegacyDB(_ dbPath: String, candidatePaths: inout Set<String>, relativeFiles: inout Set<String>) {
    var db: OpaquePointer?
    if sqlite3_open(dbPath, &db) == SQLITE_OK {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT value FROM data", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(statement, 0) {
                    let str = String(cString: cStr)
                    if str.hasPrefix("/") || str.hasPrefix("~") {
                        candidatePaths.insert(str)
                    } else {
                        relativeFiles.insert(str)
                    }
                }
            }
        }
        sqlite3_finalize(statement)
    }
    sqlite3_close(db)
}
