import XCTest
@testable import SpacesUltimate

@MainActor
final class SpaceStoreReconciliationTests: XCTestCase {
    func testSpaceMetadataWithoutNoteDefaultsToEmptyString() throws {
        let json = """
        {
          "id": "space-1",
          "stableID": "stable-1",
          "orderIndex": 1,
          "name": "Focus",
          "colorHex": "#2F80ED",
          "icon": "F",
          "shortcut": "Control+1",
          "assignedApps": ["Terminal"]
        }
        """

        let space = try JSONDecoder().decode(SpaceMetadata.self, from: Data(json.utf8))

        XCTAssertEqual(space.note, "")
        XCTAssertEqual(space.shortcut, "Control+1")
    }

    func testCustomNamesFollowStableIDsWhenSpacesReorder() throws {
        try withTemporaryStore { store in
            store.reconcile(with: detected("space-a", "space-b", "space-c"))
            rename(space: 1, to: "Research", in: store)
            rename(space: 2, to: "Writing", in: store)

            store.reconcile(with: detected("space-b", "space-a", "space-c"))

            XCTAssertEqual(store.space(orderIndex: 1).stableID, "space-b")
            XCTAssertEqual(store.space(orderIndex: 1).name, "Writing")
            XCTAssertEqual(store.space(orderIndex: 2).stableID, "space-a")
            XCTAssertEqual(store.space(orderIndex: 2).name, "Research")
        }
    }

    func testGeneratedColorsRefreshWhenStableSpacesReorder() throws {
        try withTemporaryStore { store in
            store.reconcile(with: detected("space-a", "space-b", "space-c"))

            store.reconcile(with: detected("space-b", "space-a", "space-c"))

            XCTAssertEqual(store.spaces.map(\.colorHex), (1...3).map { SpaceConfig.spectrumColorHex(orderIndex: $0, totalCount: 3) })
            XCTAssertEqual(store.space(orderIndex: 1).stableID, "space-b")
            XCTAssertEqual(store.space(orderIndex: 2).stableID, "space-a")
        }
    }

    func testGeneratedColorsRefreshWhenDesktopCountChanges() throws {
        try withTemporaryStore { store in
            store.reconcile(with: detected("space-a", "space-b", "space-c", "space-d"))
            XCTAssertEqual(store.spaces.map(\.colorHex), (1...4).map { SpaceConfig.spectrumColorHex(orderIndex: $0, totalCount: 4) })

            store.reconcile(with: detected("space-a", "space-b", "space-c", "space-d", "space-e"))

            XCTAssertEqual(store.spaces.map(\.colorHex), (1...5).map { SpaceConfig.spectrumColorHex(orderIndex: $0, totalCount: 5) })
        }
    }

    func testNamesSurviveStableIDOutageAndUseLatestFallbackEditWhenIDsReturn() throws {
        try withTemporaryStore { store in
            store.reconcile(with: detected("space-a", "space-b"))
            rename(space: 1, to: "Research", in: store)

            store.reconcile(with: [
                DetectedSpace(stableID: nil, orderIndex: 1),
                DetectedSpace(stableID: nil, orderIndex: 2)
            ])
            XCTAssertNil(store.space(orderIndex: 1).stableID)
            XCTAssertEqual(store.space(orderIndex: 1).name, "Research")

            rename(space: 1, to: "Lab", in: store)
            store.reconcile(with: detected("space-a", "space-b"))

            XCTAssertEqual(store.space(orderIndex: 1).stableID, "space-a")
            XCTAssertEqual(store.space(orderIndex: 1).name, "Lab")
        }
    }

    func testRemovedStableSpaceRecoversRememberedNameWhenItReappears() throws {
        try withTemporaryStore { store in
            store.reconcile(with: detected("space-a", "space-b", "space-c"))
            rename(space: 3, to: "Deep Work", in: store)

            store.reconcile(with: detected("space-a", "space-b"))
            XCTAssertEqual(store.spaces.count, 2)

            store.reconcile(with: detected("space-a", "space-b", "space-c"))

            XCTAssertEqual(store.spaces.count, 3)
            XCTAssertEqual(store.space(orderIndex: 3).stableID, "space-c")
            XCTAssertEqual(store.space(orderIndex: 3).name, "Deep Work")
        }
    }

