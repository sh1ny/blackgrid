/// Accepted capture events belong to M2. Manual inspection and history have no
/// producer for this session-only state, and storage cannot hydrate it.
class SessionScanState {
  const SessionScanState();
  bool get hasAcceptedScan => false;
  String get status => 'No accepted scan this session';
}
