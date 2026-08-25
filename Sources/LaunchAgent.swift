//  SPDX-License-Identifier: MIT
//  Copyright (C) 2026 Jeff Zhang
//
//  LaunchAgent.swift
//  The per-user launch agent: its plist, its launchctl lifecycle, and what it
//  is doing right now.
//
//  This is the only file that writes to disk or spawns a subprocess.
//

import Darwin
import Foundation

enum LaunchAgent {
  /// launchd's name for the job. Unrelated to the Makefile's
  /// `codesign --identifier`, which merely happens to use the same string.
  static let label = "com.nscroll.agent"

  /// launchctl's exit codes for "that service is not loaded". They differ by
  /// subcommand: `bootout` reports 3 (No such process) while `print` and
  /// `kickstart` report 113 (Could not find service). Callers that care about
  /// the difference check for a zero status explicitly.
  private static let serviceNotLoaded: Set<Int32> = [3, 113]

  static var plistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("LaunchAgents")
      .appendingPathComponent("\(label).plist")
  }

  // MARK: - Failures

  enum Failure: Error, CustomStringConvertible {
    case rootNotSupported
    case notLoaded
    case malformedPlist(URL)
    case launchctlFailed(arguments: [String], status: Int32, output: String)

    var description: String {
      switch self {
      case .rootNotSupported:
        return """
          the launch agent is per-user; run `\(NScroll.command) enable` as \
          yourself, not with sudo
          """
      case .notLoaded:
        return "the launch agent is not loaded; run `\(NScroll.command) enable` first"
      case .malformedPlist(let url):
        return """
          \(url.path) is not a readable \(NScroll.name) launch agent; run \
          `\(NScroll.command) enable` to rewrite it
          """
      case .launchctlFailed(let arguments, let status, let output):
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = detail.isEmpty ? "" : ": \(detail)"
        return "launchctl \(arguments.joined(separator: " ")) failed (\(status))\(suffix)"
      }
    }
  }

  // MARK: - Lifecycle

  static func enable() throws {
    // Under sudo this would write into root's home and bootstrap into gui/0,
    // which is a confusing kind of broken rather than a loud one.
    guard getuid() != 0 else { throw Failure.rootNotSupported }

    let program = NScroll.executablePath
    try FileManager.default.createDirectory(
      at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let plist: [String: Any] = [
      "Label": label,
      "ProgramArguments": [program, NScroll.Command.run.rawValue],
      "RunAtLoad": true,
      // Brings the agent back on its own once accessibility permission is
      // granted, at the cost of a 10-second respawn cycle while it is not.
      "KeepAlive": true,
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: plistURL, options: .atomic)

    // Idempotent: re-enabling after a rebuild or a move replaces whatever is
    // already loaded.
    try launchctl(["bootout", serviceTarget], tolerating: serviceNotLoaded)
    try launchctl(["bootstrap", domainTarget, plistURL.path])

    Log.info("enabled — \(program)")
    Log.info(
      """
      if scrolling does not invert, grant Accessibility to \(program) in \
      System Settings > Privacy & Security > Accessibility.
      """)
  }

  static func disable() throws {
    try launchctl(["bootout", serviceTarget], tolerating: serviceNotLoaded)
    if FileManager.default.fileExists(atPath: plistURL.path) {
      try FileManager.default.removeItem(at: plistURL)
    }
    Log.info("disabled")
  }

  static func restart() throws {
    let result = try launchctl(["kickstart", "-k", serviceTarget], tolerating: serviceNotLoaded)
    guard result.status == 0 else { throw Failure.notLoaded }
    Log.info("restarted")
  }

  // MARK: - Status

  enum Status: CustomStringConvertible {
    case notInstalled
    case notLoaded(program: String)
    case running(pid: Int32, program: String)
    case failing(lastExitCode: Int32?, program: String)

    var exitCode: Int32 {
      switch self {
      case .running: return 0
      case .notLoaded, .failing: return 3
      case .notInstalled: return 4
      }
    }

    var description: String {
      switch self {
      case .notInstalled:
        return """
          agent      not installed

          run `\(NScroll.command) enable` to install it.
          """
      case .notLoaded(let program):
        return Self.report(
          state: "installed but not loaded", program: program,
          hint: "run `\(NScroll.command) enable` to load it.")
      case .running(let pid, let program):
        return Self.report(state: "running (pid \(pid))", program: program, hint: nil)
      case .failing(let code, let program):
        let exit = code.map { "last exit code \($0)" } ?? "never started"
        return Self.report(
          state: "not running (\(exit))", program: program,
          hint: """
            launchd is restarting it and it keeps exiting. The usual cause is missing \
            accessibility permission — grant it in System Settings > Privacy & Security > \
            Accessibility for \(program).
            """)
      }
    }

    private static func report(state: String, program: String, hint: String?) -> String {
      let isMissing = !FileManager.default.isExecutableFile(atPath: program)
      var lines = [
        "agent      \(state)",
        "label      \(LaunchAgent.label)",
        "plist      \(LaunchAgent.plistURL.path)",
        "program    \(program)\(isMissing ? "   (missing)" : "")",
      ]
      // A vanished binary is the more specific diagnosis, so it wins.
      if isMissing {
        lines += [
          "",
          """
          the recorded program no longer exists; reinstall it and run \
          `\(NScroll.command) enable`.
          """,
        ]
      } else if let hint {
        lines += ["", hint]
      }
      return lines.joined(separator: "\n")
    }
  }

  static func status() throws -> Status {
    guard let program = try recordedProgram() else { return .notInstalled }

    let result = try launchctl(["print", serviceTarget], tolerating: serviceNotLoaded)
    guard result.status == 0 else { return .notLoaded(program: program) }

    // `launchctl print` is a human-readable dump, not a stable interface. Key
    // off `pid`, which is present only while the job is alive; everything else
    // is decoration that a future macOS is free to rename.
    if let pid = field("pid", in: result.output).flatMap(Int32.init), pid > 0 {
      return .running(pid: pid, program: program)
    }
    return .failing(
      lastExitCode: field("last exit code", in: result.output).flatMap(Int32.init),
      program: program)
  }

  /// `ProgramArguments[0]` from the installed plist, or nil when there is none.
  private static func recordedProgram() throws -> String? {
    guard let data = FileManager.default.contents(atPath: plistURL.path) else { return nil }
    guard
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let arguments = (plist as? [String: Any])?["ProgramArguments"] as? [String],
      let program = arguments.first
    else {
      throw Failure.malformedPlist(plistURL)
    }
    return program
  }

  /// Matches `<name> = <value>` in `launchctl print` output.
  private static func field(_ name: String, in output: String) -> String? {
    let prefix = "\(name) = "
    for line in output.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix(prefix) else { continue }
      return String(trimmed.dropFirst(prefix.count))
    }
    return nil
  }

  // MARK: - launchctl

  private static var domainTarget: String { "gui/\(getuid())" }
  private static var serviceTarget: String { "\(domainTarget)/\(label)" }

  @discardableResult
  private static func launchctl(
    _ arguments: [String], tolerating: Set<Int32> = []
  ) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()

    // Drain before waiting: `launchctl print` outruns the pipe buffer, and
    // waiting first would deadlock.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let status = process.terminationStatus
    let output = String(decoding: data, as: UTF8.self)
    guard status == 0 || tolerating.contains(status) else {
      throw Failure.launchctlFailed(arguments: arguments, status: status, output: output)
    }
    return (status, output)
  }
}
