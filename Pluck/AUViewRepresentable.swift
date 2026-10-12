import SwiftUI
import AppKit
import AVFoundation
import CoreAudioKit

public struct AUViewRepresentable: NSViewControllerRepresentable {
    public let audioUnit: AVAudioUnit?

    public init(audioUnit: AVAudioUnit?) {
        self.audioUnit = audioUnit
    }

    public func makeNSViewController(context: Context) -> NSViewController {
        let containerVC = NSViewController()
        containerVC.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        
        guard let auNode = audioUnit else {
            showEmptyMessage(vc: containerVC, message: "No Audio Unit Loaded")
            return containerVC
        }
        
        auNode.auAudioUnit.requestViewController { (vc) in
            DispatchQueue.main.async {
                if let viewController = vc {
                    containerVC.addChild(viewController)
                    
                    let targetSize = viewController.preferredContentSize
                    if targetSize.width > 0 && targetSize.height > 0 {
                        containerVC.view.frame.size = targetSize
                    }
                    
                    viewController.view.translatesAutoresizingMaskIntoConstraints = false
                    containerVC.view.addSubview(viewController.view)
                    
                    NSLayoutConstraint.activate([
                        viewController.view.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor),
                        viewController.view.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor),
                        viewController.view.topAnchor.constraint(equalTo: containerVC.view.topAnchor),
                        viewController.view.bottomAnchor.constraint(equalTo: containerVC.view.bottomAnchor)
                    ])
                } else {
                    self.showEmptyMessage(vc: containerVC, message: "Helix Native Editor GUI Loaded (No Custom Editor UI Returned)")
                }
            }
        }
        
        return containerVC
    }

    public func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        // AutoLayout handles resizing automatically. However, we can notify the view that constraints changed if required.
        nsViewController.view.needsLayout = true
    }
    
    private func showEmptyMessage(vc: NSViewController, message: String) {
        let textField = NSTextField(labelWithString: message)
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        textField.textColor = .secondaryLabelColor
        textField.frame = vc.view.bounds
        textField.autoresizingMask = [.width, .height]
        vc.view.addSubview(textField)
    }
}
