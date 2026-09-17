// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct OneThingTask: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var completedAt: Date?

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
