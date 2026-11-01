/// The three EFT log files the raid lifecycle reads from a session folder.
enum LogFile {
  /// The `application` log; carries game-start, scene and session lines.
  application,

  /// The `backend` log; carries matchmaking and raid-settings lines.
  backend,

  /// The `push-notifications` log; carries multi-line notification records.
  pushNotifications,
}
