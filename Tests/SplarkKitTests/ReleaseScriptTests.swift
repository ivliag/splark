import Foundation
import Testing
@testable import SplarkKit

/// `scripts/release.sh` builds the zip a `v*` tag publishes; first it checks the tag against the app's version.
@Suite struct ReleaseScriptTests {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func release(_ arguments: String...) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/release.sh").path] + arguments
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    @Test func aTagMatchingTheAppsVersionPassesTheCheck() throws {
        let result = try release("v\(SplarkInfo.version)", "--check")
        #expect(result.status == 0)
        #expect(result.output == "\(SplarkInfo.version)\n")
    }

    @Test func refusesATagThatDoesntMatchTheAppsVersion() throws {
        let result = try release("v9.9.9", "--check")
        #expect(result.status == 1)
        #expect(result.output == "9.9.9 doesn't match the app's version: Support/Info.plist says \(SplarkInfo.version), SplarkInfo.swift says \(SplarkInfo.version).\n")
    }
}
