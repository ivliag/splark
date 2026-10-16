import AppKit
import Foundation

// Shared helpers for splark-dev commands.

let args: [String] = {
    setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered, so redirected logs show progress live
    return Array(CommandLine.arguments.dropFirst())
}()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func mask(_ token: String) -> String { token.count > 12 ? "\(token.prefix(9))…\(token.suffix(4))" : "…" }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func openInBrowser(_ url: URL) { NSWorkspace.shared.open(url) }
