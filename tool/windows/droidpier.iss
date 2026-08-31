#ifndef ReleaseVersion
  #error ReleaseVersion is required
#endif
[Setup]
AppId={{5E217890-1438-4B72-9701-E2D9B626D2B8}
AppName=DroidPier
AppVersion={#ReleaseVersion}
AppPublisher=DroidPier Contributors
AppPublisherURL=https://github.com/gysosin/droidpier
DefaultDirName={localappdata}\Programs\DroidPier
DefaultGroupName=DroidPier
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=droidpier-{#ReleaseVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\droidpier.exe
CloseApplications=yes
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\DroidPier"; Filename: "{app}\droidpier.exe"
[Run]
Filename: "{app}\droidpier.exe"; Description: "Open DroidPier"; Flags: nowait postinstall skipifsilent
