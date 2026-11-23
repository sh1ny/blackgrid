# 0049 - Screenshot cleanup requires a live, unclaimed ending

- Status: accepted
- Source: `add-screenshot-cleanup` pre-ship review and owner decisions
- Supersedes ADR-0048 only for raid admission, identity retention, and folder resolution.

## Decision

Cleanup requires Blackgrid to observe the raid's original start live. Startup and reset replay do not enroll raids; opening Blackgrid mid-raid or reconstructing the raid only from a reconnect leaves its files alone. A game reconnect during the same Blackgrid run retains an enrolled original start. The ending must be fresh and after opt-in; a client restart uses the publishing queue for freshness, not for opt-in. An atomic SQLite insert claims the original start before the first move. A duplicate or failed claim moves no files; a failed claim is shown. Claims survive restart, settings import and statistics clearing. A partial cleanup is not retried. Disabling before the first dispatch stops preparation; already dispatched cleanup can finish.

The log reader tracks existing application and backend bytes by snapshot offset. Bind, rewrite and unknown-origin input establish a replay baseline before any record can count as live. Deferred reads retain that boundary. Only newly appended records (or records in a provably new session) qualify; log time alone cannot establish provenance.

Resolve the saved screenshot directory when cleanup starts, not from the watcher's previous binding. One absolute path serves listing and recycling. The player controls the configured path, including Windows junction resolution. Select direct regular files by the game basename and inclusive modification-time rule, reject leaf links and traversal, and use the Recycle Bin only. Concurrent replacement of a selected regular basename is an accepted limitation; no identity locking or staging. All other ADR-0048 recycling and cancellation rules remain in force.
