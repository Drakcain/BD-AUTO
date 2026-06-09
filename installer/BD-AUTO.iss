#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "BD-AUTO"
#define MyAppPublisher "Drakcain"
#define MyAppURL "https://github.com/Drakcain/BD-AUTO"

[Setup]
AppId={{539AD200-27B0-4D2E-99A9-66EC953E2649}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName=C:\Tools\BD-AUTO
DefaultGroupName=BD-AUTO
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=BD-AUTO-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
InfoBeforeFile=..\INSTALL-NOTICE.txt
SetupLogging=yes
Uninstallable=yes
UninstallDisplayName=BD-AUTO
MinVersion=10.0.17763

[Files]
Source: "..\payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\INSTALL-NOTICE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD-PARTY-NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\Repair BetterDiscord"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1"" -ForceRepair -ReopenDiscord"; WorkingDir: "{app}"
Name: "{group}\Repair BetterDiscord"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1"" -ForceRepair -ReopenDiscord"; WorkingDir: "{app}"
Name: "{group}\Uninstall BD-AUTO"; Filename: "{uninstallexe}"
Name: "{group}\BD-AUTO on GitHub"; Filename: "{#MyAppURL}"
Name: "{group}\Third-Party Notices"; Filename: "{sys}\notepad.exe"; Parameters: """{app}\THIRD-PARTY-NOTICES.md"""; WorkingDir: "{app}"

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\BetterDiscordWatchdog\Remove-BetterDiscord-WatchdogTask.ps1"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "RemoveWatchdogTask"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\bin"
Type: filesandordirs; Name: "{app}\BetterDiscord"
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\BetterDiscordWatchdog\logs"
Type: filesandordirs; Name: "{app}\BetterDiscordWatchdog\backups"
Type: files; Name: "{app}\BetterDiscordWatchdog\state.json"
Type: dirifempty; Name: "{app}\BetterDiscordWatchdog"
Type: dirifempty; Name: "{app}"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
  if not FileExists(ExpandConstant('{localappdata}\Discord\Update.exe')) then
  begin
    MsgBox(
      'Discord Stable was not found.' + #13#10 + #13#10 +
      'Install and launch Discord Stable once, then run BD-AUTO Setup again.',
      mbError,
      MB_OK
    );
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PowerShellPath: String;
  Parameters: String;
begin
  if CurStep = ssPostInstall then
  begin
    PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    Parameters :=
      '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass ' +
      '-File "' + ExpandConstant('{app}\Install-BD-AUTO.ps1') + '" -SkipShortcuts';

    if (not Exec(PowerShellPath, Parameters, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode)) or
       (ResultCode <> 0) then
    begin
      RaiseException(
        'BD-AUTO setup could not finish.' + #13#10 +
        'PowerShell exit code: ' + IntToStr(ResultCode) + #13#10 +
        'Review the installer log in C:\Tools\BD-AUTO\logs.'
      );
    end;
  end;
end;
