import XCTest
@testable import Type4Me

final class KeychainServiceTests: XCTestCase {

    override func tearDown() {
        KeychainService.delete(key: "test_key")
    }

    func testSaveAndLoad() throws {
        try KeychainService.save(key: "test_key", value: "secret123")
        let loaded = KeychainService.load(key: "test_key")
        XCTAssertEqual(loaded, "secret123")
    }

    func testOverwrite() throws {
        try KeychainService.save(key: "test_key", value: "old")
        try KeychainService.save(key: "test_key", value: "new")
        XCTAssertEqual(KeychainService.load(key: "test_key"), "new")
    }

    func testLoadMissing() {
        let result = KeychainService.load(key: "nonexistent_key_xyz")
        XCTAssertNil(result)
    }

    func testDelete() throws {
        try KeychainService.save(key: "test_key", value: "value")
        KeychainService.delete(key: "test_key")
        XCTAssertNil(KeychainService.load(key: "test_key"))
    }

    func testLoadCredentials_fromKeychain() throws {
        try KeychainService.save(key: "tf_appKey", value: "myAppKey")
        try KeychainService.save(key: "tf_accessKey", value: "myAccessKey")
        try KeychainService.save(key: "tf_resourceId", value: "myResource")

        let config = KeychainService.loadASRConfig()
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.appKey, "myAppKey")
        XCTAssertEqual(config?.accessKey, "myAccessKey")
        XCTAssertEqual(config?.resourceId, "myResource")

        // Cleanup
        KeychainService.delete(key: "tf_appKey")
        KeychainService.delete(key: "tf_accessKey")
        KeychainService.delete(key: "tf_resourceId")
    }
}
