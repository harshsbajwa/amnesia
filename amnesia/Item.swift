//
//  Item.swift
//  amnesia
//
//  Created by Harsh Bajwa on 2025-05-16.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
