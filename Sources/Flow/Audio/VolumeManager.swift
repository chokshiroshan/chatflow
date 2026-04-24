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

    /// Volume level before we muted — saved as backup for restore.
    private var savedVolume: Float32? = nil

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

        // Save current volume as backup for restore
        savedVolume = getDeviceVolume(deviceID: deviceID)

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
    /// before recording started. Adds a short delay to let the audio
    /// codec stabilize (AirPods/BT devices need this).
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

        // Delay unmute by 300ms to let codec stabilize (WisprFlow pattern)
        let deviceID = mutedDeviceID
        let volumeBeforeMute = savedVolume
        isCurrentlyMuted = false
        wasPreviouslyMuted = false
        mutedDeviceID = nil
        savedVolume = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            var restored = false

            if let deviceID = deviceID {
                restored = self.setMuteState(muted: false, deviceID: deviceID)
            }

            if !restored, let fallbackID = self.getDefaultOutputDeviceID() {
                restored = self.setMuteState(muted: false, deviceID: fallbackID)
            }

            // Check if volume got zeroed out — restore if we have a saved value
            if let currentDevice = deviceID ?? self.getDefaultOutputDeviceID() {
                let currentVol = self.getDeviceVolume(deviceID: currentDevice)
                if let saved = volumeBeforeMute, saved > 0, (currentVol ?? 0) < 0.01 {
                    print("[VolumeManager] Volume dropped to zero — restoring to \(saved)")
                    self.setDeviceVolume(volume: saved, deviceID: currentDevice)
                    restored = true
                }
            }

            if restored {
                print("[VolumeManager] Restored audio")
            } else {
                print("[VolumeManager] Could not restore audio — user may need to unmute manually")
            }
        }
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

        // Check if the property is accessible by trying to read it
        var currentMute: UInt32 = 0
        var currentSize = UInt32(MemoryLayout<UInt32>.size)
        let propInfoStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &currentSize,
            &currentMute
        )
        guard propInfoStatus == noErr else {
            print("[VolumeManager] Mute property not accessible for device \(deviceID)")
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

    // MARK: - Volume Helpers

    /// Get the scalar volume (0.0 - 1.0) of an output device.
    private func getDeviceVolume(deviceID: AudioDeviceID) -> Float32? {
        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Try virtual main volume first (works for aggregate/BT devices)
        var status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)

        if status != noErr {
            // Fallback to standard volume
            address.mSelector = kAudioDevicePropertyVolumeScalar
            status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
        }

        return status == noErr ? volume : nil
    }

    /// Set the scalar volume (0.0 - 1.0) of an output device.
    private func setDeviceVolume(volume: Float32, deviceID: AudioDeviceID) -> Bool {
        var volume = volume
        let dataSize = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &volume)

        if status != noErr {
            address.mSelector = kAudioDevicePropertyVolumeScalar
            status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &volume)
        }

        if status == noErr {
            print("[VolumeManager] Set volume to \(volume) on device \(deviceID)")
        } else {
            print("[VolumeManager] Failed to set volume — error \(status)")
        }
        return status == noErr
    }
}
