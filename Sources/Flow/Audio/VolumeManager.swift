import Foundation
import CoreAudio
import AudioToolbox

/// Manages system audio muting during dictation to prevent playback
/// from corrupting microphone input.
///
/// Gracefully degrades — if any CoreAudio call fails, it simply skips
/// the mute/unmute operation rather than crashing.
@MainActor
final class VolumeManager {
    static let shared = VolumeManager()

    // MARK: - Public State

    /// Whether the manager should mute audio when recording starts.
    /// Bound to `FlowConfig.shouldMuteAudio`.
    var shouldMuteAudio: Bool = true

    /// Whether we currently have the system muted (by us).
    private(set) var isCurrentlyMuted: Bool = false

    /// Whether the system was already muted before we touched it.
    private(set) var wasPreviouslyMuted: Bool = false

    // MARK: - Private State

    /// The device ID we muted, so we unmute the same one.
    private var mutedDeviceID: AudioDeviceID? = nil

    private init() {}

    // MARK: - Public API

    /// Mute the default output device before recording starts.
    ///
    /// Records whether the device was already muted so we don't
    /// accidentally unmute something the user muted on purpose.
    func muteForRecording() {
        guard shouldMuteAudio else {
            print("[VolumeManager] Skipping mute — disabled in config")
            return
        }

        guard !isCurrentlyMuted else {
            print("[VolumeManager] Already muted, skipping")
            return
        }

        guard let deviceID = getDefaultOutputDeviceID() else {
            print("[VolumeManager] Could not get default output device — skipping mute")
            return
        }

        // Check current mute state before touching it
        let currentlyMuted = isDeviceMuted(deviceID: deviceID)
        wasPreviouslyMuted = currentlyMuted

        if currentlyMuted {
            print("[VolumeManager] System already muted — nothing to do")
            isCurrentlyMuted = false  // We didn't mute it
            return
        }

        // Attempt to mute
        if setMuteState(muted: true, deviceID: deviceID) {
            mutedDeviceID = deviceID
            isCurrentlyMuted = true
            print("[VolumeManager] Playing dictation start sound and muting")
        } else {
            print("[VolumeManager] Failed to mute output device — skipping")
        }
    }

    /// Restore the previous mute state after recording stops.
    ///
    /// Only unmutes if *we* muted it and the user hadn't already muted
    /// before recording started.
    func restoreAfterRecording() {
        guard isCurrentlyMuted else {
            // Not muted by us — nothing to restore
            return
        }

        guard !wasPreviouslyMuted else {
            print("[VolumeManager] Was previously muted by user — leaving muted")
            isCurrentlyMuted = false
            mutedDeviceID = nil
            return
        }

        // Try to unmute the same device we muted
        if let deviceID = mutedDeviceID {
            if setMuteState(muted: false, deviceID: deviceID) {
                print("[VolumeManager] Restored audio — unmuted")
            } else {
                print("[VolumeManager] Failed to unmute device — user may need to unmute manually")
            }
        } else {
            // Fallback: unmute whatever the current default is
            if let deviceID = getDefaultOutputDeviceID() {
                if setMuteState(muted: false, deviceID: deviceID) {
                    print("[VolumeManager] Restored audio — unmuted (fallback device)")
                }
            }
        }

        isCurrentlyMuted = false
        wasPreviouslyMuted = false
        mutedDeviceID = nil
    }

    // MARK: - CoreAudio Helpers

    /// Get the ID of the default audio output device.
    private func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != 0, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    /// Check whether a given output device is currently muted.
    private func isDeviceMuted(deviceID: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // First check if the property exists (some devices don't support mute)
        var writable: DarwinBoolean = false
        let propStatus = AudioObjectGetPropertyInfo(
            deviceID,
            &address,
            0,
            nil,
            &writable
        )

        guard propStatus == noErr else {
            return false
        }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &muted
        )

        return status == noErr && muted != 0
    }

    /// Set the mute state on a given output device.
    private func setMuteState(muted: Bool, deviceID: AudioDeviceID) -> Bool {
        var muteValue: UInt32 = muted ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if the property is writable
        var writable: DarwinBoolean = false
        let propInfoStatus = AudioObjectGetPropertyInfo(
            deviceID,
            &address,
            0,
            nil,
            &writable
        )

        guard propInfoStatus == noErr, writable.boolValue else {
            print("[VolumeManager] Mute property not writable for device \(deviceID)")
            return false
        }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            dataSize,
            &muteValue
        )

        return status == noErr
    }
}
