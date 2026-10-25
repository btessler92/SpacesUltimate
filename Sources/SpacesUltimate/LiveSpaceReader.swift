import AppKit
import Darwin

/// Isolates the read-only, undocumented WindowServer query used for current Space
/// identity. Saved Dock preferences and window membership can both be stale.
@MainActor
final class LiveSpaceReader {
    struct Display: Equatable {
        var identifier: String
        var currentStableID: String
        // Nil means the inventory is unavailable or malformed, not an empty display.
        var spaces: [ManagedSpace]? = nil
    }

    struct ManagedSpace: Equatable {
        var stableID: String
        var type: Int
        var appName: String? = nil
    }

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private let functions: (MainConnection, CopySpaces)?

    init() {
        guard ProcessInfo.processInfo.environment["SPACESULTIMATE_DISABLE_LIVE_SPACES"] != "1",
              let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL),
              let connection = dlsym(library, "SLSMainConnectionID"),
              let copy = dlsym(library, "SLSCopyManagedDisplaySpaces") else {
            functions = nil
            return
        }
        // Keep the library loaded for the lifetime of the process/function pointers.
        functions = (unsafeBitCast(connection, to: MainConnection.self),
                     unsafeBitCast(copy, to: CopySpaces.self))
    }

    func read() -> [Display] {
        guard let (connection, copy) = functions,
              let result = copy(connection()) else { return [] }
        return Self.parse(result.takeRetainedValue())
    }

    static func parse(_ value: Any) -> [Display] {
        guard let records = value as? [[String: Any]] else { return [] }
        return records.compactMap { record in
            guard let identifier = record["Display Identifier"] as? String, !identifier.isEmpty,
                  let current = record["Current Space"] as? [String: Any],
                  let stableID = current["uuid"] as? String, !stableID.isEmpty else { return nil }
            let rawSpaces = record["Spaces"] as? [[String: Any]]
            let parsed = rawSpaces?.compactMap { space -> ManagedSpace? in
                guard let uuid = space["uuid"] as? String, !uuid.isEmpty,
                      let type = space["type"] as? Int, [0, 4].contains(type) else { return nil }
                let tiles = (space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] ?? []
                var names = tiles.compactMap { $0["appName"] as? String }.filter { !$0.isEmpty }
                if names.isEmpty, let name = space["appName"] as? String, !name.isEmpty { names = [name] }
                if names.isEmpty, type == 4, let pid = space["pid"] as? Int32,
                   let name = NSRunningApplication(processIdentifier: pid)?.localizedName { names = [name] }
                var seen = Set<String>()
                names = names.filter { seen.insert($0).inserted }
                return ManagedSpace(stableID: uuid, type: type,
                                    appName: names.isEmpty ? nil : names.joined(separator: " + "))
            }
            let complete = parsed != nil && parsed?.count == rawSpaces?.count && !(parsed?.isEmpty ?? true)
            return Display(identifier: identifier, currentStableID: stableID, spaces: complete ? parsed : nil)
        }
    }

    static func currentStableID(
        for displayUUID: String?,
        separateSpaces: Bool,
        in displays: [Display]
    ) -> String? {
        if let displayUUID {
            let matches = displays.filter { $0.identifier.caseInsensitiveCompare(displayUUID) == .orderedSame }
            // Reject ambiguous records rather than borrowing another monitor's Desktop.
            if matches.count == 1 { return matches[0].currentStableID }
            if !matches.isEmpty { return nil }
        }
        // With shared Spaces, WindowServer may use one "Main" record for all screens.
        if !separateSpaces, displays.count == 1 { return displays[0].currentStableID }
        return nil
    }
}
