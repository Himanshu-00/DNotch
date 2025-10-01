//
//  DNotchApp.swift
//  DNotch
//
//  Created by Himanshu Vinchurkar on 20/09/25.
//

import SwiftUI
import Cocoa


@main
struct DNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView() // Main app UI window
        }
    }
}




class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayWindow: OverlayWindow?
    var notchContentView: EnhancedHitTestView?  // Updated type
    var enhancedNotchState = EnhancedNotchState()
    
    @objc func toggleDebugColors() {
        notchContentView?.toggleDebugColors()
    }


    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let notchRect = getNotchRect() else {
                print("No notch detected")
                return
            }
            print("Enhanced Notch Rect: \(notchRect)")

            self.overlayWindow = OverlayWindow(notchRect: notchRect)
            
            
            //Connect window to state manager
            self.enhancedNotchState.overlayWindow = self.overlayWindow
            

            self.notchContentView = EnhancedHitTestView(
                frame: notchRect,
                //hoverRect: initialHoverRect,
                notchState: self.enhancedNotchState
            )

            let hostingView = NSHostingView(
                rootView: EnhancedNotchView(notchState: self.enhancedNotchState)
            )
            hostingView.frame = self.notchContentView!.bounds
            hostingView.autoresizingMask = [.width, .height]

            self.notchContentView!.addSubview(hostingView)
            self.overlayWindow?.contentView = self.notchContentView
            self.overlayWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

