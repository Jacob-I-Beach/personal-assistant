import AssistantCore
import Foundation
import XCTest
@testable import PersonalAssistant

final class FolderWorkspacePlatformTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> (URL, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = base.appendingPathComponent("Selected"), privateStorage = base.appendingPathComponent("Private")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, privateStorage)
    }
    func testFolderPersistenceReadSearchAndReviewedVersionedWrite() async throws {
        let (folder, privateStorage) = try fixture()
        try Data("Before\nVerified total: 60.5".utf8).write(to: folder.appendingPathComponent("notes.md"))
        let service = try FolderWorkspaceService(storage: privateStorage, requiresSecurityScope: false)
        let connected = try await service.connect(folder)
        do { _ = try await service.list(connected.id, remote: true); XCTFail("Shared an on-device-only folder") } catch {}
        try await service.setAccess(connected.id, connected: true, edits: true)
        let page = try await service.list(connected.id, remote: true)
        let file = try XCTUnwrap(page.files.first)
        let read = try await service.read(file.id, remote: true)
        let found = try await service.search(connected.id, query: "Verified", remote: true)
        XCTAssertEqual(found.matches.count, 1); XCTAssertTrue(found.matches[0].1.contains("60.5"))
        let proposal = try await service.propose(fileID: file.id, version: read.version, replacement: "After\nVerified total: 60.5", remote: true)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("notes.md"), encoding: .utf8), "Before\nVerified total: 60.5")
        let reopened = try FolderWorkspaceService(storage: privateStorage, requiresSecurityScope: false)
        let applied = try await reopened.apply(proposal.id, remote: true)
        XCTAssertEqual(applied.state, "applied")
        _ = try await reopened.apply(proposal.id, remote: true)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("notes.md"), encoding: .utf8), "After\nVerified total: 60.5")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("connected-folders.json").path))
    }
    func testStaleCancelledAndRevokedChangesNeverOverwrite() async throws {
        let (folder, privateStorage) = try fixture()
        let fileURL = folder.appendingPathComponent("note.txt")
        try Data("Original".utf8).write(to: fileURL)
        let service = try FolderWorkspaceService(storage: privateStorage, requiresSecurityScope: false)
        let connection = try await service.connect(folder)
        try await service.setAccess(connection.id, connected: true, edits: true)
        let page = try await service.list(connection.id, remote: true)
        let file = try XCTUnwrap(page.files.first)
        let read = try await service.read(file.id, remote: true)
        let proposal = try await service.propose(fileID: file.id, version: read.version, replacement: "Proposed", remote: true)
        try Data("Changed outside app".utf8).write(to: fileURL)
        do { _ = try await service.apply(proposal.id, remote: true); XCTFail("Overwrote a changed file") } catch {}
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "Changed outside app")
        try await service.cancelProposal(proposal.id)
        do { _ = try await service.apply(proposal.id, remote: true); XCTFail("Applied a cancelled edit") } catch {}
        try await service.setAccess(connection.id, connected: false, edits: false)
        do { _ = try await service.read(file.id, remote: true); XCTFail("Read after revocation") } catch {}
        try await service.disconnect(connection.id)
        do { _ = try await service.list(connection.id, remote: false); XCTFail("Read disconnected folder") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
    func testCreationRejectsCollisionsTraversalAndFakeBinaryDocuments() async throws {
        let (folder, privateStorage) = try fixture()
        let service = try FolderWorkspaceService(storage: privateStorage, requiresSecurityScope: false)
        let connection = try await service.connect(folder)
        try await service.setAccess(connection.id, connected: false, edits: true)
        let file = try await service.create(connection.id, filename: "result.csv", content: "value\n60.5\n", remote: false)
        let repeated = try await service.create(connection.id, filename: "result.csv", content: "value\n60.5\n", remote: false)
        XCTAssertEqual(file.id, repeated.id)
        for (name, content) in [("result.csv", "different"), ("../escape.txt", "bad"), ("fake.pdf", "plain text"), ("invalid.json", "{bad}")] {
            do { _ = try await service.create(connection.id, filename: name, content: content, remote: false); XCTFail("Accepted \(name)") } catch {}
        }
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("result.csv"), encoding: .utf8), "value\n60.5\n")
        try Data("%PDF ASCII is not an editable text document".utf8).write(to: folder.appendingPathComponent("example.pdf"))
        let page = try await service.list(connection.id, remote: false)
        let pdf = try XCTUnwrap(page.files.first { $0.relativePath == "example.pdf" })
        let read = try await service.read(pdf.id, remote: false)
        do { _ = try await service.propose(fileID: pdf.id, version: read.version, replacement: "text", remote: false); XCTFail("Permitted replacing a binary-format document with text") } catch {}
    }
}
