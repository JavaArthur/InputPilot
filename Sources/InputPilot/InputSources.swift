import AppKit
import Carbon

struct InputSource: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String

    var shortName: String {
        if language.hasPrefix("zh") { return "中" }
        if language.hasPrefix("ja") { return "日" }
        if language.hasPrefix("ko") { return "韩" }
        if language.hasPrefix("en") || id.contains("ABC") || id.contains("US") { return "EN" }
        return String(name.prefix(2))
    }
}

enum InputSources {
    static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static func available() -> [InputSource] {
        let filter = [kTISPropertyInputSourceCategory!: kTISCategoryKeyboardInputSource!,
                      kTISPropertyInputSourceIsSelectCapable!: kCFBooleanTrue!,
                      kTISPropertyInputSourceIsEnabled!: kCFBooleanTrue!] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        var seen = Set<String>()
        return list.compactMap { source in
            guard let id = string(source, kTISPropertyInputSourceID), seen.insert(id).inserted else { return nil }
            var language = ""
            if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
                language = (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String])?.first ?? ""
            }
            return InputSource(id: id, name: string(source, kTISPropertyLocalizedName) ?? id, language: language)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return string(source, kTISPropertyInputSourceID)
    }

    static func select(_ id: String) -> OSStatus {
        let filter = [kTISPropertyInputSourceID!: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return OSStatus(-50) }
        return TISSelectInputSource(source)
    }
}
