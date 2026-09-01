import Foundation
import AVFoundation
import Combine
import AppKit

// MARK: - AudioDevice

struct AudioDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let isDefault: Bool
}

// MARK: - AudioInputService
// Manages microphone device listing and selection.
// Actual audio capture is handled within SpeechRecognitionService.

@MainActor
final class AudioInputService: ObservableObject {

    @Published var availableDevices: [AudioDevice] = []
    @Published var selectedDeviceID: String? = nil
    @Published var micPermissionGranted: Bool = false

    init() {
        refreshDevices()
        checkMicPermission()

        // Listen for device changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesChanged),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesChanged),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    @objc private func devicesChanged() {
        refreshDevices()
    }

    func refreshDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        availableDevices = session.devices.map { device in
            AudioDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == AVCaptureDevice.default(for: .audio)?.uniqueID
            )
        }

        // Keep selection if still available, else default
        if let selected = selectedDeviceID,
           !availableDevices.contains(where: { $0.id == selected }) {
            selectedDeviceID = availableDevices.first(where: { $0.isDefault })?.id
                ?? availableDevices.first?.id
        }
        if selectedDeviceID == nil {
            selectedDeviceID = availableDevices.first(where: { $0.isDefault })?.id
                ?? availableDevices.first?.id
        }
    }

    func checkMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micPermissionGranted = true
        default:
            micPermissionGranted = false
        }
    }

    func requestMicPermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        micPermissionGranted = granted
        return granted
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
