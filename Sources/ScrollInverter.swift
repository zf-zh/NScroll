//  SPDX-License-Identifier: MIT
//  Copyright (C) 2026 Jeff Zhang
//
//  ScrollInverter.swift
//  Negating a scroll event's deltas, and the rule for which events get it.
//

import CoreGraphics

// MARK: - Scroll axes

enum ScrollAxis {
  case vertical
  case horizontal

  /// Integer representations of this axis' delta, coarsest first.
  ///
  /// Order matters on write: setting any one representation makes CoreGraphics
  /// recompute the others, so the finer-grained value is written last and wins.
  var integerDeltaFields: [CGEventField] {
    switch self {
    case .vertical:
      return [.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1]
    case .horizontal:
      return [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2]
    }
  }

  /// 16.16 fixed-point representation. Must be read and written as a Double;
  /// going through the integer accessor truncates the fractional part.
  var fixedPointDeltaField: CGEventField {
    switch self {
    case .vertical: return .scrollWheelEventFixedPtDeltaAxis1
    case .horizontal: return .scrollWheelEventFixedPtDeltaAxis2
    }
  }
}

extension CGEvent {
  /// Negates every representation of the given axes' deltas.
  func negateScrollDeltas(on axes: [ScrollAxis]) {
    var integers: [(field: CGEventField, value: Int64)] = []
    var fixedPoints: [(field: CGEventField, value: Double)] = []

    // Pass 1 — snapshot everything. Because a write to one field triggers
    // recomputation of its siblings, reading and writing in a single loop
    // would negate already-derived values.
    for axis in axes {
      for field in axis.integerDeltaFields {
        integers.append((field, getIntegerValueField(field)))
      }
      let fixedPoint = axis.fixedPointDeltaField
      fixedPoints.append((fixedPoint, getDoubleValueField(fixedPoint)))
    }

    // Pass 2 — write the negated snapshot back.
    for (field, value) in integers {
      setIntegerValueField(field, value: -value)
    }
    for (field, value) in fixedPoints {
      setDoubleValueField(field, value: -value)
    }
  }
}

// MARK: - The transform

/// The rule applied to every event the tap receives.
enum ScrollInverter {
  /// Deliberately not configurable: edit here to also invert horizontal scrolling.
  private static let axes: [ScrollAxis] = [.vertical]

  /// Returns the (possibly mutated) event to forward it, or `nil` to swallow it.
  static func transform(_ event: CGEvent) -> CGEvent? {
    // Continuous == trackpad or Magic Mouse; those follow the system
    // "Natural scrolling" preference and are deliberately left alone.
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    guard !isContinuous else { return event }

    event.negateScrollDeltas(on: axes)
    return event
  }
}
