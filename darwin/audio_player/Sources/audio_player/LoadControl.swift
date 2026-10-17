import Foundation

final class LoadControl {
    /// In microseconds.
    var preferredForwardBufferDuration: Int64?
    var canUseNetworkResourcesForLiveStreamingWhilePaused = false
    var preferredPeakBitRate: Double?
}
