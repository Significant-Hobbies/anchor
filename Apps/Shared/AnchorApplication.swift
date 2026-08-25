#if !os(watchOS)
import AnchorUI

/// Build configuration is app-target state, so this tiny shared factory keeps
/// DebugLocal persistence behavior identical without duplicating app worlds.
@MainActor
func makeAnchorAppWorld() -> AnchorAppWorld {
    #if ANCHOR_LOCAL_ONLY
    AnchorAppWorld(persistenceMode: .localOnly)
    #else
    AnchorAppWorld(persistenceMode: .automatic)
    #endif
}
#endif
