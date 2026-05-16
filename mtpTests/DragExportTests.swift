//
//  DragExportTests.swift
//  mtpTests
//

import XCTest
import UniformTypeIdentifiers
@testable import mtp

final class DragExportTests: XCTestCase {
    func testFilePromiseDestinationAppendsFileName() {
        let baseURL = URL(fileURLWithPath: "/tmp/export", isDirectory: true)
        let file = FileItem(
            id: "file-1",
            name: "photo.jpg",
            path: "/DCIM/photo.jpg",
            size: 1024,
            modifiedDate: Date(),
            isDirectory: false,
            mimeType: "image/jpeg"
        )
        
        let destinationURL = FilePromiseDestination.url(for: file, in: baseURL)
        
        XCTAssertEqual(destinationURL.path, "/tmp/export/photo.jpg")
        XCTAssertFalse(destinationURL.hasDirectoryPath)
    }
    
    func testFilePromiseDestinationAppendsFolderNameAsDirectory() {
        let baseURL = URL(fileURLWithPath: "/tmp/export", isDirectory: true)
        let folder = FileItem(
            id: "folder-1",
            name: "DCIM",
            path: "/DCIM",
            size: 0,
            modifiedDate: Date(),
            isDirectory: true,
            mimeType: nil
        )
        
        let destinationURL = FilePromiseDestination.url(for: folder, in: baseURL)
        
        XCTAssertEqual(destinationURL.path, "/tmp/export/DCIM")
        XCTAssertTrue(destinationURL.hasDirectoryPath)
    }
    
    func testFilePromiseTypeUsesFolderIdentifierForDirectories() {
        let folder = FileItem(
            id: "folder-1",
            name: "Download",
            path: "/Download",
            size: 0,
            modifiedDate: Date(),
            isDirectory: true,
            mimeType: nil
        )
        
        XCTAssertEqual(FilePromiseType.identifier(for: folder), UTType.folder.identifier)
    }
    
    func testFilePromiseTypeFallsBackToDataForUnknownExtension() {
        let file = FileItem(
            id: "file-1",
            name: "archive.unknown-extension-for-test",
            path: "/archive.unknown-extension-for-test",
            size: 1024,
            modifiedDate: Date(),
            isDirectory: false,
            mimeType: nil
        )
        
        XCTAssertEqual(FilePromiseType.identifier(for: file), UTType.data.identifier)
    }
    
    func testPromisedExportResultMergesCountsAndFailures() {
        var result = PromisedExportResult(
            succeeded: 1,
            failed: [PromisedExportFailure(path: "/tmp/a", message: "failed")],
            skipped: 0
        )
        let other = PromisedExportResult(succeeded: 2, failed: [], skipped: 1)
        
        result.merge(other)
        
        XCTAssertEqual(result.succeeded, 3)
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(result.hasFailures)
    }
}
