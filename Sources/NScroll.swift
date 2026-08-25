//  SPDX-License-Identifier: MIT
//  Copyright (C) 2026 Jeff Zhang
//
//  NScroll.swift
//  Inverts scroll direction for discrete (wheel) mice only, leaving continuous
//  devices such as trackpads and the Magic Mouse untouched.
//
//  Build: make
//

import Darwin
import Foundation

@main
struct NScroll {
  static let name = "NScroll"
  static let command = "nscroll"
  static let version = "0.1.0"

  /// The absolute path of the running binary — the identity TCC keys
  /// accessibility permission to, and the path the launch agent's plist has
  /// to record. Resolved via dyld rather than argv[0], which is just "nscroll"
  /// when the shell found us on PATH.
  static var executablePath: String {
    var size = UInt32(PATH_MAX)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { return command }
    return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
  }

  enum Command: String {
    case run
    case enable
    case disable
    case restart
    case status
    case help
    case version

    init?(argument: String) {
      switch argument {
      case "-h", "--help": self = .help
      case "-V", "--version": self = .version
      default: self.init(rawValue: argument)
      }
    }
  }

  static func main() {
    exit(NScroll().run(CommandLine.arguments))
  }

  /// Kept out of `main()` so it can be driven with a synthetic argv.
  ///
  /// Exit codes: 0 success or agent running, 1 runtime failure, 2 bad
  /// invocation, 3 agent installed but not running, 4 agent not installed.
  func run(_ argv: [String]) -> Int32 {
    let arguments = argv.dropFirst()

    guard let first = arguments.first else {
      printOverview()
      return 0
    }
    guard arguments.count == 1 else {
      Log.error("`\(first)` takes no arguments")
      return 2
    }
    guard let command = Command(argument: first) else {
      Log.error("unknown command `\(first)`")
      Log.error("run `\(Self.command) help` for usage")
      return 2
    }

    do {
      return try execute(command)
    } catch {
      Log.error("\(error)")
      return 1
    }
  }

  /// Returns the process exit code. Everything but `status` reports success
  /// by returning, and failure by throwing.
  private func execute(_ command: Command) throws -> Int32 {
    switch command {
    case .run: try ScrollService().run()
    case .enable: try LaunchAgent.enable()
    case .disable: try LaunchAgent.disable()
    case .restart: try LaunchAgent.restart()
    case .status:
      let status = try LaunchAgent.status()
      Log.info("\(status)")
      return status.exitCode
    case .help: printOverview()
    case .version: Log.info(Self.version)
    }
    return 0
  }

  private func printOverview() {
    Log.info(
      """
      \(Self.name) — inverts scroll direction for discrete (wheel) mice only,
      leaving trackpads and the Magic Mouse untouched.

      usage: \(Self.command) <command>

        run        invert scrolling in the foreground until interrupted
        enable     install and start the launch agent
        disable    stop and remove the launch agent
        restart    restart the launch agent, after reinstalling the binary
        status     report whether the launch agent is installed and running
        help       show this message                        (-h, --help)
        version    print the version                        (-V, --version)
      """)
  }
}
