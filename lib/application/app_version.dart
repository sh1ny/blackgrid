/// The application version, injected at build time with
/// `--dart-define=BLACKGRID_VERSION=<version>`; `dev` when built without one.
const appVersion = String.fromEnvironment(
  'BLACKGRID_VERSION',
  defaultValue: 'dev',
);
