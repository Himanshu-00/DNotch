//
//  ContentView.swift
//  DNotch
//
//  Created by Himanshu Vinchurkar on 20/09/25.
//

import SwiftUI
import Cocoa
import CoreGraphics
import PDFKit
import AVFoundation
import QuickLook
import Combine
import Foundation
import IOKit.ps

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

struct NotchPillShape: Shape {
    var cornerRadiusTop: CGFloat
    var cornerRadiusBottom: CGFloat
    var topOffset: CGFloat = 35

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY + topOffset
        let maxY = rect.maxY

        path.move(to: CGPoint(x: minX, y: rect.minY))
        path.addLine(to: CGPoint(x: minX, y: minY))

        path.addQuadCurve(
            to: CGPoint(x: minX + cornerRadiusTop, y: minY + cornerRadiusTop),
            control: CGPoint(x: minX + cornerRadiusTop, y: minY)
        )

        path.addLine(to: CGPoint(x: minX + cornerRadiusTop, y: maxY - cornerRadiusBottom))

        path.addQuadCurve(
            to: CGPoint(x: minX + cornerRadiusTop + cornerRadiusBottom, y: maxY),
            control: CGPoint(x: minX + cornerRadiusTop, y: maxY)
        )

        path.addLine(to: CGPoint(x: maxX - cornerRadiusTop - cornerRadiusBottom, y: maxY))

        path.addQuadCurve(
            to: CGPoint(x: maxX - cornerRadiusTop, y: maxY - cornerRadiusBottom),
            control: CGPoint(x: maxX - cornerRadiusTop, y: maxY)
        )

        path.addLine(to: CGPoint(x: maxX - cornerRadiusTop, y: minY + cornerRadiusTop))

        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY),
            control: CGPoint(x: maxX - cornerRadiusTop, y: minY)
        )
        
        path.addLine(to: CGPoint(x: maxX, y: rect.minY))
        path.closeSubpath()

        return path
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadiusTop, cornerRadiusBottom) }
        set {
            cornerRadiusTop = newValue.first
            cornerRadiusBottom = newValue.second
        }
    }
}

// Enhanced 3-level state management
enum NotchState {
    case minimal
    case hovered
    case tempFiles
}

class EnhancedNotchState: ObservableObject {
    @Published var currentState: NotchState = .minimal
    @Published var droppedFiles: [DroppedFile] = []
    @Published var batteryMonitor = BatteryMonitor()
    private var chargingObserver: NSObjectProtocol?
        
