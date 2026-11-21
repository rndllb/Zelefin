import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// Reads and sets the device media volume (hardware / Control Center), not an in-app gain.
@MainActor
enum DeviceVolume {
    static var level: Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    static func set(_ value: Float) {
        let clamped = min(1, max(0, value))
        if apply(clamped) { return }
        // Slider may not exist until the hidden host is in the hierarchy.
        Task { @MainActor in
            _ = apply(clamped)
        }
    }

    static func adjust(by delta: Float) {
        set(level + delta)
    }

    /// Called by [DeviceVolumeHost] when the hidden MPVolumeView is ready.
    fileprivate static func bind(slider: UISlider?) {
        volumeSlider = slider
    }

    @discardableResult
    private static func apply(_ clamped: Float) -> Bool {
        guard let slider = volumeSlider else { return false }
        slider.setValue(clamped, animated: false)
        slider.sendActions(for: [.valueChanged, .touchUpInside])
        return true
    }

    private static weak var volumeSlider: UISlider?
}

/// Off-screen MPVolumeView so [DeviceVolume] can drive the system volume slider.
@MainActor
struct DeviceVolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.attach(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        func attach(_ view: MPVolumeView) {
            view.layoutIfNeeded()
            DeviceVolume.bind(slider: Self.findSlider(in: view))
            // Subviews can appear a tick later.
            Task { @MainActor in
                view.layoutIfNeeded()
                DeviceVolume.bind(slider: Self.findSlider(in: view))
            }
        }

        private static func findSlider(in view: UIView) -> UISlider? {
            if let slider = view as? UISlider { return slider }
            for child in view.subviews {
                if let slider = findSlider(in: child) { return slider }
            }
            return nil
        }
    }
}
