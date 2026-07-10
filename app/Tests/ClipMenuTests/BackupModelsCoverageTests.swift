import Testing
import Foundation
@testable import ClipMenu

// Characterization of the backup model value types (BackupModels.swift):
// BackupKind Codable/CaseIterable, BackupVersionMeta computed props + Equatable,
// and the BackupError / BackupResult equality surfaces.
@Suite struct BackupModelsCoverageTests {

    private func meta(recordName: String = "rec-1",
                      kind: BackupKind = .manual,
                      serverDate: Date? = nil,
                      clientDate: Date = Date(timeIntervalSince1970: 1_700_000_000))
    -> BackupVersionMeta {
        BackupVersionMeta(
            recordName: recordName, kind: kind, serverDate: serverDate, clientDate: clientDate,
            folderCount: 2, snippetCount: 3, contentHash: "h", schemaVersion: 1, deviceName: "Mac")
    }

    // MARK: BackupKind

    @Test func backupKindHasThreeStableRawValues() {
        #expect(BackupKind.allCases == [.auto, .manual, .preRestore])
        #expect(BackupKind.auto.rawValue == "auto")
        #expect(BackupKind.manual.rawValue == "manual")
        #expect(BackupKind.preRestore.rawValue == "preRestore")
    }

    @Test func backupKindCodableRoundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for kind in BackupKind.allCases {
            let data = try encoder.encode(kind)
            let decoded = try decoder.decode(BackupKind.self, from: data)
            #expect(decoded == kind)
        }
    }

    @Test func backupKindDecodesFromRawString() throws {
        let decoded = try JSONDecoder().decode(BackupKind.self, from: Data("\"preRestore\"".utf8))
        #expect(decoded == .preRestore)
    }

    // MARK: BackupVersionMeta

    @Test func idEqualsRecordName() {
        #expect(meta(recordName: "abc").id == "abc")
    }

    @Test func effectiveDatePrefersServerClock() {
        let server = Date(timeIntervalSince1970: 2_000_000_000)
        let client = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(meta(serverDate: server, clientDate: client).effectiveDate == server)
    }

    @Test func effectiveDateFallsBackToClientWhenNoServerDate() {
        let client = Date(timeIntervalSince1970: 1_234_567_890)
        #expect(meta(serverDate: nil, clientDate: client).effectiveDate == client)
    }

    @Test func metaEquality() {
        let a = meta(recordName: "same")
        let b = meta(recordName: "same")
        #expect(a == b)
        #expect(meta(recordName: "x") != meta(recordName: "y"))
        // A differing field (schemaVersion via serverDate here) breaks equality.
        #expect(a != meta(recordName: "same", serverDate: Date(timeIntervalSince1970: 5)))
    }

    // MARK: BackupError

    @Test func backupErrorEquality() {
        #expect(BackupError.validationFailed == BackupError.validationFailed)
        #expect(BackupError.preRestoreFailed == BackupError.preRestoreFailed)
        #expect(BackupError.unsupportedSchemaVersion(found: 2, supported: 1)
                == BackupError.unsupportedSchemaVersion(found: 2, supported: 1))
        #expect(BackupError.unsupportedSchemaVersion(found: 2, supported: 1)
                != BackupError.unsupportedSchemaVersion(found: 3, supported: 1))
        #expect(BackupError.validationFailed != BackupError.preRestoreFailed)
    }

    // MARK: BackupResult

    @Test func backupResultEquality() {
        let v = meta()
        #expect(BackupResult.created(v) == BackupResult.created(v))
        #expect(BackupResult.noChanges == BackupResult.noChanges)
        #expect(BackupResult.created(v) != BackupResult.noChanges)
        #expect(BackupResult.created(v) != BackupResult.created(meta(recordName: "other")))
    }
}
