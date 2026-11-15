//
//  VoiceTranslationTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-11.
//

import XCTest
import Combine
@testable import VoiceTranslation

final class VoiceTranslationTests: XCTestCase {
    
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        cancellables = Set<AnyCancellable>()
        
        // 清理UserDefaults测试数据
        let testDefaults = UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!
        testDefaults.removeObject(forKey: Constants.UserDefaults.openAIApiKey)
        testDefaults.removeObject(forKey: Constants.UserDefaults.selectedLanguageDirection)
        testDefaults.removeObject(forKey: Constants.UserDefaults.keepHistory)
        testDefaults.removeObject(forKey: "Translation_History")
    }
    
    override func tearDownWithError() throws {
        cancellables = nil
    }
    
    // MARK: - 测试性能和内存管理
    
    func testPerformanceExample() throws {
        // 测试主要功能的性能表现
        self.measure {
            let viewModel = MainViewModel()
            let _ = viewModel.speechRecognizer
            let _ = viewModel.translationService
        }
    }
    
    func testMemoryLeakage() throws {
        weak var weakViewModel: MainViewModel?
        
        autoreleasepool {
            let viewModel = MainViewModel()
            weakViewModel = viewModel
            // 模拟一些操作
            viewModel.clearText()
            viewModel.switchLanguageDirection()
        }
        
        // 验证对象被正确释放
        XCTAssertNil(weakViewModel, "MainViewModel should be deallocated")
    }
}