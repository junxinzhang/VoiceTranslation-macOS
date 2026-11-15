//
//  APIProvider.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-09-27.
//

import Foundation

enum APIProvider: String, CaseIterable {
    case openAI = "OpenAI"
    case customAPI = "Custom API"

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI (GPT-4o-mini)"
        case .customAPI:
            return "Custom API (OpenAI Compatible)"
        }
    }

    var baseURL: String {
        switch self {
        case .openAI:
            return Constants.OpenAI.baseURL
        case .customAPI:
            return Constants.CustomAPI.defaultBaseURL
        }
    }

    var model: String {
        switch self {
        case .openAI:
            return Constants.OpenAI.model
        case .customAPI:
            return Constants.CustomAPI.defaultModel
        }
    }

    var requiresAPIKey: Bool {
        return true
    }
}