    //INIT WITH CHARGING OBSERVER
    init() {
        setupChargingObserver()
        
        //FIXED: Check initial charging state after setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.batteryMonitor.isCharging && self.currentState == .minimal {
                    print("🔌 Initial charging state detected - expanding to hovered")
                    self.setState(.hovered)
                }
            }
    }
    
    //CHARGING OBSERVER SETUP
    private func setupChargingObserver() {
        chargingObserver = NotificationCenter.default.addObserver(
            forName: .chargingStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let isCharging = notification.object as? Bool else { return }
            
            MainActor.assumeIsolated{
                if isCharging {
                    // Auto-expand to hovered when charging starts
                    print("🔌 Charging started - expanding to hovered")
                    self.setState(.hovered)
                } else {
                    // Auto-collapse when charging stops (only if no files)
                    if self.droppedFiles.isEmpty && (self.currentState == .hovered || self.currentState == .tempFiles) {
                        print("🔌 Charging stopped - collapsing to minimal")
                        self.setState(.minimal)
                    }
                }
            }
        }
    }
    
    //DEINIT TO CLEAN UP OBSERVER
    deinit {
        if let observer = chargingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    //  FIX: Reference to control window
    weak var overlayWindow: OverlayWindow?
    
    func setState(_ state: NotchState) {
        currentState = state
        
        switch state {
        case .minimal:
            if droppedFiles.isEmpty && !batteryMonitor.isCharging {
                //  KEEP: 3-second grace period for fast re-drags
                overlayWindow?.setInteractive(true)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if self.currentState == .minimal &&
                       self.droppedFiles.isEmpty &&
                       !self.batteryMonitor.isCharging {
                        self.overlayWindow?.setInteractive(false)
                    }
                }
            } else {
                overlayWindow?.setInteractive(true)
            }
            
        case .hovered, .tempFiles:
            overlayWindow?.setInteractive(true)
        }
    }

    
    //  UPDATED: Consider charging state when determining if should stay hovered
    func shouldStayHovered() -> Bool {
        return !droppedFiles.isEmpty || batteryMonitor.isCharging
    }
    
    // FIXED: Remove auto-deletion
    func addDroppedFile(_ file: DroppedFile) {
        droppedFiles.append(file)
        
        // Show tempFiles temporarily
        setState(.tempFiles)
        
        // Auto-collapse after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.currentState == .tempFiles {
                //  UPDATED: Check both files and charging state
                if !self.droppedFiles.isEmpty || self.batteryMonitor.isCharging {
                    self.setState(.hovered)  // Show hovered if files OR charging
                } else {
                    self.setState(.minimal)  // Only minimal if no files AND not charging
                }
            }
        }
        
        print("📎 Added file: \(file.name)")
    }
    
    // Update your setState method to be more explicit
    func forceState(_ state: NotchState) {
        print("🔄 Force setting state to: \(state)")
        currentState = state
    }

    func removeDroppedFile(_ file: DroppedFile) {
        droppedFiles.removeAll { $0.id == file.id }
        
        // Only delete when user manually removes
        if let tempURL = file.tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        //  FIXED: Handle all states and consider charging
            if droppedFiles.isEmpty {
                if batteryMonitor.isCharging {
                    // Charging active - stay in hovered
                    print("🔋 Files removed but charging - staying in hovered")
                    setState(.hovered)
                } else {
                    // No charging, no files - go to minimal
                    print("📁 No files, no charging - going to minimal")
                    setState(.minimal)
                }
            }
    }
    
    func clearAllFiles() {
        for file in droppedFiles {
            if let tempURL = file.tempURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        droppedFiles.removeAll()
        
        //  UPDATED: Only go to minimal if not charging
        if !batteryMonitor.isCharging {
            setState(.minimal)
        } else {
            setState(.hovered)  // Stay hovered if charging
        }
    }
    
    func launchApp(_ appName: String) {
        let apps = [
            "calculator": "/System/Applications/Calculator.app",
            "safari": "/Applications/Safari.app",
            "notes": "/System/Applications/Notes.app",
            "preview": "/System/Applications/Preview.app",
            "finder": "/System/Library/CoreServices/Finder.app",
            "mail": "/System/Applications/Mail.app"
        ]
        
        if let appPath = apps[appName.lowercased()],
           FileManager.default.fileExists(atPath: appPath) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                //  UPDATED: Consider charging state when collapsing
                if !self.droppedFiles.isEmpty || self.batteryMonitor.isCharging {
                    self.setState(.hovered)  // Stay hovered if files or charging
                } else {
                    self.setState(.minimal)  // Only minimal if nothing to show
                }
            }
        }
    }
}



//FILE STRUCTURES
struct DroppedFile: Identifiable, Equatable {
    let id: UUID
    let name: String
    let originalURL: URL
    let fileType: FileType
    let droppedAt: Date
    let previewImage: NSImage?
    var tempURL: URL?
    
    static func == (lhs: DroppedFile, rhs: DroppedFile) -> Bool {
        return lhs.id == rhs.id
    }
}

enum FileType {
    case image
    case document
    case video
    case audio
    case archive
    case other
    
    var icon: String {
        switch self {
        case .image: return "photo"
        case .document: return "doc.text"
        case .video: return "video"
        case .audio: return "music.note"
        case .archive: return "archivebox"
        case .other: return "doc"
        }
    }
    
    var color: Color {
        switch self {
        case .image: return .green
        case .document: return .blue
        case .video: return .purple
        case .audio: return .orange
        case .archive: return .gray
        case .other: return .white
        }
    }
}

// TEMP FILE MANAGER
class TempFileManager {
    static let shared = TempFileManager()
    private let tempDirectory: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first!
        tempDirectory = appSupport.appendingPathComponent("DynamicNotch/TempFiles")
        createTempDirectory()
    }
    
    private func createTempDirectory() {
        try? FileManager.default.createDirectory(at: tempDirectory,
                                               withIntermediateDirectories: true)
    }
    
    func copyFileToTemp(_ sourceURL: URL) -> URL? {
        let fileName = sourceURL.lastPathComponent
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)
            return tempURL
        } catch {
            print("❌ Failed to copy file to temp: \(error)")
            return nil
        }
    }
}



