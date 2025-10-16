//
//  CaptureStorage.swift
//  ARKitAndScan
//
//  Created by Codex on 2025/10/16.
//

import Foundation

enum CaptureStorage {
    struct Entry {
        let url: URL
        let name: String
        let createdAt: Date?
    }

    private static let fileManager = FileManager.default
    private static let rootDirectoryName = "ARLocalScans"

    static func rootDirectory() throws -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent(rootDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        }
        try markExcludedFromBackup(at: root)
        return root
    }

    static func makeCaptureDirectory(named name: String) throws -> URL {
        let root = try rootDirectory()
        let directory = root.appendingPathComponent(name, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        try markExcludedFromBackup(at: directory)
        return directory
    }

    static func listCaptures() -> [Entry] {
        var allEntries: [Entry] = []

        if let root = try? rootDirectory() {
            allEntries.append(contentsOf: entries(in: root))
        }

        if let legacy = legacyDirectory() {
            allEntries.append(contentsOf: entries(in: legacy))
        }

        return allEntries
            .sorted { (lhs, rhs) in
                let lhsDate = lhs.createdAt ?? Date.distantPast
                let rhsDate = rhs.createdAt ?? Date.distantPast
                return lhsDate > rhsDate
            }
    }

    private static func entries(in root: URL) -> [Entry] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let createdAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate
            return Entry(url: url, name: url.lastPathComponent, createdAt: createdAt)
        }
    }

    private static func legacyDirectory() -> URL? {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacy = documents.appendingPathComponent("ARScans", isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: legacy.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return legacy
        }
        return nil
    }

    private static func markExcludedFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
