// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class SpacePredictionCache {
    static let shared = SpacePredictionCache()

    private static let predictionTTLMs: UInt64 = 600

    private struct Entry {
        let index: UInt32
        let timestampMs: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var lastCommandMs: UInt64 = 0
    private var lastSpaceCount: UInt32 = 0

    private init() {}

    private static func nowMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }

    func getPrediction(for displayID: String) -> UInt32? {
        guard let entry = entries[displayID] else { return nil }
        let now = Self.nowMs()
        if now >= entry.timestampMs && (now - entry.timestampMs) <= Self.predictionTTLMs {
            return entry.index
        } else {
            entries.removeValue(forKey: displayID)
            return nil
        }
    }

    func setPrediction(for displayID: String, index: UInt32) {
        entries[displayID] = Entry(index: index, timestampMs: Self.nowMs())
    }

    func reset() {
        entries.removeAll()
        lastSpaceCount = 0
        lastCommandMs = 0
    }

    func refreshIfStale(currentInfo: SpaceInfo?) {
        let now = Self.nowMs()
        let idle = (now - lastCommandMs) > Self.predictionTTLMs

        var layoutChanged = false
        if let info = currentInfo {
            layoutChanged = (lastSpaceCount != 0 && info.spaceCount != lastSpaceCount)
            lastSpaceCount = info.spaceCount
        }

        if idle || layoutChanged {
            entries.removeAll()
        }
        lastCommandMs = now
    }
}