struct EnhancedNotchView: View {
    @ObservedObject var notchState: EnhancedNotchState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NotchPillShape(
                    cornerRadiusTop: cornerRadius,
                    cornerRadiusBottom: cornerRadius
                )
                .fill(Color.black)
                .frame(width: currentWidth, height: currentHeight)
                //.animation(.spring(response: 0.4, dampingFraction: 0.8), value: notchState.currentState)
                .animation(.smooth(duration: 0.4, extraBounce: 0.1), value: notchState.currentState)

                
                contentView
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: notchState.currentState)
            }
            Spacer(minLength: 0)
        }
        .frame(width: maxWidth, height: maxHeight)
        .onDrop(of: [UTType.fileURL], isTargeted: .constant(false), perform: handleFileDrop)
    }
    
    // SIZING
    private var currentWidth: CGFloat {
        switch notchState.currentState {
        case .minimal: return 200
        case .hovered: return 400
        case .tempFiles: return 600  // This will be expanded state
        }
    }
    
    private var currentHeight: CGFloat {
        switch notchState.currentState {
        case .minimal: return 67
        case .hovered: return 67
        case .tempFiles: return 280  // This will be expanded state
        }
    }
    
    private var maxWidth: CGFloat { 650 }
    private var maxHeight: CGFloat { 300 }
    private var cornerRadius: CGFloat { 15 }
    
    @ViewBuilder
    private var contentView: some View {
        switch notchState.currentState {
        case .minimal:
            minimalContent
        case .hovered:
            hoveredContent
        case .tempFiles:
            expandedContent  // Renamed - this is now the expanded state
        }
    }
    
    // MINIMAL - Keep clean (no file indicator here - it's hidden anyway)
    private var minimalContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 8, height: 8)
            
            Text("DNotch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: currentWidth, height: currentHeight)
    }

    // HOVERED - File indicator at left edge, stays visible when files present
    // HOVERED - Eye icon moved right and better positioned
    // In EnhancedNotchView - replace hoveredContent:
    private var hoveredContent: some View {
        HStack(spacing: 0) {
            // LEFT WING - File indicator (existing code)
            HStack {
                //Spacer()
                
                if !notchState.droppedFiles.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Text("\(notchState.droppedFiles.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange.opacity(0.9))
                    }
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.orange.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.orange.opacity(0.3), lineWidth: 0.5)
                            )
                    )
                    .offset(x:30, y: 16.5)
                }
                
                Spacer()
            }
            .frame(width: 120, height: currentHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.smooth(duration: 0.5, extraBounce: 0.1)) {
                    notchState.setState(.tempFiles)
                }
            }
            
            // CENTER AREA - Clickable to expand
            Rectangle()
                .fill(Color.clear)
                .frame(width: 160, height: currentHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.5, extraBounce: 0.1)) {
                        notchState.setState(.tempFiles)
                    }
                }
            
            // RIGHT WING - Charging indicator
            HStack {
                Spacer()
                
                if notchState.batteryMonitor.isCharging {
                    HStack(spacing: 3) {
                        Image(systemName: chargingIcon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(chargingColor)
                        
                        Text("\(notchState.batteryMonitor.batteryLevel)%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(chargingColor.opacity(0.9))
                    }
                    .frame(width: 55, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(chargingColor.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(chargingColor.opacity(0.3), lineWidth: 0.5)
                            )
                    )
                    .offset(y: 16)
                    .animation(.easeInOut(duration: 0.3), value: notchState.batteryMonitor.isCharging)
                    .animation(.easeInOut(duration: 0.3), value: notchState.batteryMonitor.isFullyCharged)
                }
                
                Spacer()
            }
            .frame(width: 120, height: currentHeight)
        }
        .frame(width: currentWidth, height: currentHeight)
    }

    // Helper computed properties for charging indicator
    private var chargingIcon: String {
        if notchState.batteryMonitor.isFullyCharged {
            return "checkmark.circle.fill"  //  Full
        } else {
            return "bolt.fill"  // ⚡ Charging
        }
    }

    private var chargingColor: Color {
        if notchState.batteryMonitor.isFullyCharged {
            return .green  // Green when full
        } else {
            return .yellow  // Yellow when charging
        }
    }

    
    // EXPANDED - Full feature panel
    private var expandedContent: some View {
        VStack(spacing: 0) {
            // TOP SPACER - Reasonable space for physical notch
            Rectangle()
                .fill(Color.clear)
                .frame(height: 65) // Reasonable top space
            
            // MAIN CONTENT - Compact and clean
            VStack(spacing: 0) {
                Spacer() // Push to bottom area
                    .frame(height: 20) //  Adjust this number to push content down more
                
                // CLEAN LAYOUT
                VStack(spacing: 24) { // Reasonable section spacing
                    
                    // APPS ROW - Clean compact spacing
                    HStack(spacing: 32) { // Good spacing, not too much
                        ForEach(getAllApps(), id: \.name) { app in
                            CleanCompactButton(app: app) {
                                print("🚀 Launching \(app.name)")
                                notchState.launchApp(app.name)
                            }
                        }
                    }
                    .padding(.horizontal, 32) // Reasonable margins
                    
                    // FILES SECTION - Compact and clean
                    if !notchState.droppedFiles.isEmpty {
                        VStack(spacing: 16) { // Compact spacing
                            
                            // CLEAN HEADER with clear button at right
                            HStack {
                                HStack(spacing: 6) {
                                    Text("Recent Files")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    // Simple count badge
                                    Text("\(notchState.droppedFiles.count)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 16, height: 16)
                                        .background(
                                            Circle()
                                                .fill(.red.opacity(0.7))
                                        )
                                }
                                
                                Spacer()
                                
                                // CLEAR BUTTON - Simple, at right edge
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        notchState.clearAllFiles()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 10))
                                        Text("Clear")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(.red.opacity(0.6))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Clear all files")
                            }
                            .padding(.horizontal, 32)
                            
                            // CLEAN FILE GRID
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) { // Compact file spacing
                                    ForEach(notchState.droppedFiles) { file in
                                        CompactFileCard(file: file) {
                                            openFile(file)
                                        } onDelete: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                notchState.removeDroppedFile(file)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 32)
                            }
                            .frame(maxHeight: 90) // Compact height
                        }
                    } else {
                        // SIMPLE EMPTY STATE - No fancy effects
                        Button(action: {
                            showAddFilesDialog()
                        }) {
                            VStack(spacing: 12) {
                                // Simple add button - NO GLOWS
                                Circle()
                                    .fill(.purple.opacity(0.3))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.purple)
                                    )
                                
                                VStack(spacing: 4) {
                                    Text("Add Files")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    Text("Click or drag & drop (5 files max)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding(.vertical, 16) // Compact padding
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Click to add files")
                    }
                }
                
                Spacer(minLength: 20) // Reasonable bottom space
            }
        }
        .frame(width: currentWidth, height: currentHeight)
    }




    
    // Helper methods for new functionality
    private func showAddFilesDialog() {
        print("🔍 Opening file picker dialog")
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                createDroppedFile(from: url)
            }
        }
    }

    private func scrollToFiles() {
        print("📜 Scrolling to files section")
        // Could add smooth scroll animation here
    }

    
    // Keep your existing helper methods...
    // All apps in one perfect row - no weird positioning
    private func getAllApps() -> [QuickApp] {
        return [
            QuickApp(name: "calculator", icon: "plus.forwardslash.minus", color: .blue),
            QuickApp(name: "safari", icon: "safari.fill", color: .cyan),
            QuickApp(name: "notes", icon: "note.text", color: .yellow),
            QuickApp(name: "finder", icon: "folder.fill", color: .green),
            QuickApp(name: "mail", icon: "envelope.fill", color: .red)
        ]
    }
    
    struct CleanCompactButton: View {
        let app: QuickApp
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) { // Compact spacing
                    // SIMPLE CIRCLE - No glows or fancy effects
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [app.color.opacity(0.4), app.color.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44) // Reasonable size
                        .overlay(
                            Image(systemName: app.icon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(app.color)
                        )
                        .overlay(
                            Circle()
                                .stroke(app.color.opacity(0.5), lineWidth: 1)
                        )
                    
                    Text(app.name.capitalized)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .help("Launch \(app.name.capitalized)")
        }
    }


    // FIXED: Update your file drop handler
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        print("📁 File drop initiated")
        
        // CHECK FREE TIER LIMIT
        let remainingSlots = 5 - notchState.droppedFiles.count
        if remainingSlots <= 0 {
            showUpgradeAlert()
            return false
        }
        
        var processedCount = 0
        for provider in providers {
            if processedCount >= remainingSlots {
                break
            }
            
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let fileURL = url, fileURL.isFileURL else {
                    return
                }
                
                DispatchQueue.main.async {
                    if self.notchState.droppedFiles.count < 5 {
                        print("📎 Processing file: \(fileURL.lastPathComponent)")
                        self.createDroppedFile(from: fileURL)
                        
                    }
                }
            }
            processedCount += 1
        }

        
        return true
    }

    // FIXED: Update clear files method
    private func clearAllFiles() {
        notchState.clearAllFiles()
        print("🔓 All files cleared - allowing minimal state")
        withAnimation(.easeInOut(duration: 0.3)) {
            notchState.setState(.minimal)
        }
    }

    // FIXED: Update remove single file
    private func removeFile(_ file: DroppedFile) {
        withAnimation(.easeInOut(duration: 0.2)) {
            notchState.removeDroppedFile(file)
            
            // Check if no files left, return to minimal
            if notchState.droppedFiles.isEmpty {
                withAnimation(.easeInOut(duration: 0.3)) {
                    notchState.setState(.minimal)
                }
            }
        }
    }


        // Show upgrade alert when limit reached
        private func showUpgradeAlert() {
            print("💎 Free tier limit reached - show upgrade popup")
            // You can implement a nice popup here later
        }

    
        private func createDroppedFile(from url: URL) {
            guard let tempURL = TempFileManager.shared.copyFileToTemp(url) else {
                print("❌ Failed to copy file to temp")
                return
            }
    
            let droppedFile = DroppedFile(
                id: UUID(),
                name: url.lastPathComponent,
                originalURL: url,
                fileType: determineFileType(url),
                droppedAt: Date(),
                previewImage: generatePreview(url),
                tempURL: tempURL
            )
    
            withAnimation(.easeInOut(duration: 0.3)) {
                notchState.addDroppedFile(droppedFile)
            }
    
            print(" File added: \(droppedFile.name)")
        }
    
        private func determineFileType(_ url: URL) -> FileType {
            let ext = url.pathExtension.lowercased()
    
            switch ext {
            case "jpg", "jpeg", "png", "gif", "heic", "webp": return .image
            case "pdf", "doc", "docx", "txt", "rtf": return .document
            case "mp4", "mov", "avi", "mkv": return .video
            case "mp3", "aac", "m4a", "wav": return .audio
            case "zip", "rar", "7z": return .archive
            default: return .other
            }
        }
    
    
        private func generatePreview(_ url: URL) -> NSImage? {
            let fileType = determineFileType(url)
    
            switch fileType {
            case .image:
                //  Images - Keep current working code
                return NSImage(contentsOf: url)
    
            case .document:
                // 📄 PDF Preview - First page thumbnail
                if url.pathExtension.lowercased() == "pdf" {
                    return generatePDFPreview(url)
                }
                // 📝 Text files - Generate text preview
                else {
                    return generateTextPreview(url)
                }
    
            case .video:
                // 📱 Video Preview - First frame thumbnail
                return generateVideoPreview(url)
    
            case .audio:
                // 🎵 Audio Preview - Album artwork
                return generateAudioPreview(url)
    
            default:
                // For other types, return nil to show icon
                return nil
            }
        }
    
        // PDF PREVIEW GENERATION
        private func generatePDFPreview(_ url: URL) -> NSImage? {
            guard let pdfDocument = PDFDocument(url: url),
                  let firstPage = pdfDocument.page(at: 0) else {
                return nil
            }
    
            // Use PDFPage's built-in thumbnail generation
            let thumbnailSize = NSSize(width: 45, height: 45)
            return firstPage.thumbnail(of: thumbnailSize, for: .mediaBox)
        }
    
    
        //VIDEO PREVIEW GENERATION
        private func generateVideoPreview(_ url: URL) -> NSImage? {
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
    
            // Use semaphore to make async call synchronous
                let semaphore = DispatchSemaphore(value: 0)
                var resultImage: NSImage?
    
                let time = CMTime(seconds: 1.0, preferredTimescale: 600)
    
                imageGenerator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                    defer { semaphore.signal() }
    
                    if let error = error {
                        print("❌ Video preview generation failed: \(error)")
                        return
                    }
    
                    guard let cgImage = cgImage else {
                        print("❌ No image generated for video")
                        return
                    }
    
                    resultImage = NSImage(cgImage: cgImage, size: NSSize(width: 45, height: 45))
                }
    
                // Wait for completion (with timeout)
                _ = semaphore.wait(timeout: .now() + 3.0) // 3 second timeout
    
                return resultImage
        }
    
        //TEXT PREVIEW GENERATION
        private func generateTextPreview(_ url: URL) -> NSImage? {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
    
            // Take first few lines
            let lines = content.components(separatedBy: .newlines).prefix(6)
            let previewText = lines.joined(separator: "\n")
    
            // Create image with text
            let thumbnailSize = NSSize(width: 45, height: 45)
            let image = NSImage(size: thumbnailSize)
    
            image.lockFocus()
    
            // White background
            NSColor.white.set()
            NSRect(origin: .zero, size: thumbnailSize).fill()
    
            // Draw text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 6),
                .foregroundColor: NSColor.black
            ]
    
            let attributedString = NSAttributedString(string: previewText, attributes: attributes)
            let textRect = NSRect(x: 2, y: 2, width: 41, height: 41)
            attributedString.draw(in: textRect)
    
            image.unlockFocus()
            return image
        }
    
        //AUDIO PREVIEW GENERATION
        private func generateAudioPreview(_ url: URL) -> NSImage? {
            let asset = AVURLAsset(url: url)
    
            // Use semaphore to make async call synchronous
            let semaphore = DispatchSemaphore(value: 0)
            var resultImage: NSImage?
    
            Task {
                do {
                    // Load metadata formats asynchronously
                    let metadataFormats = try await asset.load(.availableMetadataFormats)
    
                    for format in metadataFormats {
                        let metadata = try await asset.loadMetadata(for: format)
    
                        for item in metadata {
                            if item.commonKey == .commonKeyArtwork,
                               let data = try await item.load(.dataValue),
                               let artwork = NSImage(data: data) {
    
                                // Resize to thumbnail
                                let thumbnail = NSImage(size: NSSize(width: 45, height: 45))
                                thumbnail.lockFocus()
                                artwork.draw(in: NSRect(origin: .zero, size: NSSize(width: 45, height: 45)))
                                thumbnail.unlockFocus()
    
                                resultImage = thumbnail
                                break
                            }
                        }
    
                        if resultImage != nil { break }
                    }
                } catch {
                    print("Audio metadata loading failed: \(error)")
                }
    
                // If no artwork found, create waveform preview
                if resultImage == nil {
                    resultImage = generateWaveformPreview(url)
                }
    
                semaphore.signal()
            }
    
            // Wait for completion (with timeout)
            _ = semaphore.wait(timeout: .now() + 2.0) // 2 second timeout
    
            return resultImage ?? generateWaveformPreview(url)
        }
    
    
        //SIMPLE WAVEFORM PREVIEW (for audio without artwork)
        private func generateWaveformPreview(_ url: URL) -> NSImage? {
            let thumbnailSize = NSSize(width: 45, height: 45)
            let image = NSImage(size: thumbnailSize)
    
            image.lockFocus()
    
            // Dark background
            NSColor.black.set()
            NSRect(origin: .zero, size: thumbnailSize).fill()
    
            // Draw simple waveform bars
            NSColor.blue.set()
            let barCount = 8
            let barWidth: CGFloat = 4
            let spacing: CGFloat = 1
    
            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + spacing) + 3
                let height = CGFloat.random(in: 10...35)
                let y = (thumbnailSize.height - height) / 2
    
                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                barRect.fill()
            }
    
            image.unlockFocus()
            return image
        }
    
    
        private func openFile(_ file: DroppedFile) {
            print("🚀 Attempting to open file: \(file.name)")
    
            // Try temp file first, then original
            let urlsToTry = [file.tempURL, file.originalURL].compactMap { $0 }
    
            for url in urlsToTry {
                if FileManager.default.fileExists(atPath: url.path) {
                    print(" Opening file at: \(url.path)")
                    NSWorkspace.shared.open(url)
                    return
                }
            }
    
            print("❌ File not found: \(file.name)")
    
            // Show alert if file not found
            let alert = NSAlert()
            alert.messageText = "File Not Found"
            alert.informativeText = "The file '\(file.name)' could not be opened. It may have been moved or deleted."
            alert.alertStyle = .warning
            alert.runModal()
        }
}