    func testAutomaticDesktopNamesRenumberButCustomNamesSurviveReorder() throws {
        try withTemporaryStore { store in
            store.reconcile(with: detected("space-a", "space-b"))
            rename(space: 2, to: "Writing", in: store)

            store.reconcile(with: detected("space-b", "space-a"))

            XCTAssertEqual(store.space(orderIndex: 1).stableID, "space-b")
            XCTAssertEqual(store.space(orderIndex: 1).name, "Writing")
            XCTAssertEqual(store.space(orderIndex: 2).stableID, "space-a")
            XCTAssertEqual(store.space(orderIndex: 2).name, "Desktop 2")
        }
    }

    func testMalformedImportedConfigNormalizesDuplicateIDsAndOrder() throws {
        try withTemporaryConfig(
            SpaceConfig(
                spaces: [
                    metadata(id: "duplicate", stableID: "space-a", orderIndex: 5, name: "Research"),
                    metadata(id: "duplicate", stableID: "space-b", orderIndex: 5, name: "Writing")
                ],
                stableSpaceHistory: [
                    "": metadata(id: "", stableID: "", orderIndex: 0, name: "Broken"),
                    "space-a": metadata(id: "wrong", stableID: nil, orderIndex: 0, name: "Research")
                ],
                lastKnownActiveOrderIndex: 99,
                overviewShortcut: "",
                riskyMethodsEnabled: false,
                settings: .defaults
            )
        ) { store in
            XCTAssertEqual(store.spaces.map(\.orderIndex), [1, 2])
            XCTAssertEqual(Set(store.spaces.map(\.id)).count, 2)
            XCTAssertEqual(store.config.lastKnownActiveOrderIndex, 2)
            XCTAssertNil(store.config.stableSpaceHistory[""])
            XCTAssertEqual(store.config.stableSpaceHistory["space-a"]?.stableID, "space-a")
            XCTAssertEqual(store.config.stableSpaceHistory["space-a"]?.id, "space-a")
            XCTAssertEqual(store.config.stableSpaceHistory["space-a"]?.orderIndex, 1)
        }
    }

    func testDefaultColorsSpanSpectrumWithoutRepeating() {
        let colors = SpaceConfig.defaults(spaceCount: 10).spaces.map(\.colorHex)
        let first = NSColor(hex: colors[0])
        let last = NSColor(hex: colors[9])

        XCTAssertEqual(Set(colors).count, 10)
        XCTAssertEqual(colors.first, SpaceConfig.spectrumColorHex(orderIndex: 1, totalCount: 10))
        XCTAssertEqual(colors.last, SpaceConfig.spectrumColorHex(orderIndex: 10, totalCount: 10))
        XCTAssertNotEqual(colors.first, colors.last)
        XCTAssertGreaterThan(first.redComponent, first.blueComponent)
        XCTAssertGreaterThan(last.blueComponent, last.redComponent)
    }

    func testRepeatedLegacyGeneratedColorsMigrateToSpectrum() throws {
        let legacyPalette = ["#2F80ED", "#27AE60", "#EB5757", "#F2C94C", "#9B51E0", "#00A8A8"]
        let legacyConfig = SpaceConfig(
            spaces: (1...10).map { index in
                metadata(
                    id: "order-\(index)",
                    stableID: nil,
                    orderIndex: index,
                    name: "Desktop \(index)",
                    colorHex: legacyPalette[(index - 1) % legacyPalette.count]
                )
            },
            lastKnownActiveOrderIndex: 1,
            overviewShortcut: "",
            riskyMethodsEnabled: false,
            settings: .defaults
        )

        try withTemporaryConfig(legacyConfig) { store in
            let colors = store.spaces.map(\.colorHex)

            XCTAssertEqual(Set(colors).count, 10)
            XCTAssertEqual(colors, (1...10).map { SpaceConfig.spectrumColorHex(orderIndex: $0, totalCount: 10) })
        }
    }

    func testRepeatedStaleColorsMigrateToSpectrum() throws {
        let staleConfig = SpaceConfig(
            spaces: (1...8).map { index in
                metadata(
                    id: "order-\(index)",
                    stableID: nil,
                    orderIndex: index,
                    name: "Desktop \(index)",
                    colorHex: index < 4 ? "#F15A53" : "#E663EF"
                )
            },
            lastKnownActiveOrderIndex: 1,
            overviewShortcut: "",
            riskyMethodsEnabled: false,
            settings: .defaults
        )

        try withTemporaryConfig(staleConfig) { store in
            XCTAssertEqual(store.spaces.map(\.colorHex), (1...8).map { SpaceConfig.spectrumColorHex(orderIndex: $0, totalCount: 8) })
        }
    }

