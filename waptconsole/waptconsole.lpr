program waptconsole;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, pl_luicontrols, pl_bgracontrols, pl_graphics32ext,
  runtimetypeinfocontrols, uwaptconsole, uVisCreateKey, tisstrings, waptcommon,
  tiscommon, tisinifiles, dmwaptpython, uVisEditPackage, uvisoptioninifile,
  uviscreatewaptsetup, uvispassword, uvisprivatekeyauth, 
uvisloading; //uvissearchpackage;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Initialize;
  Application.CreateForm(TDMPython, DMPython);
  Application.CreateForm(TVisWaptGUI, VisWaptGUI);
  Application.Run;
end.

