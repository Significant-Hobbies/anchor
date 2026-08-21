#if !os(watchOS)
import AnchorCore
import SwiftUI

private struct AnchorPlatformSyncKey: EnvironmentKey {
    static let defaultValue: AnchorPlatformSync? = nil
}

public extension EnvironmentValues {
    var anchorPlatformSync: AnchorPlatformSync? {
        get { self[AnchorPlatformSyncKey.self] }
        set { self[AnchorPlatformSyncKey.self] = newValue }
    }
}
#endif