    func testCustomColorSetIsNotMigrated() throws {
        let customConfig = SpaceConfig(
            spaces: [
                metadata(id: "one", stableID: nil, orderIndex: 1, name: "One", colorHex: "#111111"),
                metadata(id: "two", stableID: nil, orderIndex: 2, name: "Two", colorHex: "#222222")
            ],
            lastKnownActiveOrderIndex: 1,
            overviewShortcut: "",
            riskyMethodsEnabled: false,
            settings: .defaults
        )

        try withTemporaryConfig(customConfig) { store in
            XCTAssertEqual(store.spaces.map(\.colorHex), ["#111111", "#222222"])
        }
    }

    func testBindingSummariesExposeStableIDAndOrderFallbackState() throws {
        try withTemporaryStore { store in
            store.reconcile(with: detected("space-a", "space-b"))
            store.reconcile(with: [
                DetectedSpace(stableID: nil, orderIndex: 1),
                DetectedSpace(stableID: "space-b", orderIndex: 2)
            ])

            let summaries = store.nameBindingSummaries()

            XCTAssertEqual(summaries[0].mode, .orderFallback)
            XCTAssertNil(summaries[0].stableID)
            XCTAssertEqual(summaries[0].rememberedStableIDCount, 1)
            XCTAssertEqual(summaries[1].mode, .stableID)
            XCTAssertEqual(summaries[1].stableID, "space-b")
        }
    }

    func testRepairOrderFallbackNamesRestoresRememberedCustomMetadataOnlyForAutomaticNames() throws {
        try withTemporaryStore { store in
            store.reconcile(with: detected("space-a", "space-b"))
            rename(space: 1, to: "Research", in: store)
            var second = store.space(orderIndex: 2)
            second.name = "Writing"
            second.icon = "W"
            second.colorHex = "#27AE60"
            second.assignedApps = ["Notes"]
            store.update(second)

            store.reconcile(with: [
                DetectedSpace(stableID: nil, orderIndex: 1),
                DetectedSpace(stableID: nil, orderIndex: 2)
            ])
            rename(space: 2, to: "Manual Override", in: store)

            var first = store.space(orderIndex: 1)
            first.name = "Desktop 1"
            store.update(first)

            let repaired = store.repairOrderFallbackNamesFromHistory()

            XCTAssertEqual(repaired, [1: "Research"])
            XCTAssertEqual(store.space(orderIndex: 1).name, "Research")
            XCTAssertEqual(store.space(orderIndex: 2).name, "Manual Override")
            XCTAssertEqual(store.listBackups().count, 1)
        }
    }

    func testInvalidConfigIsPreservedBeforeDefaultsAreWritten() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpacesUltimateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("spaces-config.json"))

        setenv("SPACESULTIMATE_CONFIG_DIR", directory.path, 1)
        defer {
            unsetenv("SPACESULTIMATE_CONFIG_DIR")
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SpaceStore()

        XCTAssertEqual(store.spaces.count, 4)
        let invalidConfigs = store.listInvalidConfigs()
        XCTAssertEqual(invalidConfigs.count, 1)
        XCTAssertEqual(try Data(contentsOf: invalidConfigs[0]), Data("{ not json".utf8))
        XCTAssertNoThrow(try JSONDecoder().decode(SpaceConfig.self, from: Data(contentsOf: store.configURL)))
    }

    private func withTemporaryStore(_ body: (SpaceStore) throws -> Void) throws {
        try withTemporaryConfig(nil, body)
    }

    private func withTemporaryConfig(_ config: SpaceConfig?, _ body: (SpaceStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpacesUltimateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let config {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: directory.appendingPathComponent("spaces-config.json"))
        }

        setenv("SPACESULTIMATE_CONFIG_DIR", directory.path, 1)
        defer {
            unsetenv("SPACESULTIMATE_CONFIG_DIR")
            try? FileManager.default.removeItem(at: directory)
        }

        try body(SpaceStore())
    }

    private func rename(space orderIndex: Int, to name: String, in store: SpaceStore) {
        var space = store.space(orderIndex: orderIndex)
        space.name = name
        store.update(space)
    }

    private func detected(_ stableIDs: String...) -> [DetectedSpace] {
        stableIDs.enumerated().map { index, stableID in
            DetectedSpace(stableID: stableID, orderIndex: index + 1)
        }
    }

    private func metadata(
        id: String,
        stableID: String?,
        orderIndex: Int,
        name: String,
        colorHex: String = "#2F80ED"
    ) -> SpaceMetadata {
        SpaceMetadata(
            id: id,
            stableID: stableID,
            orderIndex: orderIndex,
            name: name,
            colorHex: colorHex,
            icon: "",
            note: "",
            shortcut: "",
            assignedApps: []
        )
    }
}
