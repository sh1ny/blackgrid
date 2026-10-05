# blackgrid

blackgrid application. Minimal Flutter scaffold targeting **Windows desktop only**.

## Prerequisites

- Windows 11, Git, and [mise](https://mise.jdx.dev/).
- Visual Studio with **Desktop development with C++**, its CMake tools, and a Windows SDK. See [Flutter's Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).
- Windows Developer Mode when native plugins require build-time symlinks.

Flutter **3.47.6** (including Dart **3.13.5**) and git-cliff **2.14.2** are pinned in `mise.toml`. No global Flutter installation is required.

## Setup and run

```text
mise trust mise.toml
mise install
mise exec -- flutter pub get
mise exec -- flutter doctor -v
mise exec -- flutter run -d windows
```

Warnings about unselected Android or web tooling do not block Windows development. Do not enable additional platforms just to silence those warnings.

Build the Windows release bundle:

```text
mise exec -- flutter build windows
```

The executable is `build/windows/x64/runner/Release/blackgrid.exe`; distribute the complete release directory, not just the executable.

## Development

| Command | Purpose |
| --- | --- |
| `mise run analyze` | Flutter static analysis |
| `mise run test` | Flutter tests |
| `mise run format` | Format Dart source |
| `mise run format:check` | Check formatting without modifying files |
| `mise run changelog` | Regenerate `CHANGELOG.md` from local Git history, offline |
| `mise run release-notes` | Print changelog entries without the project heading |

The widget test checks that the placeholder remains visible in a compact window with large accessibility text.

## Changelog and release notes

Use conventional commits: `feat`, `fix`, `perf`, `docs`, `refactor`, `test`, `build`, `ci`, `chore`, and `style`. Breaking changes use `!` or a `BREAKING CHANGE:` footer. Merge commits are excluded; other commits remain under **Other**.

Release tags must be strict, `v`-prefixed semantic versions, such as `v1.0.0` or `v1.2.3-beta.1`. These commands generate text only; they do not create tags, releases, or remotes.

```text
mise run changelog
mise run release-notes -- --unreleased
mise run release-notes -- --latest
mise run release-notes -- -- v0.1.0..v0.2.0
```

Use a range only after both tags exist. Before the first commit, the small dependency-free `tool/changelog.dart` runner supplies an empty JSON context because git-cliff cannot traverse an unborn branch. The changelog contains **Unreleased**; release notes are empty until history exists.

## AI tooling

- `.omp/mcp.json` launches the [official Dart MCP server](https://dart.dev/tools/mcp-server) through mise using the pinned Dart and Flutter SDKs. CLI and Flutter lifecycle capabilities are enabled. The Windows launch command uses built-in PowerShell and isolates the server's tool cache under ignored `.dart_tool/dart-data/`.
- `.omp/skills/` contains 10 first-party Flutter skills and 7 first-party Dart skills. Source commits, file hashes, and licenses are recorded alongside them in `UPSTREAM.json`, `LICENSE.flutter`, and `LICENSE.dart`.
- Sources: [flutter/agent-plugins](https://github.com/flutter/agent-plugins) and [dart-lang/skills](https://github.com/dart-lang/skills). These are guidance, not installed application packages or architecture decisions.
- Restart or reload OMP after setup so it discovers the repository-local server and skills. Approve only the tools and project roots needed for your work.
- The official [`skills` package](https://pub.dev/packages/skills) **1.0.3** was used to inspect `flutter`, `flutter_test`, and `flutter_lints`; none supplied package skills. Its current generic-agent installer targets `.agents/skills/`, not `.omp/skills/`, so discovery was run in a disposable copy of the dependency workspace. No duplicate skill directory or extra project dependency was added.
