//
//  Item.swift
//  20 Questions
//
//  Created by Steven Richter on 11/11/25.
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
