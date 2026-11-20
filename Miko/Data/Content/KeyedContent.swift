import Foundation

/// Content entities that carry a stable string key.
protocol KeyedContent: AnyObject {
    var key: String { get }
}
