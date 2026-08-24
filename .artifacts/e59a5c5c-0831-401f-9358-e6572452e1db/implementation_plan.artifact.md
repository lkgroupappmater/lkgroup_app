# Implementation Plan - AppShell and Language Management Improvements

This plan refactors language management and optimizes `AppShell` for better performance and maintainability.

## User Review Required

> [!IMPORTANT]
> This change introduces a `LanguageController` and `LanguageScope` to manage language state globally. Screens will no longer need to receive the `language` parameter explicitly if they use the new `context.S()` extension or read from the scope.

## Proposed Changes

### Core & Controllers

#### [NEW] [language_controller.dart](file:///C:/Users/ssapd/StudioProjects/lkgroup_app/lib/controllers/language_controller.dart)
- Create a `ChangeNotifier` to manage `AppLanguage` state.
- Include persistence logic (TODO: SharedPreferences) for user preference.

#### [NEW] [language_scope.dart](file:///C:/Users/ssapd/StudioProjects/lkgroup_app/lib/widgets/language_scope.dart)
- Create an `InheritedNotifier` wrapper for `LanguageController`.
- Provide `of(context)` and `read(context)` static methods.

#### [MODIFY] [app_language.dart](file:///C:/Users/ssapd/StudioProjects/lkgroup_app/lib/core/app_language.dart)
- Add a `BuildContext` extension to simplify localization calls: `context.S(key)`.

---

### App Level

#### [MODIFY] [app.dart](file:///C:/Users/ssapd/StudioProjects/lkgroup_app/lib/app.dart)
- Instantiate `LanguageController` at the root.
- Wrap `MaterialApp` with `LanguageScope`.
- Dynamically update the global `ThemeData` based on the selected language (applying the Lao font globally if needed).

---

### Widgets & Screens

#### [MODIFY] [app_shell.dart](file:///C:/Users/ssapd/StudioProjects/lkgroup_app/lib/widgets/app_shell.dart)
- **State Removal**: Remove local `_language` state and `_onLanguageChanged` callback. Use `LanguageScope` instead.
- **Optimization**: Move tab bodies initialization to `initState` or a memoized getter to prevent unnecessary rebuilds of all tab screens when only the index changes.
- **Styling**: Replace hardcoded `Color(0xFF1565C0)` with `AppColors.accent` or `Theme.of(context).primaryColor`.
- **Refactoring**: Extract `BottomNavigationBar` items for better readability.

## Verification Plan

### Automated Tests
- N/A (Unit tests for `LanguageController` can be added if requested).

### Manual Verification
1. Open the app and verify the Home tab loads correctly.
2. Change the language in the Dashboard (Home tab) and verify all tabs (tracking, quote, account) update their labels immediately.
3. Verify the Lao font (`Phetsarath OT`) is correctly applied to all text when Lao is selected.
4. Verify that switching tabs does not cause the language to reset.
5. Verify the "Quote Request" tab's "Member Login" link correctly navigates to the Account tab.
