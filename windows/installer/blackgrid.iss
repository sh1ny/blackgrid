; Blackgrid per-user installer (ADR-0025). Compiled only by
; `mise run package:release`, which passes every define below with /D.
;
; Invariants asserted by test/tool/release/installer_script_test.dart:
; - PrivilegesRequired=lowest with no override, default {autopf}\Blackgrid.
; - AppId never changes: a new id makes the next version a second install.
; - Every [Files] entry carries ignoreversion, so any version replaces every
;   bundled file.
; - No [InstallDelete], [UninstallDelete], [UninstallRun] or [Code] section:
;   nothing outside Setup's own install log is deleted or run, so
;   %LOCALAPPDATA%\Blackgrid (the user's data) is never touched.

#ifndef AppVersion
  #error AppVersion must be defined (the SemVer display version)
#endif
#ifndef FileVersion
  #error FileVersion must be defined (major.minor.patch.build)
#endif
#ifndef SourceDir
  #error SourceDir must be defined (absolute path of the Release bundle)
#endif
#ifndef NoticesFile
  #error NoticesFile must be defined (absolute path of THIRD_PARTY_NOTICES.md)
#endif
#ifndef OutputDir
  #error OutputDir must be defined (absolute path of build/release)
#endif
#ifndef OutputBaseFilename
  #error OutputBaseFilename must be defined
#endif

[Setup]
AppId={{3DBFACF4-DBDB-4BC3-A5CA-2EC50C0BB82E}
AppName=Blackgrid
AppVersion={#AppVersion}
AppVerName=Blackgrid {#AppVersion}
AppPublisher=Nikolay Bochev
VersionInfoVersion={#FileVersion}
DefaultDirName={autopf}\Blackgrid
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
CloseApplications=yes
RestartApplications=no
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\blackgrid.exe
UninstallDisplayName=Blackgrid
WizardStyle=modern
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#NoticesFile}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Blackgrid"; Filename: "{app}\blackgrid.exe"
Name: "{autodesktop}\Blackgrid"; Filename: "{app}\blackgrid.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\blackgrid.exe"; Description: "{cm:LaunchProgram,Blackgrid}"; Flags: postinstall nowait skipifsilent unchecked
