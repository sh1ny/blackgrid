# 0007 - Windows boundary: runner method channel and standalone FFI DLLs, DPAPI current-user tokens

- Status: accepted
- Date: 2026-10-06 (M1 PR #3; FFI DLL in M5, PR #7)
- Source: [implementation strategy §7](../IMPLEMENTATION_STRATEGY.md#7-windows-integration-strategy), [§8](../IMPLEMENTATION_STRATEGY.md#8-data-and-persistence-strategy)

## Context and problem

Blackgrid needs a few Windows services: protecting Tracker tokens, the LocalAppData path, atomic file replace and native OCR. Windows code must stay narrow: no matching, pricing or recommendation logic. Tokens must never be stored in plaintext.

## Decision

- **No Flutter plugin packages.** `generated_plugins.cmake` lists none.
- **Runner method channel.** The runner registers one channel, `blackgrid/credentials`, with `localDataPath`, `atomicReplace`, `protect` and `unprotect` (`windows/runner/credential_protector.cpp:32-107`; `flutter_window.cpp:28`).
- **DPAPI.** `CryptProtectData` runs in current-user scope with no LOCAL_MACHINE flag and `CRYPTPROTECT_UI_FORBIDDEN` (`:92-98`). Buffers are zeroed afterwards.
- **Token files.** Ciphertext goes to `%LOCALAPPDATA%\Blackgrid\credentials\<mode>.dpapi`: written to a temp file, then `MoveFileExW(REPLACE_EXISTING|WRITE_THROUGH)`. There is no plaintext fallback (`lib/data/credential_store.dart:44-109`).
- **Heavy native work** goes in standalone, hash-bound FFI DLLs built by the Windows CMake project (ADR-0006).

## Rejected alternative

- **A federated Flutter Windows plugin package** for credentials, input and capture. It adds packaging and a plugin registrant with no benefit to a single-platform app.
- **Storing tokens in SQLite or settings.** Rejected: plaintext at rest.

## Consequences

- **Small native surface,** owned in this repository.
- **Scope.** This decision covers the implemented credentials channel and panel-OCR DLL. Input, capture and hotkeys do not exist yet; the change that builds them decides their packaging (runner, DLL or plugin).
- **Tokens are bound to the Windows user.** A different user, or a machine move, needs the token re-entered.
- **Reversal cost: low.** It is one channel and one DLL behind Dart adapters.
