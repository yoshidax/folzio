import Foundation
import FixtureKit

let arguments = CommandLine.arguments
let options = arguments.dropFirst(2)
let knownOptions: Set<String> = ["--big", "--multi-root-search", "--large-search"]
guard arguments.count >= 2, options.allSatisfy({ knownOptions.contains($0) }) else {
    FileHandle.standardError.write(Data("usage: make-fixtures <output-directory> [--big] [--multi-root-search] [--large-search]\n".utf8))
    exit(2)
}

let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if options.contains("--multi-root-search") {
        // Only the TAK-104 fixtures, which take a few seconds instead of every set.
        try FixtureSets.multiRootSearch(in: directory)
    } else {
        try FixtureSets.makeAll(in: directory)
    }
    if options.contains("--big") {
        try FixtureSets.bigVideoZips(in: directory)
    }
    if options.contains("--large-search") {
        try FixtureSets.largeSearch(in: directory)
    }
    print("fixtures written to \(directory.path)")
} catch {
    FileHandle.standardError.write(Data("make-fixtures failed: \(error)\n".utf8))
    exit(1)
}
