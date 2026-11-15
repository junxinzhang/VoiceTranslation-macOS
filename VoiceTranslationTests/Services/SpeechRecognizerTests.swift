//
//  SpeechRecognizerTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-11.
//

import XCTest
import Speech
import Combine
@testable import VoiceTranslation

final class SpeechRecognizerTests: XCTestCase {
    
    var speechRecognizer: SpeechRecognizer!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        speechRecognizer = SpeechRecognizer()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        speechRecognizer.stopRecording()
        speechRecognizer = nil
        cancellables = nil
    }
    
    // MARK: - 初始化和配置测试
    
    func testSpeechRecognizerInitialization() throws {
        XCTAssertNotNil(speechRecognizer)
        XCTAssertFalse(speechRecognizer.isRecording)
        XCTAssertFalse(speechRecognizer.isListening)
        XCTAssertEqual(speechRecognizer.recognizedText, "")
    }
    
    func testLanguageConfiguration() throws {
        // 调用 setLanguage 后对象仍可用
        speechRecognizer.setLanguage("en-US")
        XCTAssertNotNil(speechRecognizer)

        speechRecognizer.setLanguage("zh-CN")
        XCTAssertNotNil(speechRecognizer)
    }
    
    // MARK: - 权限测试
    
    func testAuthorizationRequest() throws {
        let expectation = self.expectation(description: "Authorization request")
        
        speechRecognizer.$authorizationStatus
            .dropFirst() // 跳过初始值
            .sink { status in
                XCTAssertTrue([.authorized, .denied, .restricted, .notDetermined].contains(status))
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        speechRecognizer.requestAuthorization()
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - 录音状态测试
    
    func testRecordingStateManagement() throws {
        // 初始状态
        XCTAssertFalse(speechRecognizer.isRecording)
        XCTAssertFalse(speechRecognizer.isListening)

        // 在权限被拒绝的情况下尝试录音（应该不会开始录音）
        speechRecognizer.authorizationStatus = .denied
        speechRecognizer.startRecording()
        XCTAssertFalse(speechRecognizer.isRecording, "Recording should not start when authorization is denied")
        
        // 停止录音（即使没有开始也应该安全）
        speechRecognizer.stopRecording()
        XCTAssertFalse(speechRecognizer.isRecording)
        XCTAssertFalse(speechRecognizer.isListening)
    }
    
    func testMultipleStartStopCalls() throws {
        // 连续调用startRecording应该安全
        speechRecognizer.startRecording()
        speechRecognizer.startRecording()
        speechRecognizer.startRecording()
        
        // 连续调用stopRecording应该安全
        speechRecognizer.stopRecording()
        speechRecognizer.stopRecording()
        speechRecognizer.stopRecording()
        
        XCTAssertFalse(speechRecognizer.isRecording)
        XCTAssertFalse(speechRecognizer.isListening)
    }
    
    // MARK: - 文本清理和状态重置测试
    
    func testTextClearing() throws {
        // 设置一些识别文本
        speechRecognizer.recognizedText = "Test text"
        XCTAssertEqual(speechRecognizer.recognizedText, "Test text")
        
        // 停止录音应该保留文本
        speechRecognizer.stopRecording()
        XCTAssertEqual(speechRecognizer.recognizedText, "Test text")
    }
    
    func testStateResetOnStop() throws {
        let expectation = self.expectation(description: "State reset")
        
        speechRecognizer.$isRecording
            .sink { isRecording in
                if !isRecording {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        speechRecognizer.stopRecording()
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertFalse(speechRecognizer.isRecording)
        XCTAssertFalse(speechRecognizer.isListening)
    }
    
    // MARK: - 资源管理测试
    
    func testResourceCleanup() throws {
        // 创建语音识别器并尝试开始录音
        let recognizer = SpeechRecognizer()
        recognizer.startRecording()
        
        // 手动停止
        recognizer.stopRecording()
        
        XCTAssertFalse(recognizer.isRecording)
        XCTAssertFalse(recognizer.isListening)
    }
    
    func testDeinitialization() throws {
        weak var weakRecognizer: SpeechRecognizer?
        
        autoreleasepool {
            let recognizer = SpeechRecognizer()
            weakRecognizer = recognizer
            recognizer.startRecording()
            // 对象销毁时应该自动清理资源
        }
        
        // 验证对象被正确释放
        XCTAssertNil(weakRecognizer, "SpeechRecognizer should be deallocated")
    }
    
    // MARK: - 边界条件测试
    
    func testEmptyLanguageCode() throws {
        speechRecognizer.setLanguage("")
        // 应该不会崩溃
        XCTAssertNotNil(speechRecognizer)
    }
    
    func testInvalidLanguageCode() throws {
        speechRecognizer.setLanguage("invalid-locale")
        // 应该不会崩溃
        XCTAssertNotNil(speechRecognizer)
    }
    
    func testVeryLongLanguageCode() throws {
        let longCode = String(repeating: "a", count: 1000)
        speechRecognizer.setLanguage(longCode)
        // 应该不会崩溃
        XCTAssertNotNil(speechRecognizer)
    }
}