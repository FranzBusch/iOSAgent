//
//  File.swift
//  
//
//  Created by Christian Menschel on 04.12.19.
//

import Foundation

@objc public extension Instana {
    struct Types {
        public typealias Milliseconds = Int64
        public typealias Seconds = Double
        public typealias Bytes = Int64
        public typealias HTTPSize = HTTPMarker.HTTPSize
    }
}
