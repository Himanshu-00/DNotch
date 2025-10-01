//
//  NotchHitTest.swift
//  DNotch
//
//  Created by Himanshu Vinchurkar on 20/09/25.
//



import Cocoa
import SwiftUI

class EnhancedHitTestView: NSView {
    var notchState: EnhancedNotchState
    private var showDebugColors = false  // Toggle for debug colors
    private var isExpanding = false
    private var expandTimer: DispatchWorkItem?

    init(frame: CGRect, notchState: EnhancedNotchState) {
        self.notchState = notchState
        super.init(frame: frame)
        self.wantsLayer = true
        
        //  ADD ONLY THIS LINE
            self.registerForDraggedTypes([.fileURL, .URL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    //  ADD ONLY THIS METHOD
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        print("🎯 DRAG DETECTED - Auto-expanding to tempFiles")
        print("🔍 DEBUG DRAG:")
         print("  - Current state: \(notchState.currentState)")
         print("  - isExpanding: \(isExpanding)")
         print("  - Timer active: \(expandTimer != nil)")
         print("  - Files count: \(notchState.droppedFiles.count)")
         print("  - Charging: \(notchState.batteryMonitor.isCharging)")
        
        //  CRITICAL: Cancel any existing timer and reset flags
        expandTimer?.cancel()
        isExpanding = false
        
        DispatchQueue.main.async {
            self.notchState.setState(.tempFiles)
        }
        
        return .copy
    }

    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        needsDisplay = true  // Force redraw for debug colors
    }

    // DEBUG: Draw colored backgrounds for hit areas
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard showDebugColors else { return }
        
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        
        // Draw different colored rectangles for each hit area
        switch notchState.currentState {
        case .minimal:
            // GREEN for minimal hit area
            context?.setFillColor(NSColor.green.withAlphaComponent(0.3).cgColor)
            context?.fill(minimalHitRect())
            
            // Draw border
            context?.setStrokeColor(NSColor.green.cgColor)
            context?.setLineWidth(2.0)
            context?.stroke(minimalHitRect())
            
        case .hovered:
            // BLUE for hovered hit area
            context?.setFillColor(NSColor.blue.withAlphaComponent(0.3).cgColor)
            context?.fill(hoveredHitRect())
            
            // Draw border
            context?.setStrokeColor(NSColor.blue.cgColor)
            context?.setLineWidth(2.0)
            context?.stroke(hoveredHitRect())
            
        case .tempFiles:
            // RED for expanded hit area
            context?.setFillColor(NSColor.red.withAlphaComponent(0.3).cgColor)
            context?.fill(expandedHitRect())
            
            // Draw border
            context?.setStrokeColor(NSColor.red.cgColor)
            context?.setLineWidth(2.0)
            context?.stroke(expandedHitRect())
        }
        
        // Always show all areas with different colors for comparison
        if showDebugColors {
            // Minimal area - GREEN outline
            context?.setStrokeColor(NSColor.green.cgColor)
            context?.setLineWidth(1.0)
            context?.stroke(minimalHitRect())
            
            // Hovered area - BLUE outline
            context?.setStrokeColor(NSColor.blue.cgColor)
            context?.setLineWidth(1.0)
            context?.stroke(hoveredHitRect())
            
            // Expanded area - RED outline
            context?.setStrokeColor(NSColor.red.cgColor)
            context?.setLineWidth(1.0)
            context?.stroke(expandedHitRect())
            
            // Add labels
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            
            // Label for minimal
            let minimalRect = minimalHitRect()
            let minimalLabel = NSAttributedString(string: " MINIMAL ", attributes: attributes)
            minimalLabel.draw(at: CGPoint(x: minimalRect.midX - 30, y: minimalRect.midY))
            
            // Label for hovered
            let hoveredRect = hoveredHitRect()
            let hoveredLabel = NSAttributedString(string: " HOVERED ", attributes: attributes)
            hoveredLabel.draw(at: CGPoint(x: hoveredRect.midX - 30, y: hoveredRect.midY))
            
            // Label for expanded
            let expandedRect = expandedHitRect()
            let expandedLabel = NSAttributedString(string: " EXPANDED ", attributes: attributes)
            expandedLabel.draw(at: CGPoint(x: expandedRect.midX - 40, y: expandedRect.midY))
        }
        
        context?.restoreGState()
    }

