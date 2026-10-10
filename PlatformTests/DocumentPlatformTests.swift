import AssistantCore
import PDFKit
import XCTest
@testable import PersonalAssistant

@MainActor
final class DocumentPlatformTests: XCTestCase {
    private func fixture(_ name: String, base64: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try XCTUnwrap(Data(base64Encoded: base64)).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
    func testWordExtractionPreservesOriginalAndRejectsExternalEntities() async throws {
        let word = "UEsDBBQAAAAIAC6oSV3fP6/jWAAAAHsAAAARAAAAd29yZC9kb2N1bWVudC54bWyzKbdKyU8uzU3NK1GoyM3JK7Yqt1UqLcqzKkktLlGysym3SspPqQTRBSCiCESU2IWlFmWmZaamKMD1luSXJOZYKZgZ6Jna6IOUgMgiMFkAJiHG6COsswMAUEsBAhQAFAAAAAgALqhJXd8/r+NYAAAAewAAABEAAAAAAAAAAAAAAIABAAAAAHdvcmQvZG9jdW1lbnQueG1sUEsFBgAAAAABAAEAPwAAAIcAAAAAAA=="
        let url = try fixture("example.docx", base64: word)
        let (file, bytes) = try await DocumentImporter.shared.read(url)
        XCTAssertTrue(file.text.contains("Verified document total: 60.5"))
        XCTAssertEqual(bytes, try Data(contentsOf: url))
        XCTAssertFalse(file.allowsConnectedModels); XCTAssertFalse(file.allowsWorkspaceSearch)
        let bad = "UEsDBBQAAAAIAC6oSV1mmSYEVQAAAGAAAAARAAAAd29yZC9kb2N1bWVudC54bWyzUXTxdw6JDHBVSMlPLs1NzStRiLZRdPUL8QyJVKhQCI4MDnH1VVBKy8xJtdLX1y8oyixLLEnVL05NLkotUbKLtbOB6bOzKbFTq7C20S+xs9GHCwIAUEsBAhQAFAAAAAgALqhJXWaZJgRVAAAAYAAAABEAAAAAAAAAAAAAAIABAAAAAHdvcmQvZG9jdW1lbnQueG1sUEsFBgAAAAABAAEAPwAAAIQAAAAAAA=="
        do { _ = try await DocumentImporter.shared.read(fixture("entities.docx", base64: bad)); XCTFail("Accepted external entities") }
        catch { XCTAssertTrue(error.localizedDescription.contains("entity")) }
    }
    func testSpreadsheetResolvesSharedStringsAndLabelsCachedFormulas() async throws {
        let sheet = "UEsDBBQAAAAIAC6oSV1i+vLkHwAAACIAAAAUAAAAeGwvc2hhcmVkU3RyaW5ncy54bWyzKS4usbMpzrSzKbELSi1LzStNtdEvsbPRBwnpgyQBUEsDBBQAAAAIAC6oSV0xLwdgUQAAAHUAAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1ssynPL8ouzkhNLbGzAVMuiSWJdjZF+eV2NskKRbZKjoZKCiW2SsVKdjZldgY2+mV2NvrJUDknQyU7mzQ7Q20jG/00kLwxXF4fbII+kpH6CJsAUEsBAhQAFAAAAAgALqhJXWL68uQfAAAAIgAAABQAAAAAAAAAAAAAAIABAAAAAHhsL3NoYXJlZFN0cmluZ3MueG1sUEsBAhQAFAAAAAgALqhJXTEvB2BRAAAAdQAAABgAAAAAAAAAAAAAAIABUQAAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLBQYAAAAAAgACAIgAAADYAAAAAAA="
        let url = try fixture("example.xlsx", base64: sheet)
        let (file, _) = try await DocumentImporter.shared.read(url)
        XCTAssertTrue(file.text.contains("A1: Revenue"))
        XCTAssertTrue(file.text.contains("B1: 3 [cached; formula: 1+2]"))
        XCTAssertTrue(file.extractionNote.contains("not recalculated"))
    }
    func testGeneratedPDFContainsReadablePaginatedText() throws {
        let text = (1...150).map { "Item \($0): useful document text and a verified value of 60.5." }.joined(separator: "\n\n")
        let (bytes, extracted) = try PDFDocumentWriter.make(title: "Calculation report", markdown: text)
        let pdf = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let contents = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(contents.contains("Calculation report")); XCTAssertTrue(contents.contains("Item 150"))
        XCTAssertTrue(extracted.contains("60.5"))
    }
    func testDeviceResourcesExposeNoUniqueIdentity() {
        let value = DeviceContext.snapshot()
        XCTAssertNotNil(value["model_identifier"]); XCTAssertNotNil(value["physical_memory_bytes"])
        XCTAssertNil(value["name"]); XCTAssertNil(value["identifierForVendor"]); XCTAssertNil(value["serial"])
    }
}
