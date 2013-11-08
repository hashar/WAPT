unit tiscommon;
{ -----------------------------------------------------------------------
#    This file is part of WAPT
#    Copyright (C) 2013  Tranquil IT Systems http://www.tranquil.it
#    WAPT aims to help Windows systems administrators to deploy
#    setup and update applications on users PC.
#
#    Part of this file is based on JEDI JCL library
#
#    WAPT is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    WAPT is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with WAPT.  If not, see <http://www.gnu.org/licenses/>.
#
# -----------------------------------------------------------------------
}

{$mode objfpc}{$H+}

interface

uses
  interfaces,Classes, SysUtils,tisstrings,windows,jwawintype, wininet, Dialogs;

type TProgressCallback=function(Receiver:TObject;current,total:Integer):Boolean of object;

Function  Wget(const fileURL, DestFileName: Utf8String; CBReceiver:TObject=Nil;progressCallback:TProgressCallback=Nil;enableProxy:Boolean=False): boolean;
Function  Wget_try(const fileURL: Utf8String;enableProxy:Boolean=False): boolean;

function httpGetString(   url: string; enableProxy:Boolean= False): Utf8String;
procedure httpPostData(const UserAgent: string; const Server: string; const Resource: string; const Data: AnsiString; enableProxy:Boolean= False);
function SetToIgnoreCerticateErrors(oRequestHandle:HINTERNET; var aErrorMsg: string): Boolean;
function GetWinInetError(ErrorCode:Cardinal): string;
Procedure UnzipFile(ZipFilePath,OutputPath:Utf8String);
Procedure AddToUserPath(APath:Utf8String);
procedure AddToSystemPath(APath:Utf8String);

procedure UpdateCurrentApplication(fromURL:String;Restart:Boolean;restartparam:Utf8String);
procedure UpdateApplication(fromURL:String;SetupExename,SetupParams,ExeName,RestartParam:Utf8String);

function  GetApplicationVersion(FileName:Utf8String=''): Utf8String;

function GetApplicationName:AnsiString;
function GetPersonalFolder:AnsiString;
function GetAppdataFolder:AnsiString;

function Appuserinipath:AnsiString;
function GetComputerName : AnsiString;
function GetUserName : AnsiString;
function GetWorkgroupName: AnsiString;
function GetDomainName: AnsiString;

function GetCurrentUserSid: string;

function UserLogin(user,password,domain:String):THandle;
function UserDomain(htoken:THandle):String;
function OnSystemAccount: Boolean;

function GetGroups(srvName, usrName: WideString):TDynStringArray;

function SortableVersion(VersionString:String):String;

type LogLevel=(DEBUG, INFO, WARNING, ERROR, CRITICAL);
const StrLogLevel: array[DEBUG..CRITICAL] of String = ('DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL');
procedure Logger(Msg:String;level:LogLevel=WARNING);


{Const
  SECURITY_NT_AUTHORITY: TSIDIdentifierAuthority = (Value: (0, 0, 0, 0, 0, 5));
  SECURITY_BUILTIN_DOMAIN_RID = $00000020;
  DOMAIN_ALIAS_RID_ADMINS     = $00000220;
  DOMAIN_ALIAS_RID_USERS      = $00000221;
  DOMAIN_ALIAS_RID_GUESTS     = $00000222;
  DOMAIN_ALIAS_RID_POWER_USERS= $00000223;
}
const
  CSIDL_LOCAL_APPDATA = $001c;
  strnShellFolders = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders';


type
  TServiceState =
   (ssUnknown,         // Just fill the value 0
    ssStopped,         // SERVICE_STOPPED
    ssStartPending,    // SERVICE_START_PENDING
    ssStopPending,     // SERVICE_STOP_PENDING
    ssRunning,         // SERVICE_RUNNING
    ssContinuePending, // SERVICE_CONTINUE_PENDING
    ssPausePending,    // SERVICE_PAUSE_PENDING
    ssPaused);         // SERVICE_PAUSED

  TServiceStates = set of TServiceState;

const
  ssPendingStates = [ssStartPending, ssStopPending, ssContinuePending, ssPausePending];

function UserInGroup(Group :DWORD) : Boolean;
function IsAdminLoggedOn: Boolean;
function ProcessExists(ExeFileName: string): boolean;
function KillTask(ExeFileName: string): integer;
function CheckOpenPort(dwPort : Word; ipAddressStr:AnsiString;timeout:integer=5):boolean;
function GetIPFromHost(const HostName: string): string;

function RunTask(cmd: utf8string;var ExitStatus:integer;WorkingDir:utf8String=''): utf8string;

function GetSystemProductName: String;
function GetSystemManufacturer: String;
function GetBIOSVendor: String;
function GetBIOSVersion: String;
function GetBIOSDate:String;

function GetServiceStatusByName(const AServer,AServiceName:string):TServiceState;
function StartServiceByName(const AServer,AServiceName: String):Boolean;
function StopServiceByName(const AServer, AServiceName: String):Boolean;

var
  loghook : procedure(logmsg:String) of object;

const
    currentLogLevel:LogLevel=WARNING;

implementation

uses registry,strutils,FileUtil,Process,zipper,
    shlobj,winsock,JwaTlHelp32,jwalmwksta,jwalmapibuf,JwaWinBase,jwalmaccess,jwalmcons,jwalmerr,JwaWinNT,jwawinuser,IdURI;

function IsAdminLoggedOn: Boolean;
{ Returns True if the logged-on user is a member of the Administrators local
  group. Always returns True on Windows 9x/Me. }
const
  DOMAIN_ALIAS_RID_ADMINS = $00000220;
begin
  Result := UserInGroup(DOMAIN_ALIAS_RID_ADMINS);
end;

Function Wget(const fileURL, DestFileName: Utf8String; CBReceiver:TObject=Nil;progressCallback:TProgressCallback=Nil;enableProxy:Boolean=False): boolean;
 const
   BufferSize = 1024*512;
 var
   hSession, hURL: HInternet;
   Buffer: array[1..BufferSize] of Byte;
   BufferLen: DWORD;
   f: File;
   sAppName: Utf8string;
   Size: Integer;
   total:DWORD;
   totalLen:DWORD;
   dwindex: cardinal;
   dwcode : array[1..20] of char;
   dwCodeLen : DWORD;
   res : PChar;