// ENHANCED FileCard with better interaction
struct CompactFileCard: View {
    let file: DroppedFile
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 6) { //  REMOVE Button wrapper
            // SIMPLE PREVIEW - No fancy glows
            Group {
                if let preview = file.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipped()
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(file.fileType.color.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: file.fileType.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(file.fileType.color)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(file.fileType.color.opacity(0.5), lineWidth: 1)
                        )
                }
            }
            .onTapGesture { onTap() }  //  Move tap to image only
            
            Text(file.name)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 60)
        }
        .frame(width: 70, height: 70)
        .onDrag {  //  Drag should work now!
            return NSItemProvider(object: file.originalURL as NSURL)
        }
        .contextMenu {
            Button("Open") { onTap() }
            Button("Show in Finder") { showInFinder() }
            Button("Remove", role: .destructive) { onDelete() }
        }
    }
    
    private func showInFinder() {
        if let tempURL = file.tempURL, FileManager.default.fileExists(atPath: tempURL.path) {
            NSWorkspace.shared.selectFile(tempURL.path, inFileViewerRootedAtPath: tempURL.deletingLastPathComponent().path)
        }
    }
}



struct QuickApp {
    let name: String
    let icon: String
    let color: Color
}



func getNotchRect() -> CGRect? {
    guard let screen = NSScreen.main else { return nil }

    let screenFrame = screen.frame
    let visibleFrame = screen.visibleFrame
    let maxHeight: CGFloat = 350  // Smaller height
    
    let menuBarAndNotchHeight = visibleFrame.origin.y
    if menuBarAndNotchHeight <= 22 { return nil }

    let notchWidth: CGFloat = 600  // Narrower width for side positioning
    let notchX = (screenFrame.width - notchWidth) / 2
    let notchY = screenFrame.height - 290  // MUCH LOWER - below physical notch

    return CGRect(x: notchX, y: notchY, width: notchWidth, height: maxHeight)
}



