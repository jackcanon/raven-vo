#ifndef PackageRoot
  #error PackageRoot must be provided
#endif
#ifndef OutputRoot
  #error OutputRoot must be provided
#endif
[Setup]
AppId={{FEE37D52-F0EF-464A-AD95-E4FA12D69B51}
AppName=Raven VO
AppVersion=0.5.0-preview2
AppPublisher=Happy Jack Media
AppPublisherURL=https://www.ravenvo.app
DefaultDirName={localappdata}\Programs\Raven VO
DefaultGroupName=Raven VO
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputRoot}
OutputBaseFilename=Raven-VO-0.5.0-windows-preview2-x64-setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\RavenVO.exe
WizardStyle=modern
CloseApplications=yes
[Files]
Source: "{#PackageRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Raven VO"; Filename: "{app}\RavenVO.exe"; AppUserModelID: "HappyJack.RavenVO"
[Run]
Filename: "{app}\RavenVO.exe"; Description: "Open Raven VO"; Flags: nowait postinstall skipifsilent
