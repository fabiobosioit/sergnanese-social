import SwiftUI

/// Previous / label / next, plus "Questo weekend". Put it in a toolbar. The weekend is the shared
/// one of `AppModel`, so Partite, Genera and Archivio always agree.
public struct WeekendSwitcher: View {
  let model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    HStack(spacing: 2) {
      Button {
        model.goToPreviousWeekend()
      } label: {
        Label(AppStrings.Weekend.previous, systemImage: "chevron.left")
          .labelStyle(.iconOnly)
      }
      .help(AppStrings.Weekend.previous)
      .accessibilityLabel(AppStrings.Weekend.previous)

      Button {
        model.goToThisWeekend()
      } label: {
        HStack(spacing: 6) {
          Text(model.weekendLabel)
            .monospacedDigit()
          if model.isThisWeekend {
            Text(AppStrings.Weekend.thisWeekend)
              .foregroundStyle(.secondary)
          }
        }
      }
      .help(AppStrings.Weekend.thisWeekendHelp)
      .accessibilityLabel(
        model.isThisWeekend
          ? "\(AppStrings.Weekend.thisWeekend), \(model.weekendLabel)"
          : "\(AppStrings.Weekend.switcher) \(model.weekendLabel). \(AppStrings.Weekend.thisWeekendHelp)")

      Button {
        model.goToNextWeekend()
      } label: {
        Label(AppStrings.Weekend.next, systemImage: "chevron.right")
          .labelStyle(.iconOnly)
      }
      .help(AppStrings.Weekend.next)
      .accessibilityLabel(AppStrings.Weekend.next)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(AppStrings.Weekend.switcher)
  }
}