class HoverState: ObservableObject {
    @Published var isHovered: Bool = false
}

struct NotchOverlayView: View {
    @ObservedObject var hoverState: HoverState

    // Sizes for collapsed and expanded notch
    let collapsedWidth: CGFloat = 180
    let collapsedHeight: CGFloat = 40
    let expandedWidth: CGFloat = 900
    let expandedHeight: CGFloat = 270

    var isHovered: Bool {
        hoverState.isHovered
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NotchPillShape(
                    cornerRadiusTop: isHovered ? 20 : 0,
                    cornerRadiusBottom: isHovered ? 20 : 0
                )
                .fill(Color.black)
                .frame(
                    width: isHovered ? expandedWidth : collapsedWidth,
                    height: isHovered ? expandedHeight : collapsedHeight
                )
                .animation(.easeInOut(duration: 0.3), value: isHovered)

                Text("🌟 AI Assistant Active")
                    .font(.headline)
                    .frame(
                        width: isHovered ? expandedWidth : collapsedWidth,
                        height: isHovered ? expandedHeight : collapsedHeight,
                        alignment: .top
                    )
                    .animation(.easeInOut(duration: 0.3), value: isHovered)
            }
            Spacer(minLength: 0)
        }
        .frame(width: expandedWidth, height: expandedHeight)
    }
}

