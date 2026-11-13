import AVFoundation

// The iOS audio session: activation before playing, interruptions and route changes.
extension AudioPlayer {
    /// Prepares the shared audio session for playback. Returns false if the system refuses to activate it.
    func activateAudioSession() -> Bool {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // The ambient categories can't play in the background or with the silent switch on. Any other category
            // was chosen by the app, so leave it alone.
            if session.category == .ambient || session.category == .soloAmbient {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true)
        } catch {
            return false
        }
        #endif
        return true
    }

    func observeAudioSession() {
        #if os(iOS)
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        audioSessionObservers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
                self?.audioSessionInterrupted(notification)
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] notification in
                self?.audioSessionRouteChanged(notification)
            },
        ]
        #endif
    }

    #if os(iOS)
    private func audioSessionInterrupted(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            if playing {
                resumeAfterInterruption = true
                pauseForSystem()
            }
        case .ended:
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            let resume = resumeAfterInterruption && shouldResume
            resumeAfterInterruption = false
            if resume {
                resumeForSystem()
            }
        @unknown default:
            break
        }
    }

    private func audioSessionRouteChanged(_ notification: Notification) {
        guard playing,
              let info = notification.userInfo,
              let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable,
              let previousRoute = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        else { return }
        // Headphones were unplugged or a Bluetooth device went away: don't let the audio jump to the speaker.
        let wasPrivate = previousRoute.outputs.contains {
            $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
        }
        if wasPrivate {
            resumeAfterInterruption = false
            pauseForSystem()
        }
    }

    /// Pauses because the system asked for it. Dart owns the `playing` state, so it is told as well.
    private func pauseForSystem() {
        pause()
        dataEvents.sendEvent(["playing": false])
    }

    private func resumeForSystem() {
        guard !playing, let player, !handleAudioSessionActivation || activateAudioSession() else { return }
        playing = true
        player.rate = speed
        updatePosition()
        dataEvents.sendEvent(["playing": true])
    }
    #endif
}
