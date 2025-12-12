# Repository Guidelines

## Project Structure & Module Organization
The SwiftUI app resides in `JSON Assistant/`, with `JSON_AssistantApp.swift` bootstrapping the window group, `ContentView.swift` coordinating the sidebar/input/output panes, and `JSONView.swift` providing the collapsible tree renderer. Assets (logos, colors, previews) live under `JSON Assistant/Assets.xcassets` and `JSON Assistant/Preview Content/`. Unit tests sit in `JSON AssistantTests/`, while UI automation lives in `JSON AssistantUITests/`. Keep auxiliary tooling such as `buildServer.json` and `php-beautifier.php` at the repository root so IDE integrations continue to resolve them.

## Build, Test, and Development Commands
- `open "JSON Assistant.xcodeproj"` launches the project in Xcode with the shared `JSON Assistant` scheme.
- `xcodebuild -scheme "JSON Assistant" -destination 'platform=macOS' build` performs a headless debug build and surfaces compiler diagnostics.
- `xcodebuild -scheme "JSON Assistant" test` runs both unit and UI test bundles; pass `-only-testing:JSON AssistantTests/FeatureNameTests` when iterating on a single case.

## Coding Style & Naming Conventions
Follow Xcode’s default 4-space indentation and let the editor’s “Re-Indent” (`⌃I`) keep Swift block scope tidy. Use UpperCamelCase for types/releases (e.g., `JSONViewModel`), lowerCamelCase for methods and properties (e.g., `parseJSON(_:)`), and SCREAMING_SNAKE_CASE only for static configuration keys. Favor SwiftUI modifiers over imperative layout, keep view structs lightweight, and move stateful logic into observable view models. Do not edit `Package.resolved` unless dependency versions truly change.

## Testing Guidelines
Unit coverage relies on `XCTest` in `JSON AssistantTests/`; UI flows use `XCUITest` inside `JSON AssistantUITests/`. Name tests as `test<Scenario>` (e.g., `testBeautifyValidInput`), and prefer focused helpers over long fixtures. Aim to accompany every new user-facing behavior with at least one assertion-based test, and mirror crash fixes with regression cases. Execute `xcodebuild … test` locally before pushing; capture any flaky UI behaviors in the PR description.

## Commit & Pull Request Guidelines
Commits should follow Conventional Commits style: `<type>(<scope>): <subject>`, e.g., `feat(parser): add support for nested arrays`. Use `fix` for bug fixes, `docs` for documentation changes, `style` for formatting, `refactor` for code restructuring, and `test` for test-related updates. Each PR must link to an issue or feature request, include a summary of changes, and pass all CI checks before merging. Squash commits when merging to maintain a clean history.
Use https://www.conventionalcommits.org/en/v1.0.0/ for reference.

## Configuration Tips
`buildServer.json` drives Build Server Protocol clients—update the `scheme` or workspace path if the project structure moves. When adding SwiftPM dependencies, let Xcode regenerate `Package.resolved` and verify the file remains in sync across branches to avoid merge drift.
