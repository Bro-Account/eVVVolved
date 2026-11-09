; -- vvv.iss --
; install script for VVV 2.0 (evvvolved)

; packages the staged runtime folder produced by build.ps1 (..\run-x64),
; which contains the program, wxWidgets DLLs, the Firebird 5 runtime and
; the bundled Firebird 2.5 old-catalog conversion helper exactly as
; installed after a build. Build the installer AFTER running build.ps1.

#pragma option -v+
#pragma verboselevel 9

;#define Debug

#define AppName "VVV (Virtual Volumes View)"
#define ExeName "vvv.exe"
#define AppVersion "2.0"
#define StagedPath "..\run-x64"

[Setup]
; same AppId as the VVV 1.5 installer so that installing 2.0 upgrades the
; existing installation in place
AppId=VVV-fu-ku-jitsu
AppName={#AppName}
AppVerName={#AppName} version {#AppVersion}
AppVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
; always propose the native 64-bit location, even when a previous (32-bit,
; x86 folder) VVV installation is detected — the old folder is retired via
; the "delete the retired program folder" task instead of being upgraded
UsePreviousAppDir=no
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#ExeName}
VersionInfoVersion=2.0.0.0
; show the program's own GPL-2 text; the third-party license texts are
; shipped in {app}\licenses\ (see licenses\THIRD-PARTY-LICENSES.md)
LicenseFile=..\COPYING
ChangesAssociations=yes
OutputDir=.
OutputBaseFilename=VVV-2.0.0.0-Setup
; enable signing on release builds once a certificate exists:
; SignTool=signtool /d $qVVV (Virtual Volumes View)$q $f
SolidCompression=yes
Compression=lzma2/max
; the application is 64-bit: install into the native Program Files and use
; the 64-bit registry view (a plain compiler run produces a 32-bit setup
; process, which would otherwise resolve {autopf} to Program Files (x86))
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: desktopicon; Description: {cm:CreateDesktopIcon}
; offered only when VVV 1.5 is found installed (checked function below);
; deletes its retired folder instead of running its uninstaller (which would
; wipe the shared user settings)
Name: deleteold; Description: {cm:DeleteOldFolder}; Flags: checkedonce; Check: OldProgramFolderFound

[CustomMessages]
DeleteOldFolder=Delete the retired VVV 1.5 program folder (it contains only program files; run its own uninstaller instead if you kept personal files in it)

[Files]
; the whole staged runtime tree: program + wx DLLs + VC140 CRT +
; Firebird 5 runtime (incl. intl/, plugins/, tzdata/) + firebird-2.5
; conversion helper + translations + help + licenses
Source: "{#StagedPath}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs overwritereadonly

[InstallDelete]
; leftovers of the VVV 1.5 installer (Firebird 2.1 embedded + VC80 CRT at the
; app root); VVV 2.0 ships no equivalents at these locations
Type: files; Name: "{app}\fbembed.dll"
Type: files; Name: "{app}\icudt30.dll"
Type: files; Name: "{app}\icuin30.dll"
Type: files; Name: "{app}\icuuc30.dll"
Type: files; Name: "{app}\msvcp80.dll"
Type: files; Name: "{app}\msvcr80.dll"
Type: files; Name: "{app}\Microsoft.VC80.CRT.manifest"

[Icons]
Name: {commonprograms}\{#AppName}; Filename: {app}\{#ExeName}
Name: {commondesktop}\{#AppName}; Filename: {app}\{#ExeName}; Tasks: desktopicon

[Registry]
Root: HKCR; Subkey: .vvv; ValueType: string; ValueName: ; ValueData: vvvapp; Flags: uninsdeletevalue
Root: HKCR; Subkey: vvvapp; ValueType: string; ValueName: ; ValueData: {#AppName}; Flags: uninsdeletekey
Root: HKCR; Subkey: vvvapp\DefaultIcon; ValueType: string; ValueName: ; ValueData: {app}\{#ExeName},0
Root: HKCR; Subkey: vvvapp\shell\open\command; ValueType: string; ValueName: ; ValueData: """{app}\{#ExeName}"" ""%1"""
; user settings (HKCU\Software\VVV) deliberately survive a uninstall: the
; user's catalog registry and UI settings are not the program's property

[Languages]
Name: en; MessagesFile: compiler:Default.isl
Name: it; MessagesFile: compiler:Languages\Italian.isl
Name: cs; MessagesFile: compiler:Languages\Czech.isl
Name: de; MessagesFile: compiler:Languages\German.isl
Name: es; MessagesFile: compiler:Languages\Spanish.isl
Name: fr; MessagesFile: compiler:Languages\French.isl
Name: nl; MessagesFile: compiler:Languages\Dutch.isl
Name: pl; MessagesFile: compiler:Languages\Polish.isl
Name: pt; MessagesFile: compiler:Languages\Portuguese.isl
Name: ru; MessagesFile: compiler:Languages\Russian.isl

#ifdef Debug
  #expr SaveToFile(AddBackslash(SourcePath) + "Preprocessed.iss")
#endif

[Code]
// returns the folder of the previous VVV installation (Inno kept the record
// of it in its uninstall key "VVV-fu-ku-jitsu_is1"; the 1.5 installer was
// 32-bit, so its key is looked up under HKLM32, which reaches the
// Wow6432Node part of the registry on 64-bit Windows)
function OldProgramFolder(var sDir: string): Boolean;
var
  sExe: string;
begin
  Result :=
    RegQueryStringValue( HKLM32,
      'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VVV-fu-ku-jitsu_is1',
      'UninstallString', sExe ) or
    RegQueryStringValue( HKLM64,
      'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VVV-fu-ku-jitsu_is1',
      'UninstallString', sExe );
  if Result then begin
    sDir := ExtractFileDir( RemoveQuotes( sExe ) );
    Result := ( sDir <> '' ) and DirExists( sDir );
  end;
end;

// the "retired folder" task is offered only when a previous installation
// was found
function OldProgramFolderFound: Boolean;
var
  sDir: string;
begin
  Result := OldProgramFolder(sDir) and (sDir <> ExpandConstant('{app}'));
end;

// remove the retired previous program folder before copying any file;
// its uninstaller deliberately is NOT run: it would delete the shared user
// settings key HKCU\Software\VVV, which the new version still uses
procedure CurStepChanged(CurStep: TSetupStep);
var
  sDir: string;
begin
  if (CurStep = ssInstall) and WizardIsTaskSelected('deleteold') then
    if OldProgramFolder(sDir) and (sDir <> ExpandConstant('{app}')) then begin
      Log(Format('Deleting the retired previous program folder: %s', [sDir]));
      DelTree(sDir, True, True, True);
    end;
end;