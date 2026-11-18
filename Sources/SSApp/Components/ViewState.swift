import SwiftUI

/// Use `@ViewState` instead of `@State` in every view of this package.
///
/// With only the Command Line Tools, the SDK declares `State` twice: as the property-wrapper struct
/// and as a macro implemented by the `SwiftUIMacros` plugin, which ships with Xcode only. `@State`
/// resolves to the macro and fails to compile ("plugin for module 'SwiftUIMacros' not found").
/// A typealias to the struct has no macro of the same name, so it compiles everywhere and behaves
/// exactly like `@State`. (`@Entry` has the same problem: use `FocusedValueKey` and
/// `EnvironmentKey` types instead.)
public typealias ViewState<Value> = SwiftUI.State<Value>
