//
//  VoiceTranslationApp.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import SwiftUI

@main
struct VoiceTranslationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        // 移除windowResizability以兼容macOS 12
        .commands {
            CommandGroup(replacing: .newItem) {
                // 移除 "New" 菜单项
            }
            
            CommandGroup(after: .appInfo) {
                Button("设置...") {
                    // 这里可以添加全局设置快捷键的逻辑
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 应用启动时的配置
        setupWindow()
        setupMenuBar()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 应用退出时的清理工作
        print("应用正在退出...")
    }
    
    // MARK: - Private Methods
    
    private func setupWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        // 设置窗口属性
        window.title = "语音实时翻译"
        window.setContentSize(NSSize(width: Constants.UI.minWindowWidth, height: Constants.UI.minWindowHeight))
        window.minSize = NSSize(width: Constants.UI.minWindowWidth, height: Constants.UI.minWindowHeight)
        
        // 居中显示窗口
        window.center()
        
        // 设置窗口样式
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        
        // 确保窗口可以成为关键窗口
        window.makeKeyAndOrderFront(nil)
    }
    
    private func setupMenuBar() {
        // 自定义菜单栏配置（如果需要）
        guard let _ = NSApplication.shared.mainMenu else { return }
        
        // 可以在这里添加自定义菜单项
        // 例如：添加快速设置菜单
    }
}

// MARK: - Window Delegate

class WindowDelegate: NSObject, NSWindowDelegate {
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 窗口关闭前的确认逻辑
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时的清理工作
        NSApplication.shared.terminate(nil)
    }
}