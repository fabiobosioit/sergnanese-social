import Foundation

// Subcommand table. Each command lives in its own file; later tasks replace
// their own file and never edit this one.
let commands: [String: ([String]) async -> Int32] = [
  "preview": runPreview,
  "demo-render": runDemoRender,
  "screenshots": runScreenshots,
  "seed": runSeed,
]

let arguments = Array(CommandLine.arguments.dropFirst())
guard let name = arguments.first, let command = commands[name] else {
  let names = commands.keys.sorted().joined(separator: "|")
  FileHandle.standardError.write(Data("usage: ss-tool <\(names)> [args]\n".utf8))
  exit(2)
}
exit(await command(Array(arguments.dropFirst())))
