//  SPDX-License-Identifier: MIT
//  Copyright (C) 2026 Jeff Zhang
//
//  Log.swift
//  Everything the program says goes to stdout or stderr and nowhere else.
//
//  Under launchd the agent's plist sets no StandardOutPath, so both are
//  discarded; run `nscroll run` in a terminal to see any of this.
//

import Foundation

enum Log {
  static func info(_ message: String) {
    print(message)
    fflush(stdout)
  }

  static func error(_ message: String) {
    FileHandle.standardError.write(Data("\(NScroll.command): \(message)\n".utf8))
  }
}