begin
  result := false;
  sAppName := ExtractFileName(ParamStr(0)) ;
  if enableProxy then
      hSession := InternetOpenW(PWideChar(UTF8Decode(sAppName)), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0)
  else
      hSession := InternetOpenW(PWideChar(UTF8Decode(sAppName)), INTERNET_OPEN_TYPE_DIRECT, nil, nil, 0) ;
  try
    hURL := InternetOpenUrlW(hSession, PWideChar(UTF8Decode(fileURL)), nil, 0, INTERNET_FLAG_RELOAD+INTERNET_FLAG_PRAGMA_NOCACHE+INTERNET_FLAG_KEEP_CONNECTION, 0) ;
    if assigned(hURL) then
    try
      dwIndex  := 0;
      dwCodeLen := SizeOf(dwcode);
      totalLen := SizeOf(totalLen);
      HttpQueryInfo(hURL, HTTP_QUERY_STATUS_CODE, @dwcode, dwcodeLen, dwIndex);
      HttpQueryInfo(hURL, HTTP_QUERY_CONTENT_LENGTH or HTTP_QUERY_FLAG_NUMBER, @total,totalLen, dwIndex);
      res := pchar(@dwcode);
      if (res ='200') or (res ='302') then
      begin
        Size:=0;
        try
          AssignFile(f, UTF8Decode(DestFileName)) ;
          try
            Rewrite(f,1) ;
            repeat
              BufferLen:= 0;
              if InternetReadFile(hURL, @Buffer, SizeOf(Buffer), BufferLen) then
              begin
                inc(Size,BufferLen);
                BlockWrite(f, Buffer, BufferLen);
                if Assigned(progressCallback) then
                  if not progressCallback(CBReceiver,size,total) then
                  begin
                    BufferLen:=0;
                    raise Exception.Create('Download stopped by user');
                  end;
              end;
            until BufferLen = 0;
          finally
            CloseFile(f);
          end;

        except
          If FileExists(DestFileName) then
            FileUtil.DeleteFileUTF8(DestFileName);
          raise;
        end;
        result := (Size>0);
      end
      else
        raise Exception.Create('Unable to download: "'+fileURL+'", HTTP Status:'+res);
    finally
      InternetCloseHandle(hURL)
    end
  finally
    InternetCloseHandle(hSession)
  end
end;

function wget_try(const fileURL: Utf8String;enableProxy:Boolean= False): boolean;
 const
   BufferSize = 1024;
 var
   hSession, hURL: HInternet;
   Buffer: array[1..BufferSize] of Byte;
   BufferLen: DWORD;
   sAppName: Utf8string;
   dwindex: cardinal;
   dwcode : array[1..20] of char;
   dwCodeLen : DWORD;
   dwNumber: DWORD;
   res : PChar;

begin
  result := false;
  sAppName := ExtractFileName(ParamStr(0)) ;
  if enableProxy then
    hSession := InternetOpenW(PWideChar(UTF8Decode(sAppName)), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0)
  else
    hSession := InternetOpenW(PWideChar(UTF8Decode(sAppName)), INTERNET_OPEN_TYPE_DIRECT, nil, nil, 0);

  try
    hURL := InternetOpenUrlW(hSession, PWideChar(UTF8Decode(fileURL)), nil, 0, INTERNET_FLAG_RELOAD+INTERNET_FLAG_PRAGMA_NOCACHE+INTERNET_FLAG_KEEP_CONNECTION , 0) ;
    if assigned(hURL) then
    try
      dwIndex  := 0;
      dwCodeLen := 10;
      HttpQueryInfo(hURL, HTTP_QUERY_STATUS_CODE, @dwcode, dwcodeLen, dwIndex);
      res := pchar(@dwcode);
      dwNumber := sizeof(Buffer)-1;
      result :=  (res ='200') or (res ='302');
    finally
      InternetCloseHandle(hURL)
    end
  finally
    InternetCloseHandle(hSession)
  end
end;


// récupère une chaine de caractères en http en utilisant l'API windows
function httpGetString(url: string; enableProxy:Boolean= False): Utf8String;
var
  GlobalhInet,hFile,hConnect: HINTERNET;
  localFile: File;
  buffer: array[1..1024] of byte;
  flags,bytesRead,dwError,port : DWORD;
  pos:integer;
  dwindex,dwcodelen,dwread,dwNumber: cardinal;
  dwcode : array[1..20] of char;
  res    : pchar;
  doc,error: String;
  uri :TIdURI;

