unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  AppEvnts,
  // �t�@�C���̏����擾�ƃt�@�C�����s
  SHELLAPI,
  // �V���[�g�J�b�g�̏����擾
  ActiveX, ComObj, ShlObj, ExtCtrls,
  // �\���֌W
  CommCtrl, // ImageList
  // ��DPI�Ή�
  Math;

const AW_ACTIVATE = $20000;
const AW_BLEND = $80000;
const INTERRUPTED_LISTUP = 'interrupted listup';

type
  TItem = class(TObject)
  private
    function GetFullPath:WideString;
    function GetCount: Integer;
  public
    // �t�@�C�����
    Dir: WideString;
    Filename: WideString;
    IsDir: Boolean;
    LnkPath: WideString;
    // ���X�g�A�C�e�����
    Index: Integer;
    Icon: HIcon;
    CaptionW: WideString;
    Enabled: Boolean;
    Selected: Boolean;
    Items: array of TItem;
    SelectedItem: TItem;
    TextWidth: Integer;
    Top: Integer;
    Bottom: Integer;
    BoundsWidth: Integer;
    BoundsHeight: Integer;
    // ���X�g�A�C�e���X�V���
    IsListuped: boolean;
    property Count: Integer read GetCount;
    property FullPath:WideString read GetFullPath;
    function IsLnk: Boolean;
    procedure SetupItems(Dir: WideString; Filename: WideString = WideString('*.*'));
    procedure SetupShellLinkInfo(Item: TItem);
  end;

type
  THintWindowW = class(THintWindow)
  protected
    procedure Paint; override;
end;

