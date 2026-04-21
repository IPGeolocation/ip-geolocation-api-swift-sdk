import Foundation

public enum Language: String, Sendable, Codable, CaseIterable {
    case en
    case de
    case ru
    case ja
    case fr
    case cn
    case es
    case cs
    case it
    case ko
    case fa
    case pt

    var code: String { rawValue }
}
