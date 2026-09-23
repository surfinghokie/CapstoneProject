//
//  Item.swift
//  HokieBike
//
//  Created by John  Hewitt II  on 9/22/26.
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
