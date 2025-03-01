//
//  LibreTranslateServer.swift
//  damus
//
//  Created by Terry Yiu on 1/21/23.
//

import Foundation

enum LibreTranslateServer: String, CaseIterable, Identifiable, StringCodable {
    var id: String { self.rawValue }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var tag: String
        var displayName: String
        var url: String?
    }

    func to_string() -> String {
        return rawValue
    }

    init?(from string: String) {
        guard let libreTranslateServer = LibreTranslateServer(rawValue: string) else {
            return nil
        }
        self = libreTranslateServer
    }

    case argosopentech
    case terraprint
    case custom

    var model: Model {
        switch self {
        case .argosopentech:
            return .init(tag: self.rawValue, displayName: "translate.argosopentech.com", url: "https://translate.argosopentech.com")
        case .terraprint:
            return .init(tag: self.rawValue, displayName: "translate.terraprint.co", url: "https://translate.terraprint.co")
        case .custom:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("Custom", comment: "Dropdown option for selecting a custom translation server."), url: nil)
        }
    }

    static var allModels: [Model] {
        return Self.allCases.map { $0.model }
    }
}
