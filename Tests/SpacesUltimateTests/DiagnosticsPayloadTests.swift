import XCTest
@testable import SpacesUltimate

@MainActor
final class DiagnosticsPayloadTests: XCTestCase {
    func testSpaceAndBindingJSONPreserveNotesAndDistinguishMissingIdentityFromDisplayName() throws {
        let space = SpaceMetadata(id: "order-4", stableID: nil, orderIndex: 4,
                                  name: "  Focus  ", colorHex: "#123456", icon: "F",
                                  note: "First line\nSecond line", shortcut: "Control+4", assignedApps: [])
        let binding = SpaceNameBindingSummary(orderIndex: 4, displayName: space.displayName,
                                             stableID: nil, mode: .orderFallback,
                                             rememberedStableIDCount: 1, repairCandidateName: "Writing")
        let data = try JSONSerialization.data(withJSONObject: [
            "space": DiagnosticsPayload.space(space), "binding": DiagnosticsPayload.nameBinding(binding)
        ])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        XCTAssertEqual(json["space"]?["name"] as? String, "Focus")
        XCTAssertEqual(json["space"]?["rawName"] as? String, "  Focus  ")
        XCTAssertEqual(json["space"]?["note"] as? String, "First line\nSecond line")
        XCTAssertEqual(json["space"]?["color"] as? String, "#123456")
        XCTAssertTrue(json["space"]?["stableID"] is NSNull)
        XCTAssertTrue(json["binding"]?["stableID"] is NSNull)
        XCTAssertEqual(json["binding"]?["mode"] as? String, "order-fallback")
        XCTAssertEqual(json["binding"]?["repairCandidateName"] as? String, "Writing")
    }

    func testRuleJSONKeepsTimestampPrecisionAndDuplicateAssignments() throws {
        let snapshot = RuleSuggestionSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0.125),
            matches: [RuleMatch(appName: "Editor", spaceOrderIndex: 4, spaceName: "Focus", windowCount: 2)],
            unassignedVisibleApps: ["Browser"], duplicateAssignments: ["editor": [4, 7]])
        let data = try JSONSerialization.data(withJSONObject: DiagnosticsPayload.rules(snapshot))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["generatedAt"] as? String, "1970-01-01T00:00:00.125Z")
        XCTAssertEqual(json["duplicateAssignments"] as? [String: [Int]], ["editor": [4, 7]])
        XCTAssertEqual(json["unassignedVisibleApps"] as? [String], ["Browser"])
        let match = try XCTUnwrap((json["matches"] as? [[String: Any]])?.first)
        XCTAssertEqual(match["app"] as? String, "Editor")
        XCTAssertEqual(match["space"] as? Int, 4)
        XCTAssertEqual(match["windowCount"] as? Int, 2)
    }
}
