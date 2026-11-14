import Foundation

/// Only portable writing/library settings enter backups. Account and server secrets never do.
public enum PortablePreferences {
    public static func filtered(_ values: [String: JSONValue]) -> [String: JSONValue] {
        let fixed: Set<String> = ["activeProfile", "libraryProfiles", "profiles", "folders", "profileName",
            "profileTheme", "profileIcon", "profileAppearances", "libraryView", "librarySort",
            "performanceMode", "continuousPages", "fingerDrawing", "penButtonToggle", "defaultPenColor",
            "defaultPaperColor", "defaultLineCount", "penColor", "highlightColor", "penWidth", "highlightWidth", "eraserSize"]
        return values.filter { key, value in
            guard key.utf8.count <= 256 else { return false }
            let palette = (0..<6).contains { key == "penPalette.\($0)" } || (0..<5).contains { key == "highlightPalette.\($0)" }
            guard fixed.contains(key) || palette || key.hasPrefix("profileFolders.") else { return false }
            guard let data = try? value.data(), data.count <= 1024 * 1024 else { return false }
            return true
        }
    }
}
