import XCTest
@testable import Type4Me

final class ModeStorageTests: XCTestCase {

    private let testURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("type4me-test-modes.json")

    override func tearDown() {
        try? FileManager.default.removeItem(at: testURL)
    }

    func testSaveAndLoad() throws {
        let storage = ModeStorage(fileURL: testURL)
        let modes = ProcessingMode.builtins + [
            ProcessingMode(id: UUID(), name: "Custom", prompt: "Do {text}", isBuiltin: false)
        ]
        try storage.save(modes)
        let loaded = storage.load()
        // dualChannel is auto-injected if missing
        XCTAssertTrue(loaded.contains { $0.name == "Custom" })
        XCTAssertTrue(loaded.contains { $0.id == ProcessingMode.direct.id })
    }

    func testLoadMissing_returnsBuiltins() {
        let storage = ModeStorage(fileURL: testURL)
        let loaded = storage.load()
        XCTAssertEqual(loaded, ProcessingMode.defaults)
    }

    func testLoadMigratesLegacyBuiltinModesToDeletableModes() throws {
        let storage = ModeStorage(fileURL: testURL)
        let legacyModes = [
            ProcessingMode.direct,
            ProcessingMode(
                id: ProcessingMode.smartDirect.id,
                name: "智能模式",
                prompt: "",
                isBuiltin: true
            ),
            ProcessingMode(
                id: ProcessingMode.translate.id,
                name: "英文翻译",
                prompt: "legacy",
                isBuiltin: true,
                processingLabel: "翻译中"
            ),
        ]

        try storage.save(legacyModes)
        let loaded = storage.load()

        let smart = loaded.first(where: { $0.id == ProcessingMode.smartDirect.id })
        let translate = loaded.first(where: { $0.id == ProcessingMode.translate.id })

        XCTAssertEqual(smart?.isBuiltin, false)
        XCTAssertEqual(smart?.prompt, ProcessingMode.smartDirect.prompt)
        XCTAssertEqual(translate?.isBuiltin, false)
        XCTAssertEqual(translate?.prompt, ProcessingMode.translate.prompt)
    }

    func testDeletedDefaultModesAreNotReinserted_exceptAutoInjected() throws {
        let storage = ModeStorage(fileURL: testURL)
        try storage.save([ProcessingMode.direct])

        let loaded = storage.load()

        // direct is kept, dualChannel is auto-injected
        XCTAssertTrue(loaded.contains { $0.id == ProcessingMode.direct.id })
        XCTAssertTrue(loaded.contains { $0.id == ProcessingMode.dualChannel.id })
        // smartDirect and translate were removed and not re-injected
        XCTAssertFalse(loaded.contains { $0.id == ProcessingMode.smartDirect.id })
        XCTAssertFalse(loaded.contains { $0.id == ProcessingMode.translate.id })
    }

    func testCustomSmartModePromptIsPreserved() throws {
        let storage = ModeStorage(fileURL: testURL)
        let customSmart = ProcessingMode(
            id: ProcessingMode.smartDirect.id,
            name: "智能模式",
            prompt: "自定义智能 Prompt: {text}",
            isBuiltin: false,
            processingLabel: "修正中"
        )

        try storage.save([ProcessingMode.direct, customSmart])
        let loaded = storage.load()

        XCTAssertEqual(loaded.first(where: { $0.id == ProcessingMode.smartDirect.id })?.prompt, customSmart.prompt)
        XCTAssertEqual(loaded.first(where: { $0.id == ProcessingMode.smartDirect.id })?.processingLabel, customSmart.processingLabel)
    }

    // MARK: - Hotkey field tests

    func testHotkeyFieldsArePersisted() throws {
        let storage = ModeStorage(fileURL: testURL)
        var mode = ProcessingMode(
            id: UUID(), name: "Test", prompt: "{text}", isBuiltin: false
        )
        mode.hotkeyCode = 61
        mode.hotkeyModifiers = 0
        mode.hotkeyStyle = .hold

        try storage.save([ProcessingMode.direct, mode])
        let loaded = storage.load()
        let loadedMode = loaded.first { $0.name == "Test" }

        XCTAssertEqual(loadedMode?.hotkeyCode, 61)
        XCTAssertEqual(loadedMode?.hotkeyModifiers, 0)
        XCTAssertEqual(loadedMode?.hotkeyStyle, .hold)
    }

    func testMissingHotkeyFieldsDefaultGracefully() throws {
        let storage = ModeStorage(fileURL: testURL)
        // Simulate old JSON without hotkey fields
        let json = """
        [{"id":"00000000-0000-0000-0000-000000000001","name":"快速模式","prompt":"","isBuiltin":true,"processingLabel":"处理中","isDualChannel":false}]
        """
        try json.data(using: .utf8)!.write(to: testURL)
        let loaded = storage.load()
        let direct = loaded.first { $0.id == ProcessingMode.direct.id }

        // Old JSON has no hotkey fields - should decode gracefully
        // Note: direct mode's static definition has hotkeyCode=61, but since
        // it's isBuiltin=true, load() returns the static .direct which has hotkeyCode=61
        XCTAssertEqual(direct?.hotkeyStyle, .hold)
    }

    func testToggleStyleIsPersisted() throws {
        let storage = ModeStorage(fileURL: testURL)
        var mode = ProcessingMode(
            id: UUID(), name: "Toggle Mode", prompt: "{text}", isBuiltin: false
        )
        mode.hotkeyCode = 58
        mode.hotkeyStyle = .toggle

        try storage.save([ProcessingMode.direct, mode])
        let loaded = storage.load()
        let loadedMode = loaded.first { $0.name == "Toggle Mode" }

        XCTAssertEqual(loadedMode?.hotkeyCode, 58)
        XCTAssertEqual(loadedMode?.hotkeyStyle, .toggle)
    }
}
