import SwiftUI
import UIKit
#if canImport(GoogleCast)
import GoogleCast
#endif

/// Fires the system Chromecast device picker from a normal SwiftUI button.
@MainActor
final class CastRouteBridge {
    weak var button: UIButton?

    func presentPicker() {
        #if canImport(GoogleCast)
        button?.sendActions(for: .touchUpInside)
        #endif
    }
}

/// Hidden `GCKUICastButton` mounted once; `bridge.presentPicker()` opens the Cast sheet.
struct CastRoutePickerHost: UIViewRepresentable {
    var bridge: CastRouteBridge

    func makeUIView(context: Context) -> UIView {
        #if canImport(GoogleCast)
        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        button.tintColor = .clear
        button.isUserInteractionEnabled = false
        bridge.button = button
        return button
        #else
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
        #endif
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        #if canImport(GoogleCast)
        if bridge.button == nil, let button = uiView as? GCKUICastButton {
            bridge.button = button
        }
        #endif
    }
}
