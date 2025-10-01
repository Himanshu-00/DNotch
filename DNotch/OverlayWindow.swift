//
//  OverlayWindow.swift
//  DNotch
//
//  Created by Himanshu Vinchurkar on 20/09/25.
//




import Cocoa

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    init(notchRect: CGRect) {
        super.init(
            contentRect: notchRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .statusBar
        //  IMP: START with mouse events IGNORED (pass-through)
        self.ignoresMouseEvents = false  // ← THIS WAS YOUR PROBLEM!
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    //Control mouse events dynamically
    func setInteractive(_ interactive: Bool) {
        self.ignoresMouseEvents = !interactive
        print("🖱️ Window interactive: \(interactive)")
    }
}
