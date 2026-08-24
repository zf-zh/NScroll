//  SPDX-License-Identifier: MIT
//  Copyright (C) 2026 Jeff Zhang
//
//  EventTap.swift
//  Owns a CGEvent tap and its run loop source, and keeps the tap alive when
//  the system disables it.
//

import ApplicationServices
import CoreGraphics
import Darwin

final class EventTap {
  enum Failure: Error, CustomStringConvertible {
    case accessibilityPermissionDenied
    case noRunLoop
    case tapCreationFailed
    case runLoopSourceCreationFailed

    var description: String {
      switch self {
      case .accessibilityPermissionDenied:
        // TCC attributes the grant to the *responsible* process: the
        // terminal app when this was launched from a shell, but the
        // nscroll binary itself when launchd started it. Name whichever
        // one the user actually has to tick.
        let client =
          EventTap.isInteractive
          ? "the app hosting this binary (Terminal, if you launched it from a shell)"
          : NScroll.executablePath
        return """
          accessibility permission denied. Grant it in System Settings > \
          Privacy & Security > Accessibility for \(client), then rerun.
          """
      case .noRunLoop:
        return "no current run loop"
      case .tapCreationFailed:
        return "could not create the event tap"
      case .runLoopSourceCreationFailed:
        return "could not create a run loop source for the event tap"
      }
    }
  }

  private static let eventMask: CGEventMask =
    1 << CGEventMask(CGEventType.scrollWheel.rawValue)

  private let transform: (CGEvent) -> CGEvent?

  private var port: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var runLoop: CFRunLoop?

  init(transform: @escaping (CGEvent) -> CGEvent?) {
    self.transform = transform
  }

  deinit {
    stop()
  }

  // MARK: Lifecycle

  func start() throws {
    guard port == nil else { return }

    // Prompting from a launchd context drops a dialog on screen with no app
    // behind it, and KeepAlive would re-trigger it every 10 seconds. Only
    // ask when there is a human at a terminal to answer.
    guard Self.hasAccessibilityPermission(promptIfNeeded: Self.isInteractive) else {
      throw Failure.accessibilityPermissionDenied
    }
    guard let runLoop = CFRunLoopGetCurrent() else {
      throw Failure.noRunLoop
    }

    // `self` is handed to the C callback as an unretained context pointer;
    // `deinit` tears the tap down, so the pointer can never dangle.
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .tailAppendEventTap,
        options: .defaultTap,
        eventsOfInterest: Self.eventMask,
        callback: Self.callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Failure.tapCreationFailed
    }

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
      CFMachPortInvalidate(port)
      throw Failure.runLoopSourceCreationFailed
    }

    // .commonModes keeps events flowing during tracking and modal loops.
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)

    self.port = port
    self.runLoopSource = source
    self.runLoop = runLoop
  }

  func stop() {
    if let port {
      CGEvent.tapEnable(tap: port, enable: false)
    }
    if let runLoop, let runLoopSource {
      CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
    }
    if let port {
      CFMachPortInvalidate(port)
    }
    port = nil
    runLoopSource = nil
    runLoop = nil
  }

  // MARK: Callback bridging

  /// Captures nothing, so it converts to a C function pointer. All context
  /// travels through the `userInfo` parameter.
  private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // These arrive even though they aren't in `eventsOfInterest`.
      // Without this branch the tap silently dies and stays dead.
      guard let port else { return nil }
      Log.info("tap disabled by the system; re-enabling")
      CGEvent.tapEnable(tap: port, enable: true)
      return nil

    default:
      guard let result = transform(event) else { return nil }
      return Unmanaged.passUnretained(result)
    }
  }

  // MARK: Permission

  /// True when a human is at a terminal to answer a permission dialog.
  static var isInteractive: Bool {
    isatty(STDIN_FILENO) == 1
  }

  private static func hasAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: promptIfNeeded] as CFDictionary)
  }
}
