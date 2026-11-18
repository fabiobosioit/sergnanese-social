import SSCore
import SwiftUI

/// A form row that shows the validation problem of `field` under the control. Use it inside a `Form`
/// with the problems of `Validatable.validate()`.
public struct ValidatedField<Content: View>: View {
  let title: String
  let problems: [FieldProblem]
  let field: ValidationField
  let content: Content

  public init(
    _ title: String, problems: [FieldProblem], field: ValidationField, @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.problems = problems
    self.field = field
    self.content = content()
  }

  public var body: some View {
    LabeledContent(title) {
      VStack(alignment: .leading, spacing: 4) {
        content
        if let message = problems.message(for: field) {
          ProblemText(message)
        }
      }
    }
  }
}

/// A validation message in small text. Red here means "this value is wrong".
public struct ProblemText: View {
  let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var body: some View {
    Label(message, systemImage: "exclamationmark.circle")
      .font(.caption)
      .foregroundStyle(.red)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(message)
  }
}

extension View {
  /// Shows the problem of `field`, if any, under this view.
  public func fieldProblem(_ problems: [FieldProblem], for field: ValidationField) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      self
      if let message = problems.message(for: field) {
        ProblemText(message)
      }
    }
  }

  /// Asks before a destructive action: a standard confirmation dialog with a destructive button and
  /// Cancel (Esc). Routine saves never use it.
  public func confirmDelete(
    _ title: String, isPresented: Binding<Bool>, message: String? = nil, confirmTitle: String? = nil,
    onConfirm: @escaping () -> Void
  ) -> some View {
    confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
      Button(confirmTitle ?? AppStrings.Common.delete, role: .destructive, action: onConfirm)
      Button(AppStrings.Common.cancel, role: .cancel) {}
    } message: {
      Text(message ?? AppStrings.Delete.cannotUndo)
    }
  }
}