begin
  result := '';
  GlobalhInet:=Nil;
  hConnect := Nil;
  hFile:=Nil;
  if enableProxy then
     GlobalhInet := InternetOpen('wapt',INTERNET_OPEN_TYPE_PRECONFIG,nil,nil,0)
  else
     GlobalhInet := InternetOpen('wapt',INTERNET_OPEN_TYPE_DIRECT,nil,nil,0);
  try
    uri := TIdURI.Create(url);
    BEGIN
      if uri.Port<>'' then
        port := StrToInt(uri.Port)
      else
        if (uri.Protocol='https') then
          port := INTERNET_DEFAULT_HTTPS_PORT
        else
          port := INTERNET_DEFAULT_HTTP_PORT;

      hConnect := InternetConnect(GlobalhInet, PChar(uri.Host), port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
      flags := INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_PRAGMA_NOCACHE or INTERNET_FLAG_RELOAD;
      if uri.Protocol='https' then
        flags := flags or INTERNET_FLAG_SECURE;
      doc := uri.Path+uri.document;
      if uri.params<>'' then
        doc:= doc+'?'+uri.Params;
      hFile := HttpOpenRequest(hConnect, 'GET', PChar(doc), HTTP_VERSION, nil, nil,flags , 0);
      if not HttpSendRequest(hFile, nil, 0, nil, 0) then
      begin
        ErrorCode:=GetLastError;
        if (ErrorCode = ERROR_INTERNET_INVALID_CA) then
        begin
          SetToIgnoreCerticateErrors(hFile, url);
          if not HttpSendRequest(hFile, nil, 0, nil, 0) then
            Raise Exception.Create('Unable to send request to '+url+' error code '+IntToStr(GetLastError));
        end;
      end;
    end;

    if Assigned(hFile) then
    try
      dwIndex  := 0;
      dwCodeLen := 10;
      if HttpQueryInfo(hFile, HTTP_QUERY_STATUS_CODE, @dwcode, dwcodeLen, dwIndex) then
      begin
        res := pchar(@dwcode);
        dwNumber := sizeof(Buffer)-1;
        if (res ='200') or (res ='302') then
        begin
          Result:='';
          pos:=1;
          repeat
            FillChar(buffer,SizeOf(buffer),0);
            InternetReadFile(hFile,@buffer,SizeOf(buffer),bytesRead);
            SetLength(Result,Length(result)+bytesRead+1);
            Move(Buffer,Result[pos],bytesRead);
            inc(pos,bytesRead);
          until bytesRead = 0;
        end
        else
           raise Exception.Create('Unable to download: '+URL+#13#10+'HTTP Status:'+res+#13#10+'error code '+IntToStr(GetLastError));
      end
      else
         raise Exception.Create('Unable to download: '+URL+#13#10+'error code '+IntToStr(GetLastError));
    finally
      if Assigned(hFile) then
        InternetCloseHandle(hFile);
    end
    else
       raise Exception.Create('Unable to download: "'+URL+'" '+GetWinInetError(GetLastError));

  finally
    uri.Free;
    if Assigned(hConnect) then
      InternetCloseHandle(hConnect);
    if Assigned(GlobalhInet) then
      InternetCloseHandle(GlobalhInet);
  end;
end;

function GetWinInetError(ErrorCode:Cardinal): string;
const
   winetdll = 'wininet.dll';
var
  Len: Integer;
  Buffer: PChar;
begin
  Len := FormatMessage(
  FORMAT_MESSAGE_FROM_HMODULE or FORMAT_MESSAGE_FROM_SYSTEM or
  FORMAT_MESSAGE_ALLOCATE_BUFFER or FORMAT_MESSAGE_IGNORE_INSERTS or  FORMAT_MESSAGE_ARGUMENT_ARRAY,
  Pointer(GetModuleHandle(winetdll)), ErrorCode, 0, @Buffer, SizeOf(Buffer), nil);
  try
    while (Len > 0) and {$IFDEF UNICODE}(CharInSet(Buffer[Len - 1], [#0..#32, '.'])) {$ELSE}(Buffer[Len - 1] in [#0..#32, '.']) {$ENDIF} do Dec(Len);
    SetString(Result, Buffer, Len);
  finally
    LocalFree(HLOCAL(Buffer));
  end;
end;

function SetToIgnoreCerticateErrors(oRequestHandle:HINTERNET; var aErrorMsg: string): Boolean;
var
  vDWFlags: DWord;
  vDWFlagsLen: DWord;
begin
  Result := False;
  try
    vDWFlagsLen := SizeOf(vDWFlags);
    if not InternetQueryOption(oRequestHandle, INTERNET_OPTION_SECURITY_FLAGS, @vDWFlags, vDWFlagsLen) then begin
      ShowMessage(IntToStr(GetLastError()));
      aErrorMsg := 'Internal error in SetToIgnoreCerticateErrors when trying to get wininet flags.' + GetWininetError(GetLastError);
      Exit;
    end;
    vDWFlags := vDWFlags or SECURITY_FLAG_IGNORE_UNKNOWN_CA or SECURITY_FLAG_IGNORE_CERT_DATE_INVALID or SECURITY_FLAG_IGNORE_CERT_CN_INVALID or SECURITY_FLAG_IGNORE_REVOCATION;
    if not InternetSetOption(oRequestHandle, INTERNET_OPTION_SECURITY_FLAGS, @vDWFlags, vDWFlagsLen) then begin
      aErrorMsg := 'Internal error in SetToIgnoreCerticateErrors when trying to set wininet INTERNET_OPTION_SECURITY_FLAGS flag .' + GetWininetError(GetLastError);
      Exit;
    end;
    Result := True;
  except
    on E: Exception do begin
      aErrorMsg := 'Unknown error in SetToIgnoreCerticateErrors.' + E.Message;
    end;
  end;
end;

procedure httpPostData(const UserAgent: string; const Server: string; const Resource: string; const Data: AnsiString; enableProxy:Boolean= False);
var
  hInet: HINTERNET;
  hHTTP: HINTERNET;
  hReq: HINTERNET;
const
  wall : WideString = '*/*';
  accept: packed array[0..1] of LPWSTR = (@wall, nil);
  header: string = 'Content-Type: application/x-www-form-urlencoded';
begin
  if enableProxy then
     hInet := InternetOpen(PChar(UserAgent),INTERNET_OPEN_TYPE_PRECONFIG,nil,nil,0)
  else
     hInet := InternetOpen(PChar(UserAgent),INTERNET_OPEN_TYPE_DIRECT,nil,nil,0);
  try
    hHTTP := InternetConnect(hInet, PChar(Server), INTERNET_DEFAULT_HTTP_PORT, nil, nil, INTERNET_SERVICE_HTTP, 0, 1);
    try
      hReq := HttpOpenRequest(hHTTP, PChar('POST'), PChar(Resource), nil, nil, @accept, 0, 1);
      try
        if not HttpSendRequest(hReq, PChar(header), length(header), PChar(Data), length(Data)) then
          raise Exception.Create('HttpOpenRequest failed. ' + SysErrorMessage(GetLastError));
      finally
        InternetCloseHandle(hReq);
      end;
    finally
      InternetCloseHandle(hHTTP);
    end;
  finally
    InternetCloseHandle(hInet);
  end;
end;

function GetSystemProductName: String;
const
  WinNT_REG_PATH = 'HARDWARE\DESCRIPTION\System\BIOS';
  WinNT_REG_KEY  = 'SystemProductName';
var
  reg : TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey:=HKEY_LOCAL_MACHINE;
    if reg.OpenKey(WinNT_REG_PATH,False) then
       Result := reg.ReadString(WinNT_REG_KEY)
    else
        Result :='';
  finally
    reg.Free;
  end;
end;

function GetSystemManufacturer: String;
const
  WinNT_REG_PATH = 'HARDWARE\DESCRIPTION\System\BIOS';
  WinNT_REG_KEY  = 'SystemManufacturer';
var
  reg : TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey:=HKEY_LOCAL_MACHINE;
    if reg.OpenKey(WinNT_REG_PATH,False) then
       Result := reg.ReadString(WinNT_REG_KEY)
    else
        Result :='';
  finally
    reg.Free;
  end;
end;

function GetBIOSVendor: String;
const
  WinNT_REG_PATH = 'HARDWARE\DESCRIPTION\System\BIOS';
  WinNT_REG_KEY  = 'BIOSVendor';
var
  reg : TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey:=HKEY_LOCAL_MACHINE;
    if reg.OpenKey(WinNT_REG_PATH,False) then
       Result := reg.ReadString(WinNT_REG_KEY)
    else
        Result :='';
  finally
    reg.Free;
  end;
end;

function GetBIOSVersion: String;
const
  WinNT_REG_PATH = 'HARDWARE\DESCRIPTION\System\BIOS';
  WinNT_REG_PATH2 = 'HARDWARE\DESCRIPTION\System';
  WinNT_REG_KEY  = 'BIOSVersion';
  WinNT_REG_KEY2  = 'SystemBiosVersion';
var
  reg : TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey:=HKEY_LOCAL_MACHINE;
    if reg.OpenKey(WinNT_REG_PATH,False) then
       Result := reg.ReadString(WinNT_REG_KEY)
    else
        Result :='';
  finally
    reg.Free;
  end;
end;

function GetBIOSDate: String;
const
  WinNT_REG_PATH = 'HARDWARE\DESCRIPTION\System';
  WinNT_REG_KEY  = 'SystemBiosDate';
  Win9x_REG_PATH = 'Enum\Root\*PNP0C01\0000';
  Win9x_REG_KEY  = 'BiosDate';
var
  RegStr: string;
  RegSeparator: Char;
  R:TRegistry;
begin
  Result := '';
  R :=  TRegistry.Create;
  try
    R.RootKey:=HKEY_LOCAL_MACHINE;
    if Win32Platform = VER_PLATFORM_WIN32_NT then
      if R.OpenKey(WinNT_REG_PATH,False) then Result := R.ReadString(WinNT_REG_KEY)
    else
      if R.OpenKey(Win9x_REG_PATH, False) then Result := R.ReadString(Win9x_REG_KEY);
  finally
    R.Free;
  end;
end;

function UserInGroup(Group :DWORD) : Boolean;
var
  pIdentifierAuthority :TSidIdentifierAuthority;
  pSid : jwawinnt.PSID;
  IsMember    : BOOL;
begin
  pIdentifierAuthority := SECURITY_NT_AUTHORITY;
  Result := AllocateAndInitializeSid(@pIdentifierAuthority,2, SECURITY_BUILTIN_DOMAIN_RID, Group, 0, 0, 0, 0, 0, 0, pSid);
  try
    if Result then
      if not CheckTokenMembership(0, pSid, IsMember) then //passing 0 means which the function will be use the token of the calling thread.
         Result:= False
      else
         Result:=IsMember;
  finally
     FreeSid(pSid);
  end;
end;

//Unzip file to path, and return list of files as a string
Procedure UnzipFile(ZipFilePath,OutputPath:Utf8String);
var
  UnZipper: TUnZipper;
begin
  UnZipper := TUnZipper.Create;
  try
    UnZipper.FileName := ZipFilePath;
    UnZipper.OutputPath := OutputPath;
    UnZipper.Examine;
    UnZipper.UnZipAllFiles;
  finally
    UnZipper.Free;
  end;
end;

procedure AddToUserPath(APath:Utf8String);
var
  SystemPath : Utf8String;
begin
  with TRegistry.Create do
  try
    //RootKey:=HKEY_LOCAL_MACHINE;
    OpenKey('Environment',False);
    SystemPath:=ReadString('PATH');
    if pos(LowerCase(APath),LowerCase(SystemPath))=0 then
    begin
      if RightStr(SystemPath,1)<>';' then SystemPath:=SystemPath+';';
      SystemPath:=SystemPath+APath;
      if RightStr(SystemPath,1)<>';' then SystemPath:=SystemPath+';';
      WriteString('PATH',SystemPath);
    end;
  finally
    Free;
  end;
end;

procedure AddToSystemPath(APath:Utf8String);
var
  SystemPath : Utf8String;
  aresult:LongWord;
begin
  with TRegistry.Create do
  try
    RootKey:=HKEY_LOCAL_MACHINE;
    OpenKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment',False);
    SystemPath:=ReadString('Path');
    if pos(LowerCase(APath),LowerCase(SystemPath))=0 then
    begin
      if RightStr(SystemPath,1)<>';' then SystemPath:=SystemPath+';';
      SystemPath:=SystemPath+APath;
      if RightStr(SystemPath,1)<>';' then SystemPath:=SystemPath+';';
      WriteExpandString('Path',SystemPath);
      SendMessageTimeout(HWND_BROADCAST,WM_SETTINGCHANGE,0,Longint(PChar('Environment')),0,1000,aresult);
    end;
  finally
    Free;
  end;
end;

procedure UpdateCurrentApplication(fromURL:String;restart:Boolean;restartparam:Utf8String);
var
  bat: TextFile;
  tempdir,tempfn,updateBatch,fn,zipfn,version,destdir : Utf8String;
  files:TStringList;
  UnZipper: TUnZipper;
  i:integer;
begin
  Files := TStringList.Create;
  try
    Logger('Updating current application in place...');
    tempdir := fileutil.GetTempFilename(GetTempDir,'waptget');
    fn :=ExtractFileName(ParamStr(0));
    destdir := ExtractFileDir(ParamStr(0));

    tempfn := AppendPathDelim(tempdir)+fn;
    mkdir(tempdir);
    Logger('Getting new file from: '+fromURL+' into '+tempfn);
    try
      wget(fromURL,tempfn,Nil,Nil,True);
      version := GetApplicationVersion(tempfn);
      if version='' then
        raise Exception.create('no version information in downloaded file.');
      Logger(' got '+fn+' version: '+version);
      Files.Add(fn);
    except
      //trying to get a zip file instead (exe files blocked by proxy ...)
      zipfn:= AppendPathDelim(tempdir)+ChangeFileExt(fn,'.zip');
      wget(ChangeFileExt(fromURL,'.zip'),zipfn);
      Logger('  unzipping file '+zipfn);
      UnZipper := TUnZipper.Create;
      try
        UnZipper.FileName := zipfn;
        UnZipper.OutputPath := tempdir;
        UnZipper.Examine;
        UnZipper.UnZipAllFiles;
        for i := 0 to UnZipper.Entries.count-1 do
          if not UnZipper.Entries[i].IsDirectory then
            Files.Add(StringReplace(UnZipper.Entries[i].DiskFileName,'/','\',[rfReplaceAll]));
      finally
        UnZipper.Free;
      end;

      version := GetApplicationVersion(tempfn);
      if version='' then
        raise Exception.create('no version information in downloaded exe file.');
      Logger(' got '+fn+' version: '+version);
    end;

    if FileExists(tempfn) and (FileSize(tempfn)>0) then
    begin
      // small batch to replace current running application
      updatebatch := AppendPathDelim(tempdir) + 'update.bat';
      AssignFile(bat,updateBatch);
      Rewrite(bat);
      try
        Logger(' Creating update batch file '+updateBatch);
        // wait for program to terminate..
        Writeln(bat,'timeout /T 2');
        Writeln(bat,'taskkill /im '+fn+' /f');
        for i:= 0 to files.Count-1 do
        begin
          // be sure to have target directory
          if not DirectoryExists(ExtractFileDir(IncludeTrailingPathDelimiter(destdir)+files[i])) then
            MkDir(ExtractFileDir(IncludeTrailingPathDelimiter(destdir)+files[i]));
          Writeln(bat,'copy "'+IncludeTrailingPathDelimiter(tempdir)+files[i]+'" "'+IncludeTrailingPathDelimiter(destdir)+files[i]+'"');
        end;
        Writeln(bat,'cd ..');
        if restart then
          Writeln(bat,'start "" "'+ParamStr(0)+'" '+restartparam);
        Writeln(bat,'rmdir /s /q "'+tempdir+'"');
      finally
        CloseFile(bat)
      end;
      Logger(' Launching update batch file '+updateBatch);
      ShellExecute(
        0,
        'open',
        PChar( SysUtils.GetEnvironmentVariable('ComSpec')),
        PChar('/C '+ updatebatch),
        PChar(TempDir),
        SW_HIDE);
      ExitProcess(0);
    end;

  finally
    Files.Free;
  end;
end;

procedure UpdateApplication(fromURL:String;SetupExename,SetupParams,ExeName,RestartParam:Utf8String);
var
  bat: TextFile;
  tempdir,tempfn,updateBatch,zipfn,version : Utf8String;
  files:TStringList;
  UnZipper: TUnZipper;
  i:integer;
begin
  Files := TStringList.Create;
  try
    Logger('Updating application...');
    tempdir := fileutil.GetTempFilename(GetTempDir,'tis');
    if ExeName='' then
      ExeName :=ExtractFileName(ParamStr(0));

    tempfn := AppendPathDelim(tempdir)+SetupExename;
    mkdir(tempdir);
    Logger('Getting new file from: '+fromURL+' into '+tempfn);
    try
      wget(fromURL,tempfn,Nil,Nil,True);
      version := GetApplicationVersion(tempfn);
      if version='' then
        raise Exception.create('no version information in downloaded file.');
      Logger(' got '+SetupExename+' version: '+version);
      Files.Add(SetupExename);
    except
      //trying to get a zip file instead (exe files blocked by proxy ...)
      zipfn:= AppendPathDelim(tempdir)+ChangeFileExt(SetupExename,'.zip');
      wget(ChangeFileExt(fromURL,'.zip'),zipfn,Nil,Nil,True);
      Logger('  unzipping file '+zipfn);
      UnZipper := TUnZipper.Create;
      try
        UnZipper.FileName := zipfn;
        UnZipper.OutputPath := tempdir;
        UnZipper.Examine;
        UnZipper.UnZipAllFiles;
        for i := 0 to UnZipper.Entries.count-1 do
          if not UnZipper.Entries[i].IsDirectory then
            Files.Add(StringReplace(UnZipper.Entries[i].DiskFileName,'/','\',[rfReplaceAll]));
      finally
        UnZipper.Free;
      end;

      version := GetApplicationVersion(tempfn);
      if version='' then
        raise Exception.create('no version information in downloaded exe file.');
      Logger(' got '+SetupExename+' version: '+version);
    end;

    if FileExists(tempfn) and (FileSize(tempfn)>0) then
    begin
      // small batch to replace current running application
      updatebatch := AppendPathDelim(tempdir) + 'update.bat';
      AssignFile(bat,updateBatch);
      Rewrite(bat);
      try
        Logger(' Creating update batch file '+updateBatch);
        // wait for program to terminate..
        Writeln(bat,'timeout /T 2');
        Writeln(bat,'taskkill /im '+Exename+' /f');
        Writeln(bat,'"'+IncludeTrailingPathDelimiter(tempdir)+SetupExename+'" '+SetupParams);
        Writeln(bat,'cd ..');
        if RestartParam<>'' then
          Writeln(bat,'start "" "'+ParamStr(0)+'" '+restartparam);
        Writeln(bat,'rmdir /s /q "'+tempdir+'"');
      finally
        CloseFile(bat)
      end;
      Logger(' Launching update batch file '+updateBatch);
      ShellExecute(
        0,
        'open',
        PChar( SysUtils.GetEnvironmentVariable('ComSpec')),
        PChar('/C '+ updatebatch),
        PChar(TempDir),
        SW_HIDE);
      ExitProcess(0);
    end;

  finally
    Files.Free;
  end;
end;


function GetUserName : AnsiString;
var
	 pcUser   : PChar;
	 dwUSize : DWORD;
begin
	 dwUSize := 21; // user name can be up to 20 characters
	 GetMem( pcUser, dwUSize ); // allocate memory for the string
	 try
			if Windows.GetUserName( pcUser, dwUSize ) then
				 Result := pcUser;
	 finally
			FreeMem( pcUser ); // now free the memory allocated for the string
	 end;
end;

procedure StrResetLength(var S: AnsiString);
var
  I: SizeInt;
begin
  for I := 1 to Length(S) do
    if S[I] = #0 then
    begin
      SetLength(S, I);
      Exit;
    end;
end;

function GetUserDomainName(const CurUser: string): AnsiString;
var
  Count1, Count2: DWORD;
  Sd: PSID; // PSecurityDescriptor; // FPC requires PSID
  Snu: SID_Name_Use;
begin
  Count1 := 0;
  Count2 := 0;
  Sd := nil;
  Snu := SIDTypeUser;
  Result := '';
  LookUpAccountName(nil, PChar(CurUser), Sd, Count1, PChar(Result), Count2, Snu);
  SetLength(Result, Count2 + 1);
  Sd := AllocMem(Count1);
  try
    if LookUpAccountName(nil, PChar(CurUser), Sd, Count1, PChar(Result), Count2, Snu) then
      StrResetLength(Result)
    else
      Result := EmptyStr;
  finally
    FreeMem(Sd);
  end;
end;

function GetWorkGroupName: AnsiString;
var
  WkstaInfo: PByte;
  WkstaInfo100: PWKSTA_INFO_100;
begin
  if NetWkstaGetInfo(nil, 100, WkstaInfo) <> 0 then
    raise Exception.Create('NetWkstaGetInfo failed');
  WkstaInfo100 := PWKSTA_INFO_100(WkstaInfo);
  Result := WkstaInfo100^.wki100_langroup;
  NetApiBufferFree(Pointer(WkstaInfo));
end;

function GetDomainName: AnsiString;
var
  hProcess, hAccessToken: THandle;
  InfoBuffer: PChar;
  AccountName: array [0..UNLEN] of Char;
  DomainName: array [0..UNLEN] of Char;

  InfoBufferSize: Cardinal;
  AccountSize: Cardinal;
  DomainSize: Cardinal;
  snu: SID_NAME_USE;
begin
  InfoBufferSize := 1000;
  AccountSize := SizeOf(AccountName);
  DomainSize := SizeOf(DomainName);

  hProcess := GetCurrentProcess;
  Result :='';
  if OpenProcessToken(hProcess, TOKEN_READ, hAccessToken) then
  try
    GetMem(InfoBuffer, InfoBufferSize);
    try
      if GetTokenInformation(hAccessToken, TokenUser, InfoBuffer, InfoBufferSize, InfoBufferSize) then
        LookupAccountSid(nil, PSIDAndAttributes(InfoBuffer)^.sid, AccountName, AccountSize,
                         DomainName, DomainSize, snu)
      else
        RaiseLastOSError;
    finally
      FreeMem(InfoBuffer)
    end;
    Result := DomainName;
  finally
    CloseHandle(hAccessToken);
  end
end;


function GetApplicationName:AnsiString;
begin
  Result := ChangeFileExt(ExtractFileName(ParamStr(0)),'');
end;

function GetSpecialFolderLocation(csidl: Integer; ForceFolder: Boolean = False ): AnsiString;
var
  i: integer;
begin
  SetLength( Result, MAX_PATH );
  if ForceFolder then
    SHGetFolderPath( 0, csidl or CSIDL_FLAG_CREATE, 0, 0, PChar( Result ))
  else
    SHGetFolderPath( 0, csidl, 0, 0, PChar( Result ));

  i := Pos( #0, Result );
  if i > 0 then SetLength( Result, Pred(i));

end;

function GetSendToFolder: AnsiString;
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create;
  Registry.RootKey := HKEY_CURRENT_USER;
  if Registry.OpenKeyReadOnly( strnShellFolders ) then
    Result := AppendPathDelim(Registry.ReadString( 'SendTo' ))
  else
    Result := '';
  Registry.Free;
end;

function GetPersonalFolder:AnsiString;
begin
  result := GetSpecialFolderLocation(CSIDL_PERSONAL)
end;

function GetAppdataFolder:AnsiString;
begin
  result :=  GetSpecialFolderLocation(CSIDL_APPDATA);
end;

function GetStartMenuFolder: Utf8String;
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create;
  Registry.RootKey := HKEY_CURRENT_USER;

  if Registry.OpenKeyReadOnly( strnShellFolders ) then
    Result := AppendPathDelim(Registry.ReadString('Start Menu'))
  else
    Result := '';

  Registry.Free;
end;

function GetStartupFolder: Utf8String;
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create;
  Registry.RootKey := HKEY_CURRENT_USER;

  if Registry.OpenKeyReadOnly( strnShellFolders ) then
    Result := AppendPathDelim(Registry.ReadString( 'Startup' ))
  else
    Result := '';
  Registry.Free;
end;

function GetCurrentUser: AnsiString;
var
  charBuffer: array[0..128] of Char;
  strnBuffer: AnsiString;
  intgBufferSize: DWORD;
begin
  intgBufferSize := 128;
  SetLength( strnBuffer, intgBufferSize );
  if windows.GetUserName( charBuffer, intgBufferSize ) then
  begin
    Result := StrPas( charBuffer );
  end
  else
  begin
    Result := '';
  end;//if
end;

// to store use specific settings for this application
function Appuserinipath:AnsiString;
var
  dir : String;
begin
  dir := IncludeTrailingPathDelimiter(GetAppdataFolder)+'tisapps';
  if not DirectoryExists(dir) then
    MkDir(dir);
  Result:=IncludeTrailingPathDelimiter(dir)+GetApplicationName+'.ini';
end;

function SortableVersion(VersionString: String): String;
var
  version,tok : String;
begin
  version := VersionString;
  tok := StrToken(version,'.');
  Result :='';
  repeat
    if tok[1] in ['0'..'9'] then
      Result := Result+FormatFloat('0000',StrToInt(tok))
    else
      Result := Result+tok;
    tok := StrToken(version,'.');
  until tok='';
end;

procedure Logger(Msg: String;level:LogLevel=WARNING);
begin
  if level>=currentLogLevel then
  begin
    if IsConsole then
      WriteLn(Msg)
    else
      if Assigned(loghook) then
        loghook(Msg);
  end;
end;

function GetComputerName : AnsiString;
var
  buffer: array[0..255] of char;
  size: dword;
begin
  size := 256;
  if windows.GetComputerName(buffer, size) then
    Result := buffer
  else
    Result := ''
end;


 type
	PFixedFileInfo = ^TFixedFileInfo;
	TFixedFileInfo = record
		 dwSignature       : DWORD;
		 dwStrucVersion    : DWORD;
		 wFileVersionMS    : WORD;  // Minor Version
		 wFileVersionLS    : WORD;  // Major Version
		 wProductVersionMS : WORD;  // Build Number
		 wProductVersionLS : WORD;  // Release Version
		 dwFileFlagsMask   : DWORD;
		 dwFileFlags       : DWORD;
		 dwFileOS          : DWORD;
		 dwFileType        : DWORD;
		 dwFileSubtype     : DWORD;
		 dwFileDateMS      : DWORD;
		 dwFileDateLS      : DWORD;
	end; // TFixedFileInfo


function GetApplicationVersion(Filename:Utf8String=''): Utf8String;
var
	dwHandle, dwVersionSize : DWORD;
	strSubBlock             : String;
	pTemp                   : Pointer;
	pData                   : Pointer;
begin
  Result:='';
	if Filename='' then
    FileName:=ParamStr(0);
	 strSubBlock := '\';

	 // get version information values
	 dwVersionSize := GetFileVersionInfoSizeW( PWideChar( UTF8Decode(FileName) ), // pointer to filename string
																						dwHandle );        // pointer to variable to receive zero

	 // if GetFileVersionInfoSize is successful
	 if dwVersionSize <> 0 then
	 begin
			GetMem( pTemp, dwVersionSize );
			try
				 if GetFileVersionInfo( PChar( FileName ),             // pointer to filename string
																dwHandle,                      // ignored
																dwVersionSize,                 // size of buffer
																pTemp ) then                   // pointer to buffer to receive file-version info.

						if VerQueryValue( pTemp,                           // pBlock     - address of buffer for version resource
															PChar( strSubBlock ),            // lpSubBlock - address of value to retrieve
															pData,                           // lplpBuffer - address of buffer for version pointer
															dwVersionSize ) then             // puLen      - address of version-value length buffer
							 with PFixedFileInfo( pData )^ do
								Result:=IntToSTr(wFileVersionLS)+'.'+IntToSTr(wFileVersionMS)+
											'.'+IntToStr(wProductVersionLS)+'.'+IntToStr(wProductVersionMS);
			finally
				 FreeMem( pTemp );
			end; // try
	 end; // if dwVersionSize
end;


function ProcessExists(ExeFileName: string): boolean;
{description checks if the process is running. Adapted for freepascal from:
URL: http://www.swissdelphicenter.ch/torry/showcode.php?id=2554}
var
  ContinueLoop: BOOL;
  FSnapshotHandle: THandle;
  FProcessEntry32: TProcessEntry32;
begin
  FSnapshotHandle := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  FProcessEntry32.dwSize := SizeOf(FProcessEntry32);
  ContinueLoop := Process32First(FSnapshotHandle, FProcessEntry32);
  Result := False;

  while integer(ContinueLoop) <> 0 do
  begin
    if ((UpperCase(ExtractFileName(FProcessEntry32.szExeFile)) =
      UpperCase(ExeFileName)) or (UpperCase(FProcessEntry32.szExeFile) =
      UpperCase(ExeFileName))) then
    begin
      Result := True;
    end;
    ContinueLoop := Process32Next(FSnapshotHandle, FProcessEntry32);
  end;
  CloseHandle(FSnapshotHandle);
end;

function KillTask(ExeFileName: string): integer;
const
 PROCESS_TERMINATE=$0001;
var
 ContinueLoop: BOOL;
 FSnapshotHandle: THandle;
 FProcessEntry32: TProcessEntry32;
begin
 result := 0;

 FSnapshotHandle := CreateToolhelp32Snapshot
           (TH32CS_SNAPPROCESS, 0);
 FProcessEntry32.dwSize := Sizeof(FProcessEntry32);
 ContinueLoop := Process32First(FSnapshotHandle,
                 FProcessEntry32);

 while integer(ContinueLoop) <> 0 do
 begin
  if ((UpperCase(ExtractFileName(
            FProcessEntry32.szExeFile)) =
     UpperCase(ExeFileName)) or
    (UpperCase(FProcessEntry32.szExeFile) =
     UpperCase(ExeFileName))) then

   Result := Integer(TerminateProcess(OpenProcess(
            PROCESS_TERMINATE, BOOL(0),
            FProcessEntry32.th32ProcessID), 0));

  ContinueLoop := Process32Next(FSnapshotHandle,
                 FProcessEntry32);
 end;

 CloseHandle(FSnapshotHandle);
end;

// from http://theroadtodelphi.wordpress.com/2010/02/21/checking-if-a-tcp-port-is-open-using-delphi-and-winsocks/
function PortTCP_IsOpen(dwPort : Word; ipAddressStr:AnsiString) : boolean;
var
  client : sockaddr_in;
  sock   : Integer;

  ret    : Integer;
  wsdata : WSAData;
begin
 Result:=False;
 ret := WSAStartup($0002, wsdata); //initiates use of the Winsock DLL
  if ret<>0 then exit;
  try
    client.sin_family      := AF_INET;  //Set the protocol to use , in this case (IPv4)
    client.sin_port        := htons(dwPort); //convert to TCP/IP network byte order (big-endian)
    client.sin_addr.s_addr := inet_addr(PAnsiChar(ipAddressStr));  //convert to IN_ADDR  structure
    sock  :=socket(AF_INET, SOCK_STREAM, 0);    //creates a socket
    Result:=connect(sock,client,SizeOf(client))=0;  //establishes a connection to a specified socket
  finally
    WSACleanup;
  end;
end;

function GetIPFromHost(const HostName: string): string;
type
  TaPInAddr = array[0..10] of PInAddr;
  PaPInAddr = ^TaPInAddr;
var
  phe: PHostEnt;
  pptr: PaPInAddr;
  i: Integer;
  GInitData: TWSAData;
begin
  WSAStartup($101, GInitData);
  Result := '';
  phe := GetHostByName(PChar(HostName));
  if phe = nil then Exit;
  pPtr := PaPInAddr(phe^.h_addr_list);
  i := 0;
  while pPtr^[i] <> nil do
  begin
    Result := inet_ntoa(pptr^[i]^);
    Inc(i);
  end;
  WSACleanup;
end;

function RunTask(cmd: utf8string;var ExitStatus:integer;WorkingDir:utf8String=''): utf8string;
var
  AProcess: TProcess;
  AStringList: TStringList;
begin
    AProcess := TProcess.Create(nil);
    AStringList := TStringList.Create;
    try
      AProcess.CommandLine := cmd;
      if WorkingDir<>'' then
        AProcess.CurrentDirectory := ExtractFilePath(cmd);
      AProcess.Options := AProcess.Options + [poStderrToOutPut, poWaitOnExit, poUsePipes];
      AProcess.Execute;
      while AProcess.Running do;
      AStringList.LoadFromStream(AProcess.Output);
      Result := AStringList.Text;
      ExitStatus:= AProcess.ExitStatus;
    finally
      AStringList.Free;
      AProcess.Free;
    end;
end;


function CheckOpenPort(dwPort : Word; ipAddressStr:AnsiString;timeout:integer=5):boolean;
var
  St:TDateTime;
  ip:String;
begin
  ip := GetIPFromHost(ipAddressStr);
  St := Now;
  While not PortTCP_IsOpen(dwPort,ip) and (Now-St<timeout/24/3600) do
    Sleep(1000);
  Result:=PortTCP_IsOpen(dwPort,ip);
end;

procedure ResetMemory(out P; Size: Longint);
begin
  if Size > 0 then
  begin
    Byte(P) := 0;
    FillChar(P, Size, 0);
  end;
end;


// From JCL library
function GetServiceStatusByName(const AServer,AServiceName:string):TServiceState;
var
  ServiceHandle,
  SCMHandle: DWORD;
  SCMAccess,Access:DWORD;
  ServiceStatus: TServiceStatus;
begin
  Result:=ssUnknown;

  SCMAccess:=SC_MANAGER_CONNECT or SC_MANAGER_ENUMERATE_SERVICE or SC_MANAGER_QUERY_LOCK_STATUS;
  Access:=SERVICE_INTERROGATE or GENERIC_READ;

  SCMHandle:= OpenSCManager(PChar(AServer), Nil, SCMAccess);
  if SCMHandle <> 0 then
  try
    ServiceHandle:=OpenService(SCMHandle,PChar(AServiceName),Access);
    if ServiceHandle <> 0 then
    try
      ResetMemory(ServiceStatus, SizeOf(ServiceStatus));
      if QueryServiceStatus(ServiceHandle,ServiceStatus) then
        Result:=TServiceState(ServiceStatus.dwCurrentState);
    finally
      CloseServiceHandle(ServiceHandle);
    end;
  finally
    CloseServiceHandle(SCMHandle);
  end;
end;

function StartServiceByName(const AServer,AServiceName: String):Boolean;
var
  ServiceHandle,
  SCMHandle: DWORD;
  p: PChar;
begin
  p:=nil;
  Result:=False;

  SCMHandle:= OpenSCManager(PChar(AServer), nil, SC_MANAGER_ALL_ACCESS);
  if SCMHandle <> 0 then
  try
    ServiceHandle:=OpenService(SCMHandle,PChar(AServiceName),SERVICE_ALL_ACCESS);
    if ServiceHandle <> 0 then
      Result:=StartService(ServiceHandle,0,p);

    CloseServiceHandle(ServiceHandle);
  finally
    CloseServiceHandle(SCMHandle);
  end;
end;

function StopServiceByName(const AServer, AServiceName: String):Boolean;
var
  ServiceHandle,
  SCMHandle: DWORD;
  SS: _Service_Status;
begin
  Result := False;

  SCMHandle := OpenSCManager(PChar(AServer), nil, SC_MANAGER_ALL_ACCESS);
  if SCMHandle <> 0 then
  try
    ServiceHandle := OpenService(SCMHandle, PChar(AServiceName), SERVICE_ALL_ACCESS);
    if ServiceHandle <> 0 then
    begin
      ResetMemory(SS, SizeOf(SS));
      Result := ControlService(ServiceHandle, SERVICE_CONTROL_STOP, SS);
    end;

    CloseServiceHandle(ServiceHandle);
  finally
    CloseServiceHandle(SCMHandle);
  end;
end;

function GetGroups(srvName, usrName: WideString):TDynStringArray;
var
  dwEntriesRead, dwEntriesTotal: DWORD;
  grpi0: Pointer;
  pInfo: PGroupInfo0;
  nErr: Integer;
begin
  SetLength(Result,0);
  nErr := NetUserGetGroups(PWideChar(srvName), PWideChar(usrName), 0, grpi0,MAX_PREFERRED_LENGTH, @dwEntriesRead, @dwEntriesTotal);
  if nErr = NERR_SUCCESS then
  begin
    pInfo := grpi0;
    while dwEntriesRead > 0 do
    begin
      SetLength(result,length(result)+1);
      result[length(result)-1] := pInfo^.grpi0_name;
      Inc(pInfo);
      Dec(dwEntriesRead);
    end;
    NetAPIBufferFree(grpi0);
  end;
end;

function UserLogin(user,password,domain:String):THandle;
var
  htok:THandle;
begin
  if not LogonUser(pchar(user),pchar(domain),pchar(password),LOGON32_LOGON_NETWORK,LOGON32_PROVIDER_DEFAULT,htok) then
    raise EXCEPTION.Create('Unable to login as '+user+' on domain '+domain);
  result := htok;
end;

function OnSystemAccount(): Boolean;
begin
  Result := GetCurrentUserSid='S-1-5-18';
end;

function UserDomain(htoken:THandle):String;
var
  cbBuf: Cardinal;
  ptiUser: PTOKEN_USER;
  snu: SID_NAME_USE;
  ProcessHandle: THandle;
  UserSize, DomainSize: DWORD;
  bSuccess: Boolean;
  user,domain:String;
begin
  Result := '';
  bSuccess := GetTokenInformation(hToken, TokenUser, nil, 0, cbBuf);
  ptiUser  := nil;
  while (not bSuccess) and (GetLastError = ERROR_INSUFFICIENT_BUFFER) do
  begin
    ReallocMem(ptiUser, cbBuf);
    bSuccess := GetTokenInformation(hToken, TokenUser, ptiUser, cbBuf, cbBuf);
  end;

  if not bSuccess then
  begin
    Exit;
  end;

  UserSize := 0;
  DomainSize := 0;
  LookupAccountSid(nil, ptiUser^.User.Sid, nil, UserSize, nil, DomainSize, snu);
  if (UserSize <> 0) and (DomainSize <> 0) then
  begin
    SetLength(User, UserSize);
    SetLength(Domain, DomainSize);
    if LookupAccountSid(nil, ptiUser^.User.Sid, PChar(User), UserSize,
      PChar(Domain), DomainSize, snu) then
    begin
      User := StrPas(PChar(User));
      Domain := StrPas(PChar(Domain));
      Result := Domain;
    end;
  end;

  if bSuccess then
  begin
    FreeMem(ptiUser);
  end;
end;

// From http://www.swissdelphicenter.ch/torry/showcode.php?id=2095
function ConvertSid(Sid: PSID; pszSidText: PChar; var dwBufferLen: DWORD): BOOL;
var
  psia: PSIDIdentifierAuthority;
  dwSubAuthorities: DWORD;
  dwSidRev: DWORD;
  dwCounter: DWORD;
  dwSidSize: DWORD;
begin
  Result := False;

  dwSidRev := SID_REVISION;

  if not IsValidSid(Sid) then Exit;

  psia := GetSidIdentifierAuthority(Sid);

  dwSubAuthorities := GetSidSubAuthorityCount(Sid)^;

  dwSidSize := (15 + 12 + (12 * dwSubAuthorities) + 1) * SizeOf(Char);

  if (dwBufferLen < dwSidSize) then
  begin
    dwBufferLen := dwSidSize;
    SetLastError(ERROR_INSUFFICIENT_BUFFER);
    Exit;
  end;

  StrFmt(pszSidText, 'S-%u-', [dwSidRev]);

  if (psia^.Value[0] <> 0) or (psia^.Value[1] <> 0) then
    StrFmt(pszSidText + StrLen(pszSidText),
      '0x%.2x%.2x%.2x%.2x%.2x%.2x',
      [psia^.Value[0], psia^.Value[1], psia^.Value[2],
      psia^.Value[3], psia^.Value[4], psia^.Value[5]])
  else
    StrFmt(pszSidText + StrLen(pszSidText),
      '%u',
      [DWORD(psia^.Value[5]) +
      DWORD(psia^.Value[4] shl 8) +
      DWORD(psia^.Value[3] shl 16) +
      DWORD(psia^.Value[2] shl 24)]);

  dwSidSize := StrLen(pszSidText);

  for dwCounter := 0 to dwSubAuthorities - 1 do
  begin
    StrFmt(pszSidText + dwSidSize, '-%u',
      [GetSidSubAuthority(Sid, dwCounter)^]);
    dwSidSize := StrLen(pszSidText);
  end;

  Result := True;
end;

function ObtainTextSid(hToken: THandle; pszSid: PChar;
  var dwBufferLen: DWORD): BOOL;
var
  dwReturnLength: DWORD;
  dwTokenUserLength: DWORD;
  tic: TTokenInformationClass;
  ptu: Pointer;
begin
  Result := False;
  dwReturnLength := 0;
  dwTokenUserLength := 0;
  tic := TokenUser;
  ptu := nil;

  if not GetTokenInformation(hToken, tic, ptu, dwTokenUserLength,
    dwReturnLength) then
  begin
    if GetLastError = ERROR_INSUFFICIENT_BUFFER then
    begin
      ptu := HeapAlloc(GetProcessHeap, HEAP_ZERO_MEMORY, dwReturnLength);
      if ptu <> nil then
      try
        dwTokenUserLength := dwReturnLength;
        dwReturnLength    := 0;
        if not GetTokenInformation(hToken, tic, ptu, dwTokenUserLength,
          dwReturnLength) then Exit;
        if not ConvertSid((PTokenUser(ptu)^.User).Sid, pszSid, dwBufferLen) then Exit;
        Result := True;
      finally
        if ptu <> Nil then
          HeapFree(GetProcessHeap, 0, ptu);
      end;
    end
    else
      Exit;
  end;

end;

function GetCurrentUserSid: string;
var
  hAccessToken: THandle;
  bSuccess: BOOL;
  dwBufferLen: DWORD;
  szSid: array[0..260] of Char;
begin
  Result := '';

  bSuccess := OpenThreadToken(GetCurrentThread, TOKEN_QUERY, True,
    hAccessToken);
  if not bSuccess then
  begin
    if GetLastError = ERROR_NO_TOKEN then
      bSuccess := OpenProcessToken(GetCurrentProcess, TOKEN_QUERY,
        hAccessToken);
  end;
  if bSuccess then
  begin
    ZeroMemory(@szSid, SizeOf(szSid));
    dwBufferLen := SizeOf(szSid);

    if ObtainTextSid(hAccessToken, szSid, dwBufferLen) then
      Result := szSid;
    CloseHandle(hAccessToken);
  end;
end;


end.

