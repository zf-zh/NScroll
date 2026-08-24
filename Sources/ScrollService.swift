//  SPDX-License-Identifier: MIT
//  Copyright (C) 2026 Jeff Zhang
//
//  ScrollService.swift
//  The long-running half of the program: installs the tap, then blocks until a
//  termination signal arrives.
//

import CoreFoundation
import Darwin
import Dispatch

final class ScrollService {
  private static let terminatingSignals: [(number: Int32, name: String)] = [
    (SIGINT, "SIGINT"),
    (SIGTERM, "SIGTERM"),
    (SIGHUP, "SIGHUP"),
  ]

  private let tap = EventTap(transform: ScrollInverter.transform)
  private var signalHandlers: [SignalHandler] = []
  private var runLoop: CFRunLoop?

  func run() throws {
    try tap.start()
    runLoop = CFRunLoopGetCurrent()
    Log.info("\(NScroll.name) running — ^C to quit")

    signalHandlers = Self.terminatingSignals.map { signal in
      SignalHandler(signal.number) { [weak self] in self?.stop(after: signal.name) }
    }
    CFRunLoopRun()

    tap.stop()
    signalHandlers.removeAll()
    Log.info("stopped")
  }

  private func stop(after signalName: String) {
    Log.info("received \(signalName); stopping")
    guard let runLoop else { return }
    CFRunLoopStop(runLoop)
  }
}

/// Wraps a `DispatchSourceSignal` and keeps it alive for as long as the
/// instance lives.
private final class SignalHandler {
  private let source: DispatchSourceSignal

  init(_ signalNumber: Int32, handler: @escaping () -> Void) {
    // GCD observes signal delivery but does not change the default
    // disposition, so without SIG_IGN SIGINT would still kill the process
    // before the handler ever ran.
    Darwin.signal(signalNumber, SIG_IGN)

    source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler(handler: handler)
    source.activate()
  }

  deinit {
    source.cancel()
  }
}
