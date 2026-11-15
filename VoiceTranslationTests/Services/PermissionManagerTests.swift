//
//  PermissionManagerTests.swift
//  VoiceTranslationTests
//
//  Created by Claude on 2025-08-12.
//

import XCTest
import Speech
import AVFoundation
@testable import VoiceTranslation

@MainActor
final class PermissionManagerTests: XCTestCase {
    
    var permissionManager: PermissionManager!
    
    override func setUp() {
        super.setUp()
        permissionManager = PermissionManager.shared
    }
    
    override func tearDown() {
        permissionManager.resetCache()
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testPermissionManagerSingleton() {
        let instance1 = PermissionManager.shared
        let instance2 = PermissionManager.shared
        
        XCTAssertTrue(instance1 === instance2, "PermissionManager 应该是单例")
    }
    
    // MARK: - Permission Status Tests
    
    func testInitialPermissionStates() {
        // 初始状态应该是 notDetermined
        XCTAssertEqual(permissionManager.microphoneStatus, .notDetermined, "麦克风权限初始状态应该是 notDetermined")
        XCTAssertEqual(permissionManager.speechRecognitionStatus, .notDetermined, "语音识别权限初始状态应该是 notDetermined")
        XCTAssertEqual(permissionManager.screenRecordingStatus, .notDetermined, "屏幕录制权限初始状态应该是 notDetermined")
    }
    
    func testPermissionStatusConversion() {
        let testCases: [(PermissionStatus, Bool)] = [
            (.notDetermined, false),
            (.granted, true),
            (.denied, false),
            (.restricted, false),
            (.unavailable, false)
        ]
        
        for (status, expectedAuthorized) in testCases {
            XCTAssertEqual(status.isAuthorized, expectedAuthorized,
                          "PermissionStatus.\(status) 的 isAuthorized 应该是 \(expectedAuthorized)")
        }
    }
    
    // MARK: - Permission Checking Tests
    
    func testCheckAllPermissions() async {
        let expectation = XCTestExpectation(description: "检查所有权限完成")
        
        // 监听权限状态变更
        let cancellable = permissionManager.permissionStatusChanges
            .collect(3) // 等待3个权限的状态变更
            .sink { changes in
                XCTAssertEqual(changes.count, 3, "应该有3个权限状态变更")
                
                let types = changes.map { $0.type }
                XCTAssertTrue(types.contains(.microphone), "应该包含麦克风权限检查")
                XCTAssertTrue(types.contains(.speechRecognition), "应该包含语音识别权限检查")
                XCTAssertTrue(types.contains(.screenRecording), "应该包含屏幕录制权限检查")
                
                expectation.fulfill()
            }
        
        await permissionManager.checkAllPermissions()
        
        await fulfillment(of: [expectation], timeout: 10.0)
        cancellable.cancel()
    }
    
    func testPermissionCaching() async {
        // 第一次检查
        let status1 = await permissionManager.checkMicrophonePermission()
        let timestamp1 = Date()
        
        // 立即第二次检查（应该使用缓存）
        let status2 = await permissionManager.checkMicrophonePermission()
        let timestamp2 = Date()
        
        // 验证状态一致
        XCTAssertEqual(status1, status2, "缓存期间内权限状态应该一致")
        
        // 验证第二次检查很快（使用了缓存）
        let timeDiff = timestamp2.timeIntervalSince(timestamp1)
        XCTAssertLessThan(timeDiff, 1.0, "缓存的权限检查应该很快完成")
    }
    
    func testPermissionCacheReset() async {
        // 第一次检查
        _ = await permissionManager.checkMicrophonePermission()
        
        // 重置缓存
        permissionManager.resetCache()
        
        // 再次检查（应该重新请求）
        let status = await permissionManager.checkMicrophonePermission()
        
        // 验证能正常获取状态
        XCTAssertTrue([.granted, .denied, .notDetermined, .restricted].contains(status),
                     "重置缓存后应该能正常获取权限状态")
    }
    
    // MARK: - System Audio Validation Tests
    
    @available(macOS 12.3, *)
    func testSystemAudioValidation() async {
        let (hasPermission, canAccessContent, errorMessage) = await permissionManager.validateSystemAudioCapability()
        
        // 验证返回值的有效性
        if hasPermission {
            XCTAssertTrue(canAccessContent || errorMessage != nil,
                         "如果有权限但无法访问内容，应该有错误消息")
        } else {
            XCTAssertFalse(canAccessContent, "没有权限时不应该能访问内容")
        }
        
        print("系统音频验证结果: 权限=\(hasPermission), 内容访问=\(canAccessContent), 错误=\(errorMessage ?? "无")")
    }
    
    // MARK: - Permission Guide Tests
    
    func testPermissionGuideDisplay() {
        // 显示权限指导
        permissionManager.showPermissionGuideFor(.microphone)
        
        XCTAssertTrue(permissionManager.showPermissionGuide, "应该显示权限指导")
        XCTAssertEqual(permissionManager.pendingPermissionType, .microphone, "应该设置正确的权限类型")
        
        // 隐藏权限指导
        permissionManager.hidePermissionGuide()
        
        XCTAssertFalse(permissionManager.showPermissionGuide, "应该隐藏权限指导")
        XCTAssertNil(permissionManager.pendingPermissionType, "应该清除权限类型")
    }
    
    func testPermissionSummary() {
        let summary = permissionManager.getPermissionSummary()
        
        XCTAssertFalse(summary.isEmpty, "权限摘要不应该为空")
        XCTAssertTrue(summary.contains("权限状态摘要"), "摘要应该包含标题")
        XCTAssertTrue(summary.contains("麦克风"), "摘要应该包含麦克风权限")
        XCTAssertTrue(summary.contains("语音识别"), "摘要应该包含语音识别权限")
        XCTAssertTrue(summary.contains("屏幕录制"), "摘要应该包含屏幕录制权限")
    }
    
    // MARK: - Performance Tests
    
    func testPermissionCheckPerformance() async {
        // 测量权限检查的性能
        let startTime = Date()
        
        await permissionManager.checkAllPermissions()
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        XCTAssertLessThan(duration, 5.0, "完整权限检查应该在5秒内完成")
        print("权限检查耗时: \(duration) 秒")
    }
    
    func testCachedPermissionCheckPerformance() async {
        // 首次检查（建立缓存）
        _ = await permissionManager.checkMicrophonePermission()
        
        // 测量缓存的权限检查性能
        let startTime = Date()
        
        _ = await permissionManager.checkMicrophonePermission()
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        XCTAssertLessThan(duration, 0.1, "缓存的权限检查应该在0.1秒内完成")
        print("缓存权限检查耗时: \(duration) 秒")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidPermissionType() {
        // 测试无效的权限类型处理
        let summary = permissionManager.getPermissionSummary()
        XCTAssertNotNil(summary, "即使在异常情况下也应该返回权限摘要")
    }
    
    func testPermissionStatusChangePublisher() {
        let expectation = XCTestExpectation(description: "权限状态变更通知")
        
        let cancellable = permissionManager.permissionStatusChanges
            .first()
            .sink { change in
                XCTAssertNotNil(change.type, "权限变更应该包含类型")
                XCTAssertNotNil(change.timestamp, "权限变更应该包含时间戳")
                expectation.fulfill()
            }
        
        // 触发权限检查以产生状态变更
        Task {
            await permissionManager.checkMicrophonePermission()
        }
        
        wait(for: [expectation], timeout: 5.0)
        cancellable.cancel()
    }
    
    // MARK: - System Preferences Tests
    
    func testOpenSystemPreferences() {
        // 测试打开系统偏好设置（不能真实打开，但可以测试方法调用）
        XCTAssertNoThrow(
            permissionManager.openSystemPreferencesForPermission(.microphone),
            "打开麦克风系统偏好设置不应该抛出异常"
        )
        
        XCTAssertNoThrow(
            permissionManager.openSystemPreferencesForPermission(.speechRecognition),
            "打开语音识别系统偏好设置不应该抛出异常"
        )
        
        XCTAssertNoThrow(
            permissionManager.openSystemPreferencesForPermission(.screenRecording),
            "打开屏幕录制系统偏好设置不应该抛出异常"
        )
    }
}