#define MyAppName "OrexRay"
#define MyAppPublisher "Orex"
#define MyAppExeName "orex_ray.exe"
#ifndef MyAppVersion
  #error Pass /DMyAppVersion from pubspec.yaml as shown in docs\release-builds.md.
#endif
#ifndef MyAppVersionInfo
  #error Pass /DMyAppVersionInfo derived from pubspec.yaml as shown in docs\release-builds.md.
#endif
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{EE5EB640-8D42-4DE4-8DB7-48737F03B1CD}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\OrexRay
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\x64\installer
OutputBaseFilename=OrexRay-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UsePreviousAppDir=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersionInfo}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersionInfo}

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent runasoriginaluser
