import SSCore
import SwiftUI

/// A yellow triangle with a message, for non-blocking problems ("Manca il logo"). An optional
/// button offers a one-click fix.
public struct WarningLabel: View {
  let message: String
  let fixTitle: String?
  let fix: (() -> Void)?

  public init(_ message: String, fixTitle: String? = nil, fix: (() -> Void)? = nil) {
    self.message = message
    self.fixTitle = fixTitle
    self.fix = fix
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
        .accessibilityHidden(true)
      Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if let fixTitle, let fix {
        Button(fixTitle, action: fix)
          .buttonStyle(.link)
          .font(.callout)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(AppStrings.Status.warning): \(message)")
  }
}

/// How a match is doing, as a small capsule. Scheduled matches show nothing unless `showsScheduled`.
public struct StatusBadge: View {
  let status: MatchStatus
  let showsScheduled: Bool

  public init(_ status: MatchStatus, showsScheduled: Bool = false) {
    self.status = status
    self.showsScheduled = showsScheduled
  }

  static func title(for status: MatchStatus) -> String {
    switch status {
    case .scheduled: AppStrings.Status.scheduled
    case .postponed: AppStrings.Status.postponed
    case .cancelled: AppStrings.Status.cancelled
    case .played: AppStrings.Status.played
    }
  }

  private var tint: Color {
    switch status {
    case .scheduled: .secondary
    case .postponed: .orange
    case .cancelled: .red  // red in the UI means "destructive/stopped"
    case .played: .green
    }
  }

  public var body: some View {
    if status != .scheduled || showsScheduled {
      Text(Self.title(for: status))
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(tint.opacity(0.15), in: Capsule())
        .accessibilityLabel(Self.title(for: status))
    }
  }
}

/// "In casa" or "In trasferta": a small house or car symbol, with the words as the accessibility label.
public struct HomeAwayMarker: View {
  let isHome: Bool
  let showsText: Bool

  public init(isHome: Bool, showsText: Bool = false) {
    self.isHome = isHome
    self.showsText = showsText
  }

  static func title(isHome: Bool) -> String {
    isHome ? AppStrings.Status.home : AppStrings.Status.away
  }

  public var body: some View {
    HStack(spacing: 4) {
      Image(systemName: isHome ? "house" : "car")
      if showsText {
        Text(Self.title(isHome: isHome)).font(.callout)
      }
    }
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.title(isHome: isHome))
  }
}
