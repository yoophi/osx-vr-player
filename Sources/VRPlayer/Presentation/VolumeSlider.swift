import SwiftUI

struct VolumeSlider: NSViewRepresentable {
    let value: Double
    let onChange: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 1,
                              target: context.coordinator, action: #selector(Coordinator.adjust(_:)))
        slider.isVertical = true
        slider.isContinuous = true
        slider.setAccessibilityLabel("볼륨")
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        slider.doubleValue = value
        context.coordinator.onChange = onChange
    }

    final class Coordinator: NSObject {
        var onChange: (Double) -> Void
        init(_ onChange: @escaping (Double) -> Void) { self.onChange = onChange }
        @objc func adjust(_ slider: NSSlider) { onChange(slider.doubleValue) }
    }
}