type
  TMainForm = class(TForm)
    ApplicationEvents1: TApplicationEvents;
    Image1: TImage;
    ScrollBox1: TScrollBox;
    Timer1: TTimer;
    procedure ApplicationEvents1Deactivate(Sender: TObject);
    procedure ApplicationEvents1Message(var Msg: tagMSG; var Handled: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Image1MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Image1MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure Timer1Timer(Sender: TObject);
  private
    { Private �錾 }
    CaletIndex : Integer;
    ChildForm: TMainForm;
    FSelectedIndex: Integer;
    LastMousePoint: TPoint;
    ParentForm: TMainForm;
    function GetCount: Integer;
    function GetItem(Index: Integer): TItem;
    function GetSElectedIndex: Integer;
    function GetSelectedItem: TItem;
    function Select(Index: Integer): Boolean;
    procedure DrawItem(Item: TItem);
    procedure Execute();
    procedure HideChildForms;
    procedure Popup(LT: TPoint; RB: TPoint);
    procedure ResetTimer(ReselectParent: boolean = False);
    procedure SetItem(Index: Integer; Value: TItem);
    procedure SetSelectedItem(Value: TItem);
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TItem read GetItem write SetItem;
    property SelectedIndex: Integer read GetSelectedIndex;
    property SelectedItem: TItem read GetSelectedItem write SetSelectedItem;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    { Public �錾 }
    Root: TItem;
    procedure Start;
  end;

var
  MainForm: TMainForm;
  HintW: WideString;
  HiFG: TColor;
  HiBG: TColor;
  FG: TColor;
  BG: TColor;
  Maxcount: Integer;
  ShouldOpenShellLink: Boolean;
  StopFlag: boolean;
  BusyCount: Integer;
  ViMode: boolean;
  Prefix: WideString;
  ICON_SIZE: Integer;
  ITEM_HEIGHT: Integer;
  TEXT_LEFT: Integer;
  MAX_WIDTH: Integer;
  PADDING: Integer;

implementation

{$R *.dfm}

///////////////////////////////////////
// ���[�e�B���e�B
///////////////////////////////////////
function StrngToColor(S:string; Default:TColor): TColor;
begin
  Result := Default;
  if (S <> '') and (S <> 'default') then
  try
    if S[1] = '#' then
    begin
      if Length(S) = 4 then
        Result := Graphics.StringToColor('$00' + S[4] + S[4] + S[3] + S[3] + S[2] + S[2])
      else
        Result := Graphics.StringToColor('$00' + S[6] + S[7] + S[4] + S[5] + S[2] + S[3]);
    end else
      Result := Graphics.StringToColor('cl' + S);
  finally
  end;
end;

function TrimRightW(W: WideString): WideString;
begin
  Result := TrimRight(W);
  if Pos(#0, Result) <> 0 then
    Result := Copy(Result, 1, Pos(#0, Result) - 1);
end;

function GetCurrentDirW: WideString;
var W: WideString;
begin
  SetLength(W, MAX_PATH);
  GetCurrentDirectoryW(MAX_PATH, PWideChar(W));
  Result := TrimRightW(W);
end;

function GetDpiZoom(ACanvas: TCanvas): Extended;
var
  FontSizeBackup, PxSize: Integer;
  R: TRect;
begin
  FontSizeBackup := ACanvas.Font.Size;
  try
    ACanvas.Font.Size := 9;
    R := Rect(0, 0, 100, 100);
    PxSize := DrawText(
      ACanvas.Handle,
      PChar('Aj'),
      -1,
      R,
      DT_WORDBREAK or DT_CALCRECT or DT_NOPREFIX
  );
    Result := PxSize / 16;
  finally
    ACanvas.Font.size := FontSizeBackup;
  end;
end;

///////////////////////////////////////
// TItem
///////////////////////////////////////
function TItem.GetFullPath: WideString;
begin
  Result := Dir + '\' + Filename;
end;
function TItem.GetCount: Integer;
begin
  Result := Length(Items);
end;
function TItem.IsLnk;
begin
  Result := Copy(Filename, Length(Filename) - 3, 4) = '.lnk';
end;


///////////////////////////////////////
// THintWindowW
///////////////////////////////////////
procedure THintWindowW.Paint;
var R: TRect;
begin
  R := ClientRect;
  DrawTextW(Canvas.Handle, PWideChar(HintW), -1, R, DT_LEFT or DT_NOPREFIX or DT_VCENTER)
end;

///////////////////////////////////////
// TMainForm
///////////////////////////////////////
// �v���p�e�B
function TMainForm.GetItem(Index: Integer): TItem;
begin
  Result := Root.Items[Index];
end;

procedure TMainForm.SetItem(Index: Integer; Value: TItem);
begin
  Root.Items[Index] := Value;
end;

function TMainForm.GetCount: Integer;
begin
  Result := Root.Count;
end;

function TMainForm.GetSelectedItem: TItem;
begin
  Result := Root.SelectedItem;
end;

procedure TMainForm.SetSelectedItem(Value: TItem);
begin
  if Root.SelectedItem <> nil then
    Root.SelectedItem.Selected := false;
  Root.SelectedItem := Value;
  if Value <> nil then
  begin
    Value.Selected := true;
    FSelectedIndex := Value.Index;
  end else
    FSelectedIndex := -1;
end;

function TMainForm.GetSelectedIndex: Integer;
begin
  Result := FSelectedIndex;
end;

// �A�v���P�[�V�����C�x���g
procedure TMainForm.ApplicationEvents1Deactivate(Sender: TObject);
begin
  Close;
end;

// �J�n
procedure TMainForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  with Params do
    WindowClass.Style := WindowClass.Style or $00020000; // CS_DROPSHADOW;
end;

procedure TMainForm.Start;
var
  I: Integer;
  V, Opt: string;
  P: TPoint;
  NCM: TNonClientMetrics;
  Zoom: Extended;
begin
  BusyCount := 0;
  // �R���g���[�������Ȃ���N��
  if (GetKeyState(VK_SHIFT) < 0) or (GetKeyState(VK_CONTROL) < 0) then
  begin
    // �J�����g�t�H���_���G�N�X�v���[���ŊJ��
    ShellExecuteW(0, '', PWideChar(GetCurrentDirW), nil, nil, SW_SHOWNORMAL);
    Application.Terminate;
    close;
  end;

  GetAsyncKeyState(VK_RBUTTON);
  // ������
  HiFG := clHighlightText;
  HiBG := clHighlight;
  FG := clMenuText;
  BG := clMenu;
  Maxcount := 100;
  ShouldOpenShellLink := true;
  ViMode := false;
  Prefix := ';;';
  GetCursorPos(P);
  NCM.cbSize := SizeOf (NCM);
  SystemParametersInfo (SPI_GETNONCLIENTMETRICS, 0, @NCM, 0);
  Font.Name := NCM.lfMenuFont.lfFaceName;
  // �p�����[�^��t
  For I := 1 to ParamCount do
  begin
    V := ParamStr(I);
    // �P�ƃI�v�V����
    if V = '/S' then
      ShouldOpenShellLink := false
    else if V = '/vi' then
      ViMode := true
    // �p�����[�^�t���I�v�V����
    else if Pos(V, ' /X /Y /hifg /hibg /fg /bg /maxcount /prefix ') <> 0 then
      Opt := V
    else if Opt = '/X' then
      P.X := (Screen.Width + StrToInt(V)) mod Screen.Width
    else if Opt = '/Y' then
      P.Y := (Screen.Height + StrToInt(V)) mod Screen.Height
    else if Opt = '/hifg' then
      Hifg := StrngToColor(V, clHighlightText)
    else if Opt = '/hibg' then
      Hibg := StrngToColor(V, clHighlight)
    else if Opt = '/fg' then
      Fg := StrngToColor(V, clHighlightText)
    else if Opt = '/bg' then
      Bg := StrngToColor(V, clHighlight)
    else if Opt = '/maxcount' then
      Maxcount := StrToInt(V)
    else if Opt = '/prefix' then
      Prefix := V
    ;
  end;

  // ��DIP�Ή�
  Zoom := GetDpiZoom(Canvas);
  ICON_SIZE := Ceil(16 * Zoom);
  PADDING := Ceil(2 * Zoom);
  ITEM_HEIGHT := ICON_SIZE + PADDING * 2;
  TEXT_LEFT := Ceil(24 * Zoom);
  MAX_WIDTH := Ceil(300 * Zoom);

  // ����
  Width := 1; // Width��0�ɂ���Ɖe���t���Ȃ�
  Left := -1;
  Show; // Show���Ƃ��Ȃ��ƈꕔ�̃A�C�R����ǂݍ��߂Ȃ�
  // �t�@�C�������J�n
  Root := TItem.Create();
  Root.SetupItems(GetCurrentDirW);
  // �\��
  Popup(P, P);

  // �\���������Ă�Ԃɑ��̃A�v�����A�N�e�B�u�ɂȂ��Ă���I��������
  if Focused and (FindControl(GetForegroundWindow) = nil) then
    Application.Terminate;
end;

procedure TMainForm.Popup(LT: TPoint; RB: TPoint);
var
  I, L, T, W, H: Integer;
  SwpFlags: Cardinal;
begin
  // ������
  SelectedItem := nil;
  CaletIndex := -1;
  LastMousePoint := Point(-1, -1);
  ScrollBox1.AutoScroll := false;

  // �`��
  if ParentForm <> nil then
    Font := ParentForm.Font;
  Image1.Canvas.Font := Font;
  Image1.Canvas.Pixels[0, 0] := 0;
  Image1.Picture.Graphic.Width := Root.BoundsWidth;
  Image1.Picture.Graphic.Height := Root.BoundsHeight;
  W := Image1.Width;
  H := Min(Image1.Height + PADDING, Screen.Height);
  for I := 0 to Count - 1 do
    DrawItem(Items[I]);

  // �ʒu����
  DoubleBuffered := true;
  ScrollBox1.DoubleBuffered := true;
  if (LT.Y + H) < Screen.Height then
    T := LT.Y // ���܂�Ȃ牺�֕\��
  else
    T := RB.Y - H; // ���܂�Ȃ��Ȃ��֕\��
  if T < 0 then
    T := 0;
  if T + H > Screen.Height then
    H := Screen.Height - T;
  ScrollBox1.AutoScroll := Image1.Height > H;
  if ScrollBox1.AutoScroll then
    W := W + GetSystemMetrics(SM_CXVSCROLL);
  if RB.X + W < Screen.Width then
    L := RB.X
  else
    L := LT.X - W;
  if L < 0 then
    L := 0;

  // �ʒu�T�C�Y�m��ƍĕ`��
  SetWindowPos(Handle, HWND_TOPMOST, L, T, W, H, SWP_NOACTIVATE);
  AlphaBlend := false;
  Refresh;
  // �\��
  SwpFlags := SWP_SHOWWINDOW or SWP_NOSIZE or SWP_NOMOVE or SWP_NOZORDER;
  SetWindowPos(Handle, 0, 0, 0, 0, 0, SwpFlags);
  Visible := true;
end;


procedure TMainForm.HideChildForms;
begin
  if ChildForm <> nil then
  begin
    ChildForm.Timer1.Enabled := false;
    ChildForm.HideChildForms;
    ChildForm.Hide;
    ChildForm.AlphaBlendValue := 0;
    SetForegroundWindow(Handle);
  end;
end;

// �t�@�C������
procedure TItem.SetupItems(Dir: WideString; Filename: WideString = '*.*');
var
  CurrDir: WideString;
  FileHandle : THandle;
  WFD : TWin32FindDataW;
  FileInfo :TSHFileinfoW;
  IconList: Cardinal;
  I, maxWidth: Integer;
  Item: TItem;
  textRect: TRect;
  PrefixPos: Integer;
begin
  Self.IsListuped := False;
  if not SetCurrentDirectoryW(PWideChar(Dir)) then
  begin
    Self.IsListuped := True;
    exit;
  end;
  try
    Inc(BusyCount);
    StopFlag := false;
    maxWidth := 0;
    CurrDir := GetCurrentDirW;
    FileHandle := FindFirstFileW(PWideChar(Filename), WFD);
    if FileHandle <> INVALID_HANDLE_VALUE then
  try
    I := 0;
    repeat
      Application.ProcessMessages;
      if StopFlag then
        raise Exception.Create(INTERRUPTED_LISTUP);
      if (WFD.dwFileAttributes and FILE_ATTRIBUTE_SYSTEM = FILE_ATTRIBUTE_SYSTEM) then
        continue;
      if WFD.cFilename = WideString('..') then
        continue;
      if (WFD.cFileName = WideString('.')) then
        continue;
      begin
        if Maxcount <= Self.Count then break;
        // �t�@�C�����擾
        Item := TItem.Create();
        Item.Index := I;
        Item.Top := I * ITEM_HEIGHT;
        Item.Bottom := Item.Top + ITEM_HEIGHT;
        Item.Dir := dir;
        Item.Filename := WideString(WFD.cFilename);
        Item.Enabled := (ExtractFileExt(Item.Filename) <> '.___');
        if Item.Enabled then
        begin
          Item.IsDir := (WFD.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY = FILE_ATTRIBUTE_DIRECTORY);
          IconList := SHGetFileInfoW(
            PChar(Item.FileName),
            0,
            FileInfo,
            SizeOf(FileInfo),
            SHGFI_DISPLAYNAME OR SHGFI_ICON OR SHGFI_SMALLICON OR SHGFI_SYSICONINDEX
          );
          Item.CaptionW := WideString(FileInfo.szDisplayName);
          PrefixPos := Pos(Prefix, Item.CaptionW);
          if PrefixPos <> 0 then
            Item.CaptionW := Copy(Item.CaptionW, PrefixPos + Length(Prefix), Length(Item.CaptionW));
          Item.Icon := ImageList_GetIcon(IconList, FileInfo.iIcon, ILD_TRANSPARENT);
          ImageList_Destroy(IconList); // ��n��
          // �t�H���_�̃V���[�g�J�b�g�Ȃ�t�H���_�����ɂ���B
          if ShouldOpenShellLink and (not Item.IsDir) and Item.IsLnk then
            SetupShellLinkInfo(Item);
          // ��
          textRect := Rect(0, 0, 0, MainForm.Font.Size);
          DrawTextW(
            MainForm.Image1.Canvas.Handle,
            PWideChar(Item.CaptionW),
            Length(Item.CaptionW),
            textRect,
            DT_VCENTER or DT_SINGLELINE or DT_CALCRECT
          );
          Item.TextWidth := textRect.Right;
        end else
        begin
          // �Z�p���[�^
          Item.TextWidth := 50; // �ŏ���
        end;
        if maxWidth < Item.TextWidth then
          maxWidth := Item.TextWidth;
        SetLength(Self.Items, I + 1);
        Items[I] := Item;
        inc(I);
      end;
    until FindNextFileW(FileHandle, WFD) = False;
    Self.IsListuped := True;
  finally
    windows.FindClose(FileHandle);
    SetCurrentDirectoryW(PWideChar(CurrDir));
  end;
  finally
    Dec(BusyCount);
  end;

  // �`��͈�
  Self.BoundsWidth := Min(maxWidth + TEXT_LEFT * 2, MAX_WIDTH);
  Self.BoundsHeight := Self.Count * ITEM_HEIGHT;
end;

procedure TItem.SetupShellLinkInfo(Item: TItem);
var
  Win32FindDataW: TWin32FindDataW;
  Win32FindData: ^TWin32FindData;
  W: WideString;
  ShellLink: IShellLinkW;
begin
  ShellLink := CreateComObject(CLSID_ShellLink) as IShellLinkW;
  if not Succeeded((ShellLink as IPersistFile).Load(PWChar(Item.FullPath), STGM_READ)) then
    exit;
  SetLength(W, MAX_PATH);
  Win32FindData := @Win32FindDataW;
  ShellLink.Resolve(0, SLR_NO_UI);
  ShellLink.GetPath(PWideChar(W), MAX_PATH, Win32FindData^, SLGP_RAWPATH);
  if (Win32FindData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> FILE_ATTRIBUTE_DIRECTORY) then
    exit;
  Item.LnkPath := TrimRightW(W);
  Item.IsDir := true;
end;

// ���j���[���ڕ`��
procedure TMainForm.DrawItem(Item: TItem);
var
  ACanvas: TCanvas;
  TextRect, ARect: TRect;
  Middle: Integer;
begin
  ACanvas := Image1.Canvas;
  ARect := Rect(0, Item.Top, Image1.Width, Item.Bottom);
  Middle := ARect.Top + ITEM_HEIGHT div 2;

  // �F
  if Item.Selected and Item.Enabled then
  begin
    ACanvas.Brush.Color := HiBG;
    ACanvas.Pen.Color := HiFG
  end else
  begin
    ACanvas.Brush.Color := Bg;
    ACanvas.Pen.Color := Fg;
  end;
  ACanvas.Font.Color := ACanvas.Pen.Color;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.FillRect(ARect);

  // �Z�p���[�^
  if not Item.Enabled then
  begin
    ACanvas.Pen.Color := clWindowFrame;
    ACanvas.PenPos := Point(ARect.Left + 8, Middle);
    ACanvas.LineTo(ARect.Right - 8, Middle);
    exit;
  end;

  DrawIconEx(
    ACanvas.Handle,
    ARect.Left + PADDING,
    ARect.Top + PADDING,
    Item.Icon,
    ICON_SIZE,
    ICON_SIZE,
    0,
    0,
    DI_IMAGE or DI_MASK
  );

  // ����
  TextRect := Rect(ARect.Left + TEXT_LEFT, ARect.Top, ARect.Right - PADDING, ARect.Bottom);
  if Item.IsDir then
    TextRect.Right := Arect.Right - TEXT_LEFT + 3;
  DrawTextW(ACanvas.Handle,
    PWideChar(Item.CaptionW),
    Length(Item.CaptionW),
    TextRect,
    DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS
  );

  // �f�B���N�g��
  if Item.IsDir then
  begin
    ACanvas.PenPos := Point(ARect.Right - PADDING - 10 - 5, Middle - 5);
    ACanvas.LineTo(ARect.Right - PADDING - 10, Middle);
    ACanvas.LineTo(ARect.Right - PADDING - 10 - 6, Middle + 6);
  end;
end;

// �I��
function TMainForm.Select(Index: Integer): Boolean;
begin
  Result := false;
  if SelectedItem <> nil then
  begin
    if SelectedItem.Index = Index then
      exit;
    SelectedItem.Selected := false;
    DrawItem(SelectedItem);
  end;
  if Index < 0 then
  begin
    SelectedItem := nil;
    exit;
  end;
  StopFlag := true;
  SelectedItem := Items[Index];
  DrawItem(SelectedItem);
  if SelectedItem.Top < ScrollBox1.VertScrollBar.Position then
    ScrollBox1.VertScrollBar.Position := SelectedItem.Top;
  if ScrollBox1.VertScrollBar.Position < (SelectedItem.Bottom - ScrollBox1.ClientHeight) then
    ScrollBox1.VertScrollBar.Position := SelectedItem.Bottom - ScrollBox1.ClientHeight;
  if SelectedItem.TextWidth > (Width - TEXT_LEFT * 2) then
  begin
    HintWindowClass := THintWindowW;
    HintW := SelectedItem.Filename + #13#10'(' + SelectedItem.Dir + ')';
    Hint := HintW;
    Application.CancelHint;
    ShowHint := true;
  end else
    ShowHint := false;
  Result := true;
end;

// �q�t�H�[���\��
procedure TMainForm.ResetTimer(ReselectParent: Boolean);
begin
  Timer1.Enabled := false;
  if (ParentForm <> nil) and ParentForm.Timer1.Enabled then
  begin
    ParentForm.Timer1.Enabled := false;
    if ReselectParent then
      ParentForm.Select(Root.Index);
  end;
  Timer1.Enabled := true;
end;

procedure TMainForm.Timer1Timer(Sender: TObject);
var lt, rb: TPoint;
begin
  Timer1.Enabled := false;
  if (SelectedItem = nil) or not SelectedItem.IsDir then
    HideChildForms;

  if not SelectedItem.IsDir then
    exit;

  if ChildForm = nil then
  begin
    ChildForm := TMainForm.Create(Self);
    ChildForm.ParentForm := Self;
  end else
    ChildForm.HideChildForms;

  if BusyCount > 0 then
  begin
    StopFlag := true;
    ResetTimer(false);
    exit;
  end;

  if not SelectedItem.IsListuped then
  try
    if SelectedItem.LnkPath <> '' then
      SelectedItem.SetupItems(SelectedItem.LnkPath)
    else
      SelectedItem.SetupItems(SelectedItem.FullPath);
  except
    on E: Exception do if E.Message <> INTERRUPTED_LISTUP then raise E else exit;
  end;
  ChildForm.Root := SelectedItem;

  if ChildForm.Count > 0 then
  begin
    lt := Image1.ClientToScreen(Point(4, SelectedItem.Top - 1));
    rb := Image1.ClientToScreen(Point(Image1.Width -4, SelectedItem.Bottom + 1));
    ChildForm.Popup(lt, rb);
  end else if SelectedItem <> nil then
  begin
    SelectedItem.IsDir := false;
    DrawItem(SelectedItem);
    HideChildForms;
  end;
end;

// ���s
procedure TMainForm.Execute();
var
  E: Integer;
  S: string;
  W: PWideChar;
begin
  if SelectedItem = nil then
    exit;
  if ((GetAsyncKeyState(VK_RBUTTON) and 1) = 1) or (GetKeyState(VK_SHIFT) < 0) or (GetKeyState(VK_CONTROL) < 0) then
  begin
    W := PWideChar('/select,' + SelectedItem.FullPath);
    ShellExecuteW(0, nil, 'explorer.exe', W, nil, SW_SHOWNORMAL)
  end else
  begin
    SetLastError(0);
    ShellExecuteW(0, '', PWideChar(SelectedItem.Filename), nil, PWideChar(SelectedItem.Dir), SW_SHOWNORMAL);
    E := GetLastError;
    if (E <> 0) and (E <> E_PENDING) then
    begin
      if SelectedItem.IsLnk and (E = ERROR_CANCELLED) then
        E := ERROR_PATH_NOT_FOUND;
      S := SysErrorMessage(E);
      MessageBox(Handle, PChar(S), '', MB_ICONWARNING or MB_OK);
      exit;
    end;
  end;
  Application.Terminate;
end;

// �}�E�X����
procedure TMainForm.Image1MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var P: TPoint;
begin
  GetCursorPos(P);
  if (P.X = LastMousePoint.X) and (P.Y = LastMousePoint.Y) then
   exit;
  LastMousePoint.X := P.X;
  LastMousePoint.Y := P.Y;
  if Select(Y div ITEM_HEIGHT) then
    ResetTimer(true);
end;
procedure TMainForm.Image1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  Select(Y div ITEM_HEIGHT);
  Execute();
end;
procedure TMainForm.ApplicationEvents1Message(var Msg: tagMSG; var Handled: Boolean);
begin
  if Msg.message = WM_MOUSEWHEEL then
  begin
    if Msg.wParam > 0 then
    begin
      ScrollBox1.VertScrollBar.Position :=
        ScrollBox1.VertScrollBar.Position - ITEM_HEIGHT;
    end else
    begin
      ScrollBox1.VertScrollBar.Position :=
        ScrollBox1.VertScrollBar.Position + ITEM_HEIGHT;
    end;
  end;
end;

// �L�[�{�[�h����
procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
function IsInRange(I: Integer): Boolean;
begin
  Result := (0 <= I) and (I < Count);
end;
var
  I, J, D: Integer;
  K: Word;
begin
  K := Key;
  if (ssAlt in Shift) or ViMode and (Shift = []) then
  case Key of
    ord('H'): K := VK_LEFT;
    ord('J'): K := VK_DOWN;
    ord('K'): K := VK_UP;
    ord('L'): K := VK_RIGHT;
  end;
  D := 0; // �㉺�L�[�t���O
  case K of
     VK_RIGHT, VK_SPACE:
      // �f�B���N�g���Ȃ�q���J��
      if (SelectedItem <> nil) and SelectedItem.IsDir then
      begin
        Timer1Timer(Self);
        if ChildForm.Count > 0 then
        begin
          ChildForm.Select(0);
          ChildForm.CaletIndex := 0;
        end;
      end;
    VK_LEFT, VK_BACK: // ���Đe�ɖ߂�
      if ParentForm <> nil then
        ParentForm.HideChildForms
      else if Self = MainForm then
        D := - Count;
    VK_ESCAPE: Application.Terminate;
    VK_RETURN: Execute;
    VK_UP: D := -1;
    VK_DOWN: D := 1;
    ord('0')..ord('9'), ord('@')..ord('Z'):
      begin
        I := SelectedIndex;
        if not IsInRange(I) then
          I := 0;
        for J := Count downto 1 do
        begin
          I := (I + 1) mod Count;
          if I = SelectedIndex then
            exit;
          if not Items[I].Enabled then
            continue;
          if
            (UpperCase(Copy(Items[I].CaptionW, 1, 1)) = char(Key)) or
            (UpperCase(Copy(Items[I].Filename, 1, 1)) = char(Key))
          then
          begin
            Select(I);
            exit;
          end;
        end;
      end;
  end;
  // �㉺�L�[
  if D = 0 then
    exit; // �㉺�L�[�ȊO�͂�����exit
  if (SelectedIndex = -1) and (D <0) then
    I := Count
  else
    I := SelectedIndex;
  // �Z�p���[�^�̓X�L�b�v����
  repeat
    I := I + D;
  until (not IsInRange(I)) or Items[I].Enabled;
  if IsInRange(I) then
  begin
    CaletIndex := I;
    Select(CaletIndex);
  end;
end;

end.

