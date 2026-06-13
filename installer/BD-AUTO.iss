#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyPayloadDir
  #define MyPayloadDir "..\payload"
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
Source: "{#MyPayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\INSTALL-NOTICE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD-PARTY-NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SIGNING.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VERSION"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{app}\bin"; Permissions: users-modify
Name: "{app}\BetterDiscord"; Permissions: users-modify
Name: "{app}\logs"; Permissions: users-modify
Name: "{app}\runtime"; Permissions: users-modify

[Icons]
Name: "{autodesktop}\Repair BetterDiscord"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1"" -ForceRepair -RestoreStash -ReopenDiscord"; WorkingDir: "{app}"
Name: "{group}\Repair BetterDiscord"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -ExecutionPolicy Bypass -File ""{app}\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1"" -ForceRepair -RestoreStash -ReopenDiscord"; WorkingDir: "{app}"
Name: "{group}\BD-AUTO Logs"; Filename: "{app}\runtime\logs"
Name: "{group}\View BD-AUTO Status"; Filename: "{sys}\notepad.exe"; Parameters: """{app}\BD-AUTO-STATUS.txt"""; WorkingDir: "{app}"
Name: "{group}\Installation Summary"; Filename: "{sys}\notepad.exe"; Parameters: """{app}\runtime\install-summary.txt"""; WorkingDir: "{app}"
Name: "{group}\Uninstall BD-AUTO"; Filename: "{uninstallexe}"
Name: "{group}\BD-AUTO on GitHub"; Filename: "{#MyAppURL}"
Name: "{group}\Third-Party Notices"; Filename: "{sys}\notepad.exe"; Parameters: """{app}\THIRD-PARTY-NOTICES.md"""; WorkingDir: "{app}"
Name: "{group}\Signing and Windows Warnings"; Filename: "{sys}\notepad.exe"; Parameters: """{app}\SIGNING.md"""; WorkingDir: "{app}"

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\BetterDiscordWatchdog\Remove-BetterDiscord-WatchdogTask.ps1"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "RemoveWatchdogTask"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\bin"
Type: filesandordirs; Name: "{app}\BetterDiscord"
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\BetterDiscordWatchdog\logs"
Type: filesandordirs; Name: "{app}\BetterDiscordWatchdog\backups"
Type: files; Name: "{app}\BetterDiscordWatchdog\state.json"
Type: filesandordirs; Name: "{app}\runtime"
Type: dirifempty; Name: "{app}\BetterDiscordWatchdog"
Type: dirifempty; Name: "{app}"

[Code]
var
  CustomSetupExitCode: Integer;

function GetCustomSetupExitCode: Integer;
begin
  Result := CustomSetupExitCode;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PowerShellPath: String;
  Parameters: String;
  Summary: AnsiString;
  TaskWarning: String;
begin
  if CurStep = ssPostInstall then
  begin
    PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    Parameters :=
      '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass ' +
      '-File "' + ExpandConstant('{app}\Install-BD-AUTO.ps1') + '" -SkipTaskInstall -SkipShortcuts';

    if (not ExecAsOriginalUser(PowerShellPath, Parameters, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode)) or
       (ResultCode <> 0) then
    begin
      CustomSetupExitCode := 10;
      RaiseException(
        'BD-AUTO per-user setup could not finish.' + #13#10 +
        'PowerShell exit code: ' + IntToStr(ResultCode) + #13#10 +
        'Review the installer log in C:\Tools\BD-AUTO\logs.'
      );
    end;

    Parameters :=
      '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass ' +
      '-File "' + ExpandConstant('{app}\BetterDiscordWatchdog\Install-BetterDiscord-WatchdogTask.ps1') + '" ' +
      '-ProfileStatePath "' + ExpandConstant('{app}\runtime\target-profile.json') + '"';

    if (not Exec(PowerShellPath, Parameters, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode)) or
       (ResultCode <> 0) then
    begin
      TaskWarning :=
        '' + #13#10 + #13#10 +
        'WARNING: Scheduled repair automation could not be installed.' + #13#10 +
        'The core BetterDiscord installation remains usable.' + #13#10 +
        'Use the Repair BetterDiscord desktop or Start Menu shortcut after a Discord update.' + #13#10 +
        'Task setup exit code: ' + IntToStr(ResultCode);
    end;

    if not LoadStringFromFile(ExpandConstant('{app}\runtime\install-summary.txt'), Summary) then
      Summary := 'BD-AUTO core installation completed. Review C:\Tools\BD-AUTO\logs for details.';

    if not WizardSilent then
      SuppressibleMsgBox(
        String(Summary) + TaskWarning,
        mbInformation,
        MB_OK,
        IDOK
      );
  end;
end;
