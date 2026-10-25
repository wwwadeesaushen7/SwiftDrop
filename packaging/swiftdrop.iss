; Build from repository root with ISCC.exe packaging\swiftdrop.iss.
; The entire Flutter release directory is required, including data and DLLs.
#define AppVersion "0.3.0"
[Setup]
AppId={{C0CB0348-38C5-4513-96D6-271C878AF1CB}
AppName=SwiftDrop
AppVersion={#AppVersion}
AppPublisher=SwiftDrop
DefaultDirName={localappdata}\Programs\SwiftDrop
DefaultGroupName=SwiftDrop
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=SwiftDrop-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\swiftdrop.exe
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\SwiftDrop"; Filename: "{app}\swiftdrop.exe"
Name: "{autodesktop}\SwiftDrop"; Filename: "{app}\swiftdrop.exe"; Tasks: desktopicon
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\swiftdrop.exe"; Description: "Launch SwiftDrop"; Flags: nowait postinstall skipifsilent
