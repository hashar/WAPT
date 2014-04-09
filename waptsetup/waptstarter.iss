#define waptsetup 
#define default_repo_url "http://wapt.tranquil.it/wapt"
#define default_wapt_server ""
#define default_update_period "120"
#define default_update_maxruntime "30"
#define AppName "WAPTStarter"
#define output_dir "."
#define Company "Tranquil IT Systems"
#define signtool "kSign /d $qWAPT Client$q /du $qhttp://www.tranquil-it-systems.fr$q $f"

#include "wapt.iss"

[Files]
; sources of installer to rebuild a custom installer
Source: "innosetup\*"; DestDir: "{app}\waptsetup\innosetup";
Source: "wapt.iss"; DestDir: "{app}\waptsetup";
Source: "waptsetup.iss"; DestDir: "{app}\waptsetup";
Source: "services.iss"; DestDir: "{app}\waptsetup";
Source: "..\wapt.ico"; DestDir: "{app}";

[Setup]
OutputBaseFilename=waptstarter
DefaultDirName={pf}\wapt

[Tasks]
Name: use_hostpackages; Description: "Use automatic host management based on hostname packages"; Flags: unchecked;

[INI]
Filename: {app}\wapt-get.ini; Section: global; Key: repo_url; String: {#default_repo_url};
Filename: {app}\wapt-get.ini; Section: global; Key: use_hostpackages; String: "1"; Tasks: use_hostpackages;
Filename: {app}\wapt-get.ini; Section: global; Key: use_hostpackages; String: "0"; Tasks: not use_hostpackages;


