import Foundation
import FixtureKit

let arguments = CommandLine.arguments
let options = arguments.dropFirst(2)
guard arguments.count >= 2, options.allSatisfy({ $0 == "--big" }) else {
    FileHandle.standardError.write(Data("usage: make-fixtures <output-directory> [--big]\n".utf8))
    exit(2)
}

let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FixtureSets.makeAll(in: directory)
    if options.contains("--big") {
        try FixtureSets.bigVideoZips(in: directory)
    }
    print("fixtures written to \(directory.path)")
} catch {
    FileHandle.standardError.write(Data("make-fixtures failed: \(error)\n".utf8))
    exit(1)
}