    // FIXED: Simple hit testing that works
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = self.convert(point, from: nil)
        
        //  SIMPLE: Only care about hits when window is interactive
        switch notchState.currentState {
        case .minimal:
            // Check tiny minimal area for state transition
            if minimalHitRect().contains(localPoint) {
                return self  // Capture for expansion
            }
            return nil  // Pass through everything else
            
        case .hovered, .tempFiles:
            // Pass to SwiftUI for UI interactions
            return super.hitTest(point)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = self.convert(event.locationInWindow, from: nil)
        
        print("🖱️ Mouse down at: \(localPoint), state: \(notchState.currentState)")
        
        switch notchState.currentState {
        case .minimal:
            if minimalHitRect().contains(localPoint) {
                print("🔄 Minimal → Hovered")
                notchState.setState(.hovered)
                needsDisplay = true
            }
            
        case .hovered:
            if !hoveredHitRect().contains(localPoint) {
                print("🔄 Hovered → Minimal")
                notchState.setState(.minimal)
                needsDisplay = true
            }
            
        case .tempFiles:
            if !expandedHitRect().contains(localPoint) {
                print("🔄 TempFiles → Minimal")
                notchState.setState(.minimal)
                needsDisplay = true
            }
        }
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        print("Mouse entered notch area")
        
        DispatchQueue.main.async {
            switch self.notchState.currentState {
            case .minimal:
                //  SMART: Check if hovered state has content
                let hasContent = !self.notchState.droppedFiles.isEmpty ||
                               self.notchState.batteryMonitor.isCharging
                
                if hasContent {
                    // Useful hovered state - show it first
                    print("Minimal → Hovered (has content)")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.notchState.setState(.hovered)
                    }
                } else {
                    // Empty hovered state - skip directly to expanded
                    print("Minimal → TempFiles (no hovered content)")
                    withAnimation(.smooth(duration: 0.5, extraBounce: 0.1)) {
                        self.notchState.setState(.tempFiles)
                    }
                    
                    //  Add auto-collapse timer for direct expansion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        if self.notchState.currentState == .tempFiles &&
                           self.notchState.droppedFiles.isEmpty &&
                           !self.notchState.batteryMonitor.isCharging {
                            print("4-sec timeout - returning to minimal")
                            withAnimation(.smooth(duration: 0.5, extraBounce: 0.1)) {
                                self.notchState.setState(.minimal)
                            }
                        }
                    }
                }
                
            case .hovered, .tempFiles:
                break
            }
        }
    }
    
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let localPoint = self.convert(event.locationInWindow, from: nil)
        
        print("🖱️ Mouse exited at: \(localPoint)")
        
        //  FIXED: Check BOTH files AND charging state
        let shouldStayActive = !notchState.droppedFiles.isEmpty || notchState.batteryMonitor.isCharging
        
        if shouldStayActive {
            // Files OR charging present - IGNORE mouse exit and stay in hovered
            print("Files (\(notchState.droppedFiles.count)) or charging (\(notchState.batteryMonitor.isCharging)) - IGNORING mouse exit")
            
            // Force hovered state if not already there
            if notchState.currentState == .minimal {
                print("Forcing hovered state - files or charging present")
                notchState.setState(.hovered)
            }
        } else {
            // No files AND no charging - normal collapse behavior
            switch notchState.currentState {
            case .hovered:
                if !hoveredHitRect().contains(localPoint) {
                    print("No files, no charging - returning to minimal")
                    notchState.setState(.minimal)
                }
            case .tempFiles:
                if !expandedHitRect().contains(localPoint) {
                    print("No files, no charging - returning to minimal")
                    notchState.setState(.minimal)
                }
            default:
                break
            }
        }
    }

    
    override func mouseMoved(with event: NSEvent) {
        let localPoint = self.convert(event.locationInWindow, from: nil)
        
        switch notchState.currentState {
        case .minimal:
            if minimalHitRect().contains(localPoint) {
                //  SMART: Check if hovered state has useful content
                let hasContent = !notchState.droppedFiles.isEmpty || notchState.batteryMonitor.isCharging
                
                if hasContent {
                    // Hovered has content - show it first
                    print("🖱️ Entering minimal → hovered (has content)")
                    notchState.setState(.hovered)
                } else {
                    // No content in hovered - skip directly to tempFiles
                    print("🖱️ Entering minimal → tempFiles (skipping empty hovered)")
                    isExpanding = true
                    
                    withAnimation(.smooth(duration: 0.5, extraBounce: 0.1)) {
                        notchState.setState(.tempFiles)
                    }
                    
                    // Add timer for direct expansion
                    expandTimer = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        if self.notchState.currentState == .tempFiles &&
                           self.notchState.droppedFiles.isEmpty &&
                           !self.notchState.batteryMonitor.isCharging {
                            print("⏰ 4-sec timeout - returning to minimal")
                            withAnimation(.smooth(duration: 0.5, extraBounce: 0.1)) {
                                self.notchState.setState(.minimal)
                            }
                            self.isExpanding = false
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: expandTimer!)
                }
            }

        case .hovered:
            //  Only allow center expansion if hovered actually has content to show
            let hasContent = !notchState.droppedFiles.isEmpty || notchState.batteryMonitor.isCharging
            
            if hasContent {
                // Hovered has content - allow normal center expansion
                let centerExpandZone = CGRect(
                    x: (bounds.width - 200) / 2,
                    y: bounds.height - 100,
                    width: 200,
                    height: 30
                )
                
                let hoveredArea = hoveredHitRect()
                
                if hoveredArea.contains(localPoint) && centerExpandZone.contains(localPoint) && !isExpanding {
                    print("🔄 Center movement detected - Hovered → TempFiles")
                    isExpanding = true
                    
                    expandTimer?.cancel()
                    
                    withAnimation(.smooth(duration: 0.5, extraBounce: 0.1)) {
                        notchState.setState(.tempFiles)
                    }
                    
                    expandTimer = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        if self.notchState.currentState == .tempFiles {
                            let targetState: NotchState =
                                (!self.notchState.droppedFiles.isEmpty || self.notchState.batteryMonitor.isCharging) ? .hovered : .minimal
                            print("⏰ 4-sec timeout - returning to \(targetState)")
                            withAnimation(.smooth(duration: 0.5, extraBounce: 0.1)) {
                                self.notchState.setState(targetState)
                            }
                            self.isExpanding = false
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: expandTimer!)
                }
                else if !hoveredArea.contains(localPoint) &&
                         notchState.droppedFiles.isEmpty &&
                         !notchState.batteryMonitor.isCharging {
                    print("🖱️ Leaving hovered → minimal (no files, no charging)")
                    notchState.setState(.minimal)
                }
            } else {
                //  EDGE CASE: If we somehow got to hovered with no content, skip to tempFiles
                print("🖱️ Hovered has no content - jumping to tempFiles")
                notchState.setState(.tempFiles)
            }
            
        case .tempFiles:
            isExpanding = false
            
            if !expandedHitRect().contains(localPoint) &&
               notchState.droppedFiles.isEmpty &&
               !notchState.batteryMonitor.isCharging {
                expandTimer?.cancel()
                print("🖱️ Leaving tempFiles → minimal (no files, no charging)")
                notchState.setState(.minimal)
            }
        }
    }

    
    // Hit rectangles with debug info
    private func minimalHitRect() -> CGRect {
        let rect = CGRect(
            x: (bounds.width - 180) / 2,
            y: bounds.height - 90,
            width: 180,
            height: 70
        )
        return rect
    }
    
    private func hoveredHitRect() -> CGRect {
        let rect = CGRect(
            x: (bounds.width - 500) / 2,
            y: bounds.height - 100,
            width: 500,
            height: 87
        )
        return rect
    }
    
    private func expandedHitRect() -> CGRect {
        let rect = CGRect(
            x: (bounds.width - 550) / 2,
            y: bounds.height - 280,
            width: 550,
            height: 220
        )
        return rect
    }
    
    // UTILITY: Toggle debug colors
    func toggleDebugColors() {
        showDebugColors.toggle()
        needsDisplay = true
        print("🎨 Debug colors: \(showDebugColors ? "ON" : "OFF")")
    }
    
    // UTILITY: Enable/disable debug colors
    func setDebugColors(_ enabled: Bool) {
        showDebugColors = enabled
        needsDisplay = true
        print("🎨 Debug colors: \(showDebugColors ? "ON" : "OFF")")
    }
}

