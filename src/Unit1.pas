unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  AppEvnts,
  // ファイルの情報を取得とファイル実行
  SHELLAPI,
  // ショートカットの情報を取得
  ActiveX, ComObj, ShlObj, ExtCtrls,
  // 表示関係
  CommCtrl, // ImageList
  // 高DPI対応
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
    // ファイル情報
    Dir: WideString;
    Filename: WideString;
    IsDir: Boolean;
    LnkPath: WideString;
    // リストアイテム情報
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
    // リストアイテム更新情報
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
    Timer1: TTimer;
    Image1: TImage;
    ScrollBox1: TScrollBox;
    procedure ApplicationEvents1Deactivate(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure Image1MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ApplicationEvents1Message(var Msg: tagMSG;
      var Handled: Boolean);
    procedure Image1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    { Private 宣言 }
    FSelectedIndex: Integer;
    CaletIndex : Integer;
    ParentForm: TMainForm;
    ChildForm: TMainForm;
    LastMousePoint: TPoint;
    function GetCount: Integer;
    function GetItem(Index: Integer): TItem;
    function GetSelectedItem: TItem;
    function GetSElectedIndex: Integer;
    function Select(Index: Integer): Boolean;
    procedure SetItem(Index: Integer; Value: TItem);
    procedure SetSelectedItem(Value: TItem);
    procedure Execute();
    procedure DrawItem(Item: TItem);
    procedure Popup(LT: TPoint; RB: TPoint);
    procedure HideChildForms;
    procedure ResetTimer(ReselectParent: boolean = False);
    property Items[Index: Integer]: TItem read GetItem write SetItem;
    property Count: Integer read GetCount;
    property SelectedItem: TItem read GetSelectedItem write SetSelectedItem;
    property SelectedIndex: Integer read GetSelectedIndex;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    { Public 宣言 }
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

implementation

{$R *.dfm}

///////////////////////////////////////
// ユーティリティ
///////////////////////////////////////
function StrngToColor(s:String; Default:TColor): TColor;
var l: Integer;
begin
  Result := Default;
  if (s <> '') and (s <> 'default') then
  try
    if s[1] = '#' then
    begin
      l := Length(s);
      if l = 4 then
        Result := Graphics.StringToColor('$00' + s[4] + s[4] + s[3] + s[3] + s[2] + s[2])
      else
        Result := Graphics.StringToColor('$00' + s[6] + s[7] + s[4] + s[5] + s[2] + s[3]);
    end else
      Result := Graphics.StringToColor('cl' + s);
  finally
  end;
end;

function TrimRightW(W: WideString): WideString;
var p: Integer;
begin
  Result := TrimRight(W);
  p := Pos(#0, Result);
  if p <> 0 then
    Result := Copy(Result, 1, Pos(#0, Result) - 1);
end;

function GetCurrentDirW: WideString;
var w: WideString;
begin
  SetLength(w, MAX_PATH);
  GetCurrentDirectoryW(MAX_PATH, PWideChar(w));
  Result := TrimRightW(w);
end;

function GetDpiZoom(ACanvas: TCanvas): Extended;
var
  b, h: Integer;
  r: TRect;
begin
  b := ACanvas.Font.Size;
  try
    ACanvas.Font.Size := 9;
    r := Rect(0, 0, 100, 100);
    h := DrawText(
      ACanvas.Handle,
      PChar('Aj'),
      -1,
      r,
      DT_WORDBREAK or DT_CALCRECT or DT_NOPREFIX
  );
    Result := h / 16;
  finally
    ACanvas.Font.size := b;
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
// プロパティ
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

// アプリケーションイベント
procedure TMainForm.ApplicationEvents1Deactivate(Sender: TObject);
begin
  Close;
end;

// 開始
procedure TMainForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  with Params do
    WindowClass.Style := WindowClass.Style or $00020000; // CS_DROPSHADOW;
end;

procedure TMainForm.Start;
var
  i: Integer;
  v, opt: String;
  p: TPoint;
  NCM: TNonClientMetrics;
  z: Extended;
begin
  BusyCount := 0;
  // コントロール押しながら起動
  if (GetKeyState(VK_SHIFT) < 0) or (GetKeyState(VK_CONTROL) < 0) then
  begin
    // カレントフォルダをエクスプローラで開く
    ShellExecuteW(0, '', PWideChar(GetCurrentDirW), nil, nil, SW_SHOWNORMAL);
    Application.Terminate;
    close;
  end;

  GetAsyncKeyState(VK_RBUTTON);
  // 初期化
  HiFG := clHighlightText;
  HiBG := clHighlight;
  FG := clMenuText;
  BG := clMenu;
  Maxcount := 100;
  ShouldOpenShellLink := true;
  ViMode := false;
  Prefix := ';;';
  GetCursorPos(p);
  NCM.cbSize := SizeOf (NCM);
  SystemParametersInfo (SPI_GETNONCLIENTMETRICS, 0, @NCM, 0);
  Font.Name := NCM.lfMenuFont.lfFaceName;
  // パラメータ受付
  For i := 1 to ParamCount do
  begin
    v := ParamStr(i);
    // 単独オプション
    if v = '/s' then
      ShouldOpenShellLink := false
    else if v = '/vi' then
      ViMode := true
    // パラメータ付きオプション
    else if Pos(v, ' /x /y /hifg /hibg /fg /bg /maxcount /prefix ') <> 0 then
      opt := v
    else if opt = '/x' then
      p.x := (Screen.Width + StrToInt(v)) mod Screen.Width
    else if opt = '/y' then
      p.y := (Screen.Height + StrToInt(v)) mod Screen.Height
    else if opt = '/hifg' then
      Hifg := StrngToColor(v, clHighlightText)
    else if opt = '/hibg' then
      Hibg := StrngToColor(v, clHighlight)
    else if opt = '/fg' then
      Fg := StrngToColor(v, clHighlightText)
    else if opt = '/bg' then
      Bg := StrngToColor(v, clHighlight)
    else if opt = '/maxcount' then
      Maxcount := StrToInt(v)
    else if opt = '/prefix' then
      Prefix := v
    ;
  end;

  // 高DIP対応
  z := GetDpiZoom(Canvas);
  ICON_SIZE := Ceil(16 * z);
  ITEM_HEIGHT := Ceil(20 * z);
  TEXT_LEFT := Ceil(24 * z);
  MAX_WIDTH := Ceil(300 * z);

  // 準備
  Width := 1; // Widthを0にすると影が付かない
  Left := -1;
  Show; // Showしとかないと一部のアイコンを読み込めない
  // ファイル検索開始
  Root := TItem.Create();
  Root.SetupItems(GetCurrentDirW);
  // 表示
  Popup(p, p);

  // 表示準備してる間に他のアプリがアクティブになってたら終了させる
  if Focused and (FindControl(GetForegroundWindow) = nil) then
    Application.Terminate;
end;

procedure TMainForm.Popup(LT: TPoint; RB: TPoint);
var
  i, l, t, w, h: Integer;
  flugs: Cardinal;
begin
  // 初期化
  SelectedItem := nil;
  CaletIndex := -1;
  LastMousePoint := Point(-1, -1);
  ScrollBox1.AutoScroll := false;

  // 描画
  if ParentForm <> nil then
    Font := ParentForm.Font;
  Image1.Canvas.Font := Font;
  Image1.Canvas.Pixels[0,0] := 0;
  Image1.Picture.Graphic.Width := Root.BoundsWidth;
  Image1.Picture.Graphic.Height := Root.BoundsHeight;
  w := Image1.Width;
  h := Min(Image1.Height + 2, Screen.Height);
  for i := 0 to Count - 1 do
    DrawItem(Items[i]);

  // 位置調整
  DoubleBuffered := true;
  ScrollBox1.DoubleBuffered := true;
  if (LT.Y + h) < Screen.Height then
    t := LT.Y // 収まるなら下へ表示
  else
    t := RB.Y - h; // 収まらないなら上へ表示
  if t < 0 then
    t := 0;
  if t + h > Screen.Height then
    h := Screen.Height - t;
  ScrollBox1.AutoScroll := Image1.Height > h;
  if ScrollBox1.AutoScroll then
    w := w + GetSystemMetrics(SM_CXVSCROLL);
  if RB.X + w < Screen.Width then
    l := RB.X
  else
    l := LT.X - w;
  if l < 0 then
    l := 0;

  // 位置サイズ確定と再描画
  SetWindowPos(Handle, HWND_TOPMOST, l, t, w, h, SWP_NOACTIVATE);
  AlphaBlend := false;
  Refresh;
  // 表示
  flugs := SWP_SHOWWINDOW or SWP_NOSIZE or SWP_NOMOVE or SWP_NOZORDER;
  SetWindowPos(Handle, 0, 0, 0, 0, 0, flugs);
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

// ファイル検索
procedure TItem.SetupItems(Dir: WideString; Filename: WideString = '*.*');
var
  currdir: WideString;
  hFile : THandle;
  wfd : TWin32FindDataW;
  shfinfo :TSHFileinfoW;
  iconList: Cardinal;
  i, maxWidth: Integer;
  Item: TItem;
  textRect: TRect;
  _Root: TItem;
  PrefixPos: Integer;
begin
  _Root := Self;
  _Root.IsListuped := False;
  if not SetCurrentDirectoryW(PWideChar(Dir)) then
  begin
    _Root.IsListuped := True;
    exit;
  end;
  try
    Inc(BusyCount);
    StopFlag := false;
    maxWidth := 0;
    currdir := GetCurrentDirW;
    hFile := FindFirstFileW(PWideChar(Filename), wfd);
    if hFile <> INVALID_HANDLE_VALUE then
  try
    i := 0;
    repeat
      Application.ProcessMessages;
      if StopFlag then
        raise Exception.Create(INTERRUPTED_LISTUP);
      if (wfd.dwFileAttributes and FILE_ATTRIBUTE_SYSTEM = FILE_ATTRIBUTE_SYSTEM) then
        continue;
      if wfd.cFilename = WideString('..') then
        continue;
      if (wfd.cFileName = WideString('.')) then
        continue;
      begin
        if Maxcount <= _Root.Count then break;
        // ファイル情報取得
        Item := TItem.Create();
        Item.Index := i;
        Item.Top := i * ITEM_HEIGHT;
        Item.Bottom := Item.Top + ITEM_HEIGHT;
        Item.Dir := dir;
        Item.Filename := WideString(wfd.cFilename);
        Item.Enabled := (ExtractFileExt(Item.Filename) <> '.___');
        if Item.Enabled then
        begin
          Item.IsDir := (wfd.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY = FILE_ATTRIBUTE_DIRECTORY);
          iconList := SHGetFileInfoW(
            PChar(Item.FileName),
            0,
            shfinfo,
            SizeOf(shfinfo),
            SHGFI_DISPLAYNAME OR SHGFI_ICON OR SHGFI_SMALLICON OR SHGFI_SYSICONINDEX
          );
          Item.CaptionW := WideString(shfInfo.szDisplayName);
          PrefixPos := Pos(Prefix, Item.CaptionW);
          if PrefixPos <> 0 then
            Item.CaptionW := Copy(Item.CaptionW, PrefixPos + Length(Prefix), Length(Item.CaptionW));
          Item.Icon := ImageList_GetIcon(iconList, shfInfo.iIcon, ILD_TRANSPARENT);
          ImageList_Destroy(iconList); // 後始末
          // フォルダのショートカットならフォルダ扱いにする。
          if ShouldOpenShellLink and (not Item.IsDir) and Item.IsLnk then
            SetupShellLinkInfo(Item);
          // 幅
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
          // セパレータ
          Item.TextWidth := 50;
        end;
        if maxWidth < Item.TextWidth then
          maxWidth := Item.TextWidth;
        SetLength(_Root.Items, i + 1);
        Items[i] := Item;
        inc(i);
      end;
    until FindNextFileW(hFile, wfd) = False;
    _Root.IsListuped := True;
  finally
    windows.FindClose(hFile);
    SetCurrentDirectoryW(PWideChar(currdir));
  end;
  finally
    Dec(BusyCount);
  end;

  // 描画範囲
  _Root.BoundsWidth := Min(maxWidth + TEXT_LEFT * 2, MAX_WIDTH);
  _Root.BoundsHeight := _Root.Count * ITEM_HEIGHT;
end;

procedure TItem.SetupShellLinkInfo(Item: TItem);
var
  Win32FindDataW: TWin32FindDataW;
  Win32FindData: ^TWin32FindData;
  w: WideString;
  ShellLink: IShellLinkW;
begin
  ShellLink := CreateComObject(CLSID_ShellLink) as IShellLinkW;
  if not Succeeded((ShellLink as IPersistFile).Load(PWChar(Item.FullPath), STGM_READ)) then
    exit;
  SetLength(w, MAX_PATH);
  Win32FindData := @Win32FindDataW;
  ShellLink.Resolve(0, SLR_NO_UI);
  ShellLink.GetPath(PWideChar(w), MAX_PATH, Win32FindData^, SLGP_RAWPATH);
  if (Win32FindData.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> FILE_ATTRIBUTE_DIRECTORY) then
    exit;
  Item.LnkPath := TrimRightW(w);
  Item.IsDir := true;
end;

// メニュー項目描画
procedure TMainForm.DrawItem(Item: TItem);
var
  ACanvas: TCanvas;
  TextRect, ARect: TRect;
  Middle: Integer;
begin
  ACanvas := Image1.Canvas;
  ARect := Rect(0, Item.Top, Image1.Width, Item.Bottom);
  Middle := ARect.Top + ITEM_HEIGHT div 2;

  // 色
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

  // セパレータ
  if not Item.Enabled then
  begin
    ACanvas.Pen.Color := clWindowFrame;
    ACanvas.PenPos := Point(ARect.Left + 8, Middle);
    ACanvas.LineTo(ARect.Right - 8, Middle);
    exit;
  end;

  DrawIconEx(
    ACanvas.Handle,
    ARect.Left + 2,
    ARect.Top + 2,
    Item.Icon,
    ICON_SIZE,
    ICON_SIZE,
    0,
    0,
    DI_IMAGE or DI_MASK
  );

  // 文字
  TextRect := Rect(ARect.Left + TEXT_LEFT, ARect.Top, ARect.Right - 2, ARect.Bottom);
  if Item.IsDir then
    TextRect.Right := Arect.Right - TEXT_LEFT + 3;
  DrawTextW(ACanvas.Handle,
    PWideChar(Item.CaptionW),
    Length(Item.CaptionW),
    TextRect,
    DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS
  );

  // ディレクトリ
  if Item.IsDir then
  begin
    ACanvas.PenPos := Point(ARect.Right - 17, Middle -5);
    ACanvas.LineTo(ARect.Right - 12, Middle);
    ACanvas.LineTo(ARect.Right - 18, Middle + 6);
  end;
end;

// 選択
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

// 子フォーム表示
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

// 実行
procedure TMainForm.Execute();
var
  e: Integer;
  s: String;
  w: PWideChar;
begin
  if SelectedItem = nil then
    exit;
  if ((GetAsyncKeyState(VK_RBUTTON) and 1) = 1) or (GetKeyState(VK_SHIFT) < 0) or (GetKeyState(VK_CONTROL) < 0) then
  begin
    w := PWideChar('/select,' + SelectedItem.FullPath);
    ShellExecuteW(0, nil, 'explorer.exe', w, nil, SW_SHOWNORMAL)
  end else
  begin
    SetLastError(0);
    ShellExecuteW(0, '', PWideChar(SelectedItem.Filename), nil, PWideChar(SelectedItem.Dir), SW_SHOWNORMAL);
    e := GetLastError;
    if (e <> 0) and (e <> E_PENDING) then
    begin
      if SelectedItem.IsLnk and (e = ERROR_CANCELLED) then
        e := ERROR_PATH_NOT_FOUND;
      s := SysErrorMessage(e);
      MessageBox(Handle, PChar(s), '', MB_ICONWARNING or MB_OK);
      exit;
    end;
  end;
  Application.Terminate;
end;

// マウス操作
procedure TMainForm.Image1MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var p: TPoint;
begin
  GetCursorPos(p);
  if (p.X = LastMousePoint.X) and (p.Y = LastMousePoint.Y) then
   exit;
  LastMousePoint.X := p.X;
  LastMousePoint.Y := p.Y;
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

// キーボード操作
procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
function IsInRange(i: Integer): Boolean;
begin
  Result := (0 <= i) and (i < Count);
end;
var
  i, j, d: Integer;
  k: Word;

begin
  k := Key;
  if (ssAlt in Shift) or ViMode and (Shift = []) then
  case Key of
    ord('H'): k := VK_LEFT;
    ord('J'): k := VK_DOWN;
    ord('K'): k := VK_UP;
    ord('L'): k := VK_RIGHT;
  end;
  d := 0; // 上下キーフラグ
  case k of
     VK_RIGHT, VK_SPACE:
      // ディレクトリなら子を開く
      if (SelectedItem <> nil) and SelectedItem.IsDir then
      begin
        Timer1Timer(Self);
        if ChildForm.Count > 0 then
        begin
          ChildForm.Select(0);
          ChildForm.CaletIndex := 0;
        end;
      end;
    VK_LEFT, VK_BACK: // 閉じて親に戻る
      if ParentForm <> nil then
        ParentForm.HideChildForms
      else if Self = MainForm then
        d := - Count;
    VK_ESCAPE: Application.Terminate;
    VK_RETURN: Execute;
    VK_UP: d := -1;
    VK_DOWN: d := 1;
    ord('0')..ord('9'), ord('@')..ord('Z'):
      begin
        i := SelectedIndex;
        if not IsInRange(i) then
          i := 0;
        for j := Count downto 1 do
        begin
          i := (i + 1) mod Count;
          if i = SelectedIndex then
            exit;
          if not Items[i].Enabled then
            continue;
          if
            (UpperCase(Copy(Items[i].CaptionW, 1, 1)) = char(Key)) or
            (UpperCase(Copy(Items[i].Filename, 1, 1)) = char(Key))
          then
          begin
            Select(i);
            exit;
          end;
        end;
      end;
  end;
  // 上下キー
  if d = 0 then
    exit; // 上下キー以外はここでexit
  if (SelectedIndex = -1) and (d <0) then
    i := Count
  else
    i := SelectedIndex;
  // セパレータはスキップする
  repeat
    i := i + d;
  until (not IsInRange(i)) or Items[i].Enabled;
  if IsInRange(i) then
  begin
    CaletIndex := i;
    Select(CaletIndex);
  end;
end;

end.

