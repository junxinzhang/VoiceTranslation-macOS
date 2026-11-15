//
//  FloatingOverlayWindowControllerTests.swift
//  VoiceTranslationTests
//
//  Created on 2026-03-12.
//

import XCTest
@testable import VoiceTranslation

final class FloatingOverlayWindowControllerTests: XCTestCase {

    func testBoundedCollapsedHeightUsesMinimumForInvalidMeasuredHeight() {
        let height = FloatingOverlayWindowController.boundedCollapsedHeight(
            measuredHeight: .nan,
            minimumHeight: 88,
            maximumHeight: 260
        )

        XCTAssertEqual(height, 88)
    }

    func testBoundedCollapsedHeightClampsBelowMinimum() {
        let height = FloatingOverlayWindowController.boundedCollapsedHeight(
            measuredHeight: 52,
            minimumHeight: 88,
            maximumHeight: 260
        )

        XCTAssertEqual(height, 88)
    }

    func testBoundedCollapsedHeightClampsAboveMaximum() {
        let height = FloatingOverlayWindowController.boundedCollapsedHeight(
            measuredHeight: 420,
            minimumHeight: 88,
            maximumHeight: 260
        )

        XCTAssertEqual(height, 260)
    }

    func testBoundedCollapsedHeightKeepsValueWithinRange() {
        let height = FloatingOverlayWindowController.boundedCollapsedHeight(
            measuredHeight: 172,
            minimumHeight: 88,
            maximumHeight: 260
        )

        XCTAssertEqual(height, 172)
    }
}
