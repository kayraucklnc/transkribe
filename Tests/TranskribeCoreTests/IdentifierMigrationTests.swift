import Foundation
import Testing
@testable import TranskribeCore

@Suite struct IdentifierMigrationTests {
    @Test func copiesSettingsFromTheOldDomainOnce() throws {
        let old = "transkribe-tests-\(UUID().uuidString)"
        Fixtures.removeAfterRun(defaultsNamed: old)
        let defaults = Fixtures.temporaryDefaults()
        UserDefaults.standard.setPersistentDomain(["transcriptionSettings": Data([1, 2]), "NSWindow Frame main": "x", "recordingSource": "both"], forName: old)
        defer { UserDefaults.standard.removePersistentDomain(forName: old) }

        #expect(IdentifierMigration.migrateDefaults(from: old, into: defaults))
        #expect(defaults.data(forKey: "transcriptionSettings") == Data([1, 2]))
        #expect(defaults.string(forKey: "recordingSource") == "both")
        #expect(defaults.object(forKey: "NSWindow Frame main") == nil)

        defaults.set("microphone", forKey: "recordingSource")
        #expect(!IdentifierMigration.migrateDefaults(from: old, into: defaults))
        #expect(defaults.string(forKey: "recordingSource") == "microphone")
    }

    @Test func movesTheKeychainItemToTheNewService() throws {
        let legacy = KeychainStore(service: "test.legacy.\(UUID().uuidString)")
        let store = KeychainStore(service: "test.current.\(UUID().uuidString)", legacyService: legacy.service)
        try legacy.set("sk-test", account: "key")
        defer { try? legacy.delete(account: "key"); try? store.delete(account: "key") }

        #expect(store.get(account: "key") == "sk-test")
        #expect(legacy.get(account: "key") == nil)
        #expect(KeychainStore(service: store.service).get(account: "key") == "sk-test")
    }
}
