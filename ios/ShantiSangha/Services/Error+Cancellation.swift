import Foundation

extension Error {
    /// True if this error represents a cancelled Task or URLSession request,
    /// which happens routinely when SwiftUI views tear down mid-fetch. These
    /// are not real failures and should not be shown to the user or logged
    /// as errors.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
