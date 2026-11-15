//
//  FloatingOverlayWindowController.swift
//  VoiceTranslation
//
//  Created on 2026-02-26.
//  NSPanel-based floating overlay window controller for macOS.
//

import SwiftUI
import AppKit

// MARK: - Floating Overlay Window Controller

class FloatingOverlayWindowController: NSObject, ObservableObject {
    
    private var panel: NSPanel?
    private var localKeyMonitor: Any?
    @Published var isVisible = false
    @Published var isPinned = true
    
    // UserDefaults keys for position & size memory
    private let positionXKey = "FloatingOverlay_PositionX"
    private let positionYKey = "FloatingOverlay_PositionY"
    private let sizeWidthKey = "FloatingOverlay_Width"
    private let sizeHeightKey = "FloatingOverlay_Height"
    
    private weak var viewModel: MainViewModel?
    
    // MARK: - Default Configuration
    
    private let defaultWidth: CGFloat = 480
    private let defaultHeight: CGFloat = 300
    private let minWidth: CGFloat = 320
    private let maxWidth: CGFloat = 640
    private let minHeight: CGFloat = 120
    private let collapsedMinHeight: CGFloat = 88
    private let collapsedMaxHeight: CGFloat = 260
    private let screenEdgePadding: CGFloat = 20
    private let collapsedTitleBarHeight: CGFloat = 48
    
    // Collapse state
    private var expandedHeight: CGFloat?
    private var isCollapsed = false
    
    // Guard: prevent position saving during animated frame changes
    private var isAnimatingFrame = false
    
    // MARK: - Show / Hide
    
    func show(viewModel: MainViewModel) {
        self.viewModel = viewModel
        
        if let panel = panel {
            panel.orderFront(nil)
            isVisible = true
            installKeyMonitor()
            return
        }

        isCollapsed = false
        
        // Create the panel (restore saved size or use defaults)
        let restoredSize = restoredPanelSize()
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: restoredSize.width, height: restoredSize.height),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Panel configuration — always on top, even over fullscreen videos
        panel.isFloatingPanel = true
        panel.level = isPinned ? .statusBar : .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // We handle shadow in SwiftUI
        panel.isMovableByWindowBackground = true
        
        // Force dark appearance regardless of system theme
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        
        // Allow free resizing with minimum constraints only
        panel.minSize = minimumPanelSize(collapsed: false)
        panel.maxSize = maximumPanelSize(for: currentVisibleFrame(), collapsed: false)
        
        // Create the SwiftUI content
        let overlayView = FloatingOverlayView(
            viewModel: viewModel,
            onClose: { [weak self] in
                self?.hide()
            },
            onTogglePin: { [weak self] in
                self?.togglePin()
            },
            onCollapsedChange: { [weak self] collapsed in
                self?.setCollapsed(collapsed)
            },
            isPinned: Binding(
                get: { [weak self] in self?.isPinned ?? true },
                set: { [weak self] in self?.isPinned = $0 }
            )
        )
        
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        panel.contentView = hostingView
        
        // Position: restore saved or default to bottom center
        positionPanel(panel)
        
        // Show
        panel.orderFront(nil)
        self.panel = panel
        isVisible = true
        savePosition()
        
        // Install space key monitor for toggle translation
        installKeyMonitor()
        
