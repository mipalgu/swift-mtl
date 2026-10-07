import Foundation

/// Keep fixture writes atomic on native hosts; WASI has no atomic replacement.
let testWritesAtomically: Bool = {
    #if os(WASI)
    false
    #else
    true
    #endif
}()