class BatteryMonitor: ObservableObject {
    @Published var isCharging = false
    @Published var batteryLevel: Int = 0
    @Published var isFullyCharged = false
    
    private var timer: Timer?
    
    init() {
        updateBatteryStatus() //  Check initial state
        startMonitoring()
    }
    
        
     func startMonitoring() {
        // First check initial state and notify if charging
        updateBatteryStatus()
        if isCharging {
            NotificationCenter.default.post(name: .chargingStateChanged, object: true)
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateBatteryStatus()
        }
    }
    
    
    private func updateBatteryStatus() {
        guard let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        
        for powerSource in powerSources {
            guard let info = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            // Check if it's the internal battery
            if let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                let wasCharging = isCharging
                
                // Get charging status
                if let chargingState = info[kIOPSPowerSourceStateKey] as? String {
                    isCharging = (chargingState == kIOPSACPowerValue)
                }
                
                // Get battery level
                if let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int {
                    batteryLevel = currentCapacity
                    isFullyCharged = (batteryLevel >= 100) && isCharging
                }
                
                // Trigger state changes
                if wasCharging != isCharging {
                    NotificationCenter.default.post(name: .chargingStateChanged, object: isCharging)
                }
                
                print("🔋 Battery: \(batteryLevel)%, Charging: \(isCharging), Full: \(isFullyCharged)")
                break
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

extension Notification.Name {
    static let chargingStateChanged = Notification.Name("chargingStateChanged")
}