        // Save position when moved
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: panel
        )
    }
    
    func hide() {
        savePosition()
        removeKeyMonitor()
        panel?.orderOut(nil)
        isVisible = false
    }
    
    func toggle(viewModel: MainViewModel) {
        if isVisible {
            hide()
        } else {
            show(viewModel: viewModel)
        }
    }
    
    // MARK: - Pin Toggle
    
    private func togglePin() {
        isPinned.toggle()
        if isPinned {
            // statusBar level = above everything including fullscreen apps
            panel?.level = .statusBar
            panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        } else {
            panel?.level = .floating
            panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }
    
    // MARK: - Collapse / Expand Window
    
    private func setCollapsed(_ collapsed: Bool) {
        guard let panel = panel else { return }
        isCollapsed = collapsed
        panel.minSize = minimumPanelSize(collapsed: collapsed)
        panel.maxSize = maximumPanelSize(for: currentVisibleFrame(for: panel.frame), collapsed: collapsed)
        
        if collapsed {
            // Save current height before collapsing
            expandedHeight = max(panel.frame.height, minHeight)
            
            let collapsedHeight = measuredCollapsedHeight(for: panel)
            let currentFrame = panel.frame
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.maxY - collapsedHeight,
                width: currentFrame.width,
                height: collapsedHeight
            )
            
            animatePanelFrame(to: newFrame)
        } else {
            // Restore to expanded height
            let maxHeight = maximumPanelSize(for: currentVisibleFrame(for: panel.frame), collapsed: false).height
            let targetHeight = min(expandedHeight ?? defaultHeight, maxHeight)
            let currentFrame = panel.frame
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.maxY - targetHeight,
                width: currentFrame.width,
                height: targetHeight
            )
            
            animatePanelFrame(to: newFrame)
        }
    }
    
    // MARK: - Position Management
    
    private func positionPanel(_ panel: NSPanel) {
        let savedX = UserDefaults.standard.double(forKey: positionXKey)
        let savedY = UserDefaults.standard.double(forKey: positionYKey)
        
        if savedX != 0 || savedY != 0 {
            // Restore saved position (with safety check)
            let origin = clampToScreen(point: NSPoint(x: savedX, y: savedY), size: panel.frame.size)
            panel.setFrameOrigin(origin)
        } else {
            // Default: bottom center of screen
            guard let screen = NSScreen.main else { return }
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        applySafeFrameIfNeeded(to: panel)
    }
    
    private func currentVisibleFrame(for frame: NSRect? = nil) -> NSRect {
        if let frame {
            let center = NSPoint(x: frame.midX, y: frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                return screen.visibleFrame
            }
        }
        
        if let panel, let screen = panel.screen {
            return screen.visibleFrame
        }
        
        return NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: maxWidth + screenEdgePadding * 2, height: defaultHeight + 240)
    }
    
    private func minimumPanelSize(collapsed: Bool) -> NSSize {
        NSSize(width: minWidth, height: collapsed ? collapsedMinHeight : minHeight)
    }

    private func maximumPanelSize(for screenFrame: NSRect, collapsed: Bool? = nil) -> NSSize {
        let minimumHeight = (collapsed ?? isCollapsed) ? collapsedMinHeight : minHeight
        let maxAllowedWidth = max(minWidth, min(maxWidth, screenFrame.width - screenEdgePadding * 2))
        let maxAllowedHeight = max(minimumHeight, screenFrame.height - screenEdgePadding * 2)
        return NSSize(width: maxAllowedWidth, height: maxAllowedHeight)
    }
    
    private func clampedPanelSize(width: CGFloat, height: CGFloat, screenFrame: NSRect, collapsed: Bool? = nil) -> NSSize {
        let minimumHeight = (collapsed ?? isCollapsed) ? collapsedMinHeight : minHeight
        let maxSize = maximumPanelSize(for: screenFrame, collapsed: collapsed)
        let clampedWidth = min(max(width, minWidth), maxSize.width)
        let clampedHeight = min(max(height, minimumHeight), maxSize.height)
        return NSSize(width: clampedWidth, height: clampedHeight)
    }
    
    private func restoredPanelSize() -> NSSize {
        let savedWidth = UserDefaults.standard.double(forKey: sizeWidthKey)
        let savedHeight = UserDefaults.standard.double(forKey: sizeHeightKey)
        let desiredWidth = savedWidth > 0 ? savedWidth : defaultWidth
        let desiredHeight = savedHeight > 0 ? savedHeight : defaultHeight
        return clampedPanelSize(width: desiredWidth, height: desiredHeight, screenFrame: currentVisibleFrame(), collapsed: false)
    }
    
    private func clampToScreen(point: NSPoint, size: NSSize) -> NSPoint {
        let screenFrame = currentVisibleFrame(for: NSRect(origin: point, size: size))
        
        let x = max(screenFrame.minX + screenEdgePadding,
                     min(point.x, screenFrame.maxX - size.width - screenEdgePadding))
        let y = max(screenFrame.minY + screenEdgePadding,
                     min(point.y, screenFrame.maxY - size.height - screenEdgePadding))
        
        return NSPoint(x: x, y: y)
    }
    
    private func sanitizedFrame(for frame: NSRect, collapsed: Bool? = nil) -> NSRect {
        let screenFrame = currentVisibleFrame(for: frame)
        let safeSize = clampedPanelSize(width: frame.width, height: frame.height, screenFrame: screenFrame, collapsed: collapsed)
        let safeOrigin = clampToScreen(point: frame.origin, size: safeSize)
        return NSRect(origin: safeOrigin, size: safeSize)
    }
    
    private func animatePanelFrame(to frame: NSRect) {
        guard let panel = panel else { return }
        let safeFrame = sanitizedFrame(for: frame, collapsed: isCollapsed)
        
        isAnimatingFrame = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(safeFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.isAnimatingFrame = false
            self?.savePosition()
        })
    }
    
    private func applySafeFrameIfNeeded(to panel: NSPanel) {
        let safeFrame = sanitizedFrame(for: panel.frame, collapsed: isCollapsed)
        panel.minSize = minimumPanelSize(collapsed: isCollapsed)
        panel.maxSize = maximumPanelSize(for: currentVisibleFrame(for: safeFrame), collapsed: isCollapsed)
        guard safeFrame != panel.frame else { return }
        
        isAnimatingFrame = true
        panel.setFrame(safeFrame, display: true)
        isAnimatingFrame = false
    }
    
    private func savePosition() {
        guard let frame = panel?.frame else { return }
        let persistedHeight = isCollapsed ? max(expandedHeight ?? defaultHeight, minHeight) : frame.height
        let persistedFrame = NSRect(
            x: frame.origin.x,
            y: isCollapsed ? frame.maxY - persistedHeight : frame.origin.y,
            width: frame.width,
            height: persistedHeight
        )
        let screenFrame = currentVisibleFrame(for: persistedFrame)
        let safeSize = clampedPanelSize(
            width: persistedFrame.width,
            height: persistedFrame.height,
            screenFrame: screenFrame,
            collapsed: false
        )
        let safeOrigin = clampToScreen(point: persistedFrame.origin, size: safeSize)
        
        UserDefaults.standard.set(safeOrigin.x, forKey: positionXKey)
        UserDefaults.standard.set(safeOrigin.y, forKey: positionYKey)
        UserDefaults.standard.set(safeSize.width, forKey: sizeWidthKey)
        UserDefaults.standard.set(safeSize.height, forKey: sizeHeightKey)
    }
    
    @objc private func panelDidMove(_ notification: Notification) {
        guard !isAnimatingFrame else { return }
        if let panel = panel {
            panel.maxSize = maximumPanelSize(for: currentVisibleFrame(for: panel.frame), collapsed: isCollapsed)
        }
        savePosition()
    }
    
    @objc private func panelDidResize(_ notification: Notification) {
        guard !isAnimatingFrame else { return }
        if let panel = panel {
            panel.maxSize = maximumPanelSize(for: currentVisibleFrame(for: panel.frame), collapsed: isCollapsed)
        }
        savePosition()
    }

    private func measuredCollapsedHeight(for panel: NSPanel) -> CGFloat {
        let screenFrame = currentVisibleFrame(for: panel.frame)
        let maximumHeight = min(collapsedMaxHeight, maximumPanelSize(for: screenFrame, collapsed: true).height)

        let measuredHeight: CGFloat
        if let hostingView = panel.contentView as? NSHostingView<FloatingOverlayView> {
            hostingView.layoutSubtreeIfNeeded()
            measuredHeight = hostingView.fittingSize.height
        } else if let contentView = panel.contentView {
            contentView.layoutSubtreeIfNeeded()
            measuredHeight = contentView.fittingSize.height
        } else {
            measuredHeight = collapsedTitleBarHeight
        }

        return Self.boundedCollapsedHeight(
            measuredHeight: measuredHeight,
            minimumHeight: collapsedMinHeight,
            maximumHeight: maximumHeight
        )
    }

    static func boundedCollapsedHeight(
        measuredHeight: CGFloat,
        minimumHeight: CGFloat,
        maximumHeight: CGFloat
    ) -> CGFloat {
        let safeMaximum = max(minimumHeight, maximumHeight)
        guard measuredHeight.isFinite else { return minimumHeight }
        return min(max(measuredHeight, minimumHeight), safeMaximum)
    }
    
    // MARK: - Space Key Monitor
    
    private func installKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            
            // Space key (keyCode 49)
            if event.keyCode == 49 {
                // Only handle when our panel is visible
                if self.panel?.isVisible == true {
                    Task { @MainActor in
                        if let vm = self.viewModel {
                            // 同传模式 + 正在录音 → Space 触发即时翻译
                            if vm.appSettings.simultaneousTranslation && vm.speechRecognizer.isRecording {
                                vm.triggerTranslation()
                            } else {
                                // 非同传模式 → Space 切换录音开关
                                vm.toggleRecording()
                            }
                        }
                    }
                    return nil // consume the event
                }
            }
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        removeKeyMonitor()
        NotificationCenter.default.removeObserver(self)
        panel?.close()
    }
}
