Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Threading;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class WinAPI {
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

    public const uint MOUSEEVENTF_LEFTDOWN   = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP     = 0x0004;
    public const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    public const uint MOUSEEVENTF_MIDDLEUP   = 0x0040;
    public const uint MOUSEEVENTF_RIGHTDOWN  = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP    = 0x0010;
    public const int  WM_NCLBUTTONDOWN       = 0xA1;
    public const int  HT_CAPTION             = 0x2;
}

public class ClickEngine {
    public static volatile bool   Clicking   = false;
    public static volatile string Button     = "L";
    public static volatile int    CPS        = 20;
    public static long            ClickCount = 0;

    public static void Start() {
        Thread t = new Thread(() => {
            while (true) {
                if (Clicking && CPS > 0) {
                    double intervalMs = 1000.0 / CPS;
                    DoClick();
                    Interlocked.Increment(ref ClickCount);
                    int ms = (int)intervalMs;
                    if (ms > 1) Thread.Sleep(ms - 1);
                    var sw = Stopwatch.StartNew();
                    long ticks = (long)((intervalMs - (ms > 1 ? ms - 1 : 0)) * Stopwatch.Frequency / 1000.0);
                    while (sw.ElapsedTicks < ticks) { }
                } else {
                    Thread.Sleep(5);
                }
            }
        });
        t.IsBackground = true;
        t.Priority = ThreadPriority.Highest;
        t.Start();
    }

    private static void DoClick() {
        switch (Button) {
            case "L":
                WinAPI.mouse_event(WinAPI.MOUSEEVENTF_LEFTDOWN, 0,0,0,0);
                WinAPI.mouse_event(WinAPI.MOUSEEVENTF_LEFTUP,   0,0,0,0); break;
            case "M":
                WinAPI.mouse_event(WinAPI.MOUSEEVENTF_MIDDLEDOWN, 0,0,0,0);
                WinAPI.mouse_event(WinAPI.MOUSEEVENTF_MIDDLEUP,   0,0,0,0); break;
            case "R":
                WinAPI.mouse_event(WinAPI.MOUSEEVENTF_RIGHTDOWN, 0,0,0,0);
                WinAPI.mouse_event(WinAPI.MOUSEEVENTF_RIGHTUP,   0,0,0,0); break;
        }
    }
}
"@

[ClickEngine]::Start()

# ── Colors ────────────────────────────────────────────────────────────────────
$C = @{
    BG       = [System.Drawing.Color]::FromArgb(13,15,23)
    SURFACE  = [System.Drawing.Color]::FromArgb(22,26,40)
    SURFACE2 = [System.Drawing.Color]::FromArgb(30,36,55)
    BORDER   = [System.Drawing.Color]::FromArgb(48,58,90)
    ACCENT   = [System.Drawing.Color]::FromArgb(82,148,255)
    ACCENT2  = [System.Drawing.Color]::FromArgb(48,100,200)
    TEXT     = [System.Drawing.Color]::FromArgb(220,228,248)
    SUBTEXT  = [System.Drawing.Color]::FromArgb(110,125,165)
    GREEN    = [System.Drawing.Color]::FromArgb(50,210,110)
    RED      = [System.Drawing.Color]::FromArgb(255,75,75)
    IDLE     = [System.Drawing.Color]::FromArgb(85,95,130)
}

# ── State ─────────────────────────────────────────────────────────────────────
$script:mode         = "Toggle"
$script:prevHeld     = $false
$script:listeningKey = $false
$script:hotkeyVK     = 0x59        # Y
$script:hotkeyMods   = @("Ctrl")
$script:hotkeyLabel  = "Ctrl + Y"

# ── Form ──────────────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Pot's Autoclicker"
$form.Size            = New-Object System.Drawing.Size(460,290)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor       = $C.BG
$form.ForeColor       = $C.TEXT
$form.Font            = New-Object System.Drawing.Font("Segoe UI",9)
$form.KeyPreview      = $true   # <-- form gets ALL key events first

# drag
$form.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        [WinAPI]::ReleaseCapture()
        [WinAPI]::SendMessage($form.Handle,[WinAPI]::WM_NCLBUTTONDOWN,[WinAPI]::HT_CAPTION,0)
    }
})

# ── KEY DOWN — this is how we catch the bind ──────────────────────────────────
$form.Add_KeyDown({
    param($s,$e)
    if (-not $script:listeningKey) { return }

    # ignore pure modifier presses — wait for an actual key
    $modOnly = @(
        [System.Windows.Forms.Keys]::ControlKey,
        [System.Windows.Forms.Keys]::ShiftKey,
        [System.Windows.Forms.Keys]::Menu,
        [System.Windows.Forms.Keys]::LControlKey,
        [System.Windows.Forms.Keys]::RControlKey,
        [System.Windows.Forms.Keys]::LShiftKey,
        [System.Windows.Forms.Keys]::RShiftKey,
        [System.Windows.Forms.Keys]::LMenu,
        [System.Windows.Forms.Keys]::RMenu
    )
    if ($modOnly -contains $e.KeyCode) { return }

    # grab mods
    $mods  = @()
    $parts = @()
    if ($e.Control) { $mods += "Ctrl";  $parts += "Ctrl"  }
    if ($e.Shift)   { $mods += "Shift"; $parts += "Shift" }
    if ($e.Alt)     { $mods += "Alt";   $parts += "Alt"   }

    $script:hotkeyVK   = [int]$e.KeyCode
    $script:hotkeyMods = $mods

    # friendly name
    $keyName = $e.KeyCode.ToString()
    $parts  += $keyName
    $script:hotkeyLabel = $parts -join " + "

    $hotkeyDisplay.Text      = $script:hotkeyLabel
    $hotkeyDisplay.ForeColor = $C.ACCENT
    $changeKeyBtn.Text       = "Change Key"
    $changeKeyBtn.ForeColor  = $C.ACCENT
    $script:listeningKey     = $false

    $e.Handled       = $true
    $e.SuppressKeyPress = $true
})

# ── Top accent bar ────────────────────────────────────────────────────────────
$topBar = New-Object System.Windows.Forms.Panel
$topBar.Location  = New-Object System.Drawing.Point(0,0)
$topBar.Size      = New-Object System.Drawing.Size(460,3)
$topBar.BackColor = $C.ACCENT
$form.Controls.Add($topBar)

# ── Close ─────────────────────────────────────────────────────────────────────
$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text      = "✕"
$closeBtn.Location  = New-Object System.Drawing.Point(428,4)
$closeBtn.Size      = New-Object System.Drawing.Size(26,22)
$closeBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$closeBtn.FlatAppearance.BorderSize = 0
$closeBtn.BackColor = $C.BG
$closeBtn.ForeColor = $C.SUBTEXT
$closeBtn.Font      = New-Object System.Drawing.Font("Segoe UI",8)
$closeBtn.Add_Click({ $form.Close() })
$closeBtn.Add_MouseEnter({ $closeBtn.ForeColor = $C.RED })
$closeBtn.Add_MouseLeave({ $closeBtn.ForeColor = $C.SUBTEXT })
$form.Controls.Add($closeBtn)

# ── Title ─────────────────────────────────────────────────────────────────────
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text      = "Pot's Autoclicker"
$titleLabel.Font      = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = $C.TEXT
$titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$titleLabel.Location  = New-Object System.Drawing.Point(0,6)
$titleLabel.Size      = New-Object System.Drawing.Size(460,26)
$form.Controls.Add($titleLabel)

# ── Simple badge ──────────────────────────────────────────────────────────────
$badge = New-Object System.Windows.Forms.Label
$badge.Text      = "  Simple  "
$badge.Font      = New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Bold)
$badge.ForeColor = $C.GREEN
$badge.BackColor = [System.Drawing.Color]::FromArgb(15,55,30)
$badge.Location  = New-Object System.Drawing.Point(14,8)
$badge.AutoSize  = $true
$form.Controls.Add($badge)

# ── Status ────────────────────────────────────────────────────────────────────
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text      = "○  IDLE"
$statusLabel.Font      = New-Object System.Drawing.Font("Segoe UI",8,[System.Drawing.FontStyle]::Bold)
$statusLabel.ForeColor = $C.IDLE
$statusLabel.Location  = New-Object System.Drawing.Point(365,9)
$statusLabel.AutoSize  = $true
$form.Controls.Add($statusLabel)

function Update-Status {
    $form.Invoke([Action]{
        if ([ClickEngine]::Clicking) {
            $statusLabel.Text="●  ACTIVE"; $statusLabel.ForeColor=$C.GREEN
            $startBtn.Text="■  STOP";     $startBtn.BackColor=[System.Drawing.Color]::FromArgb(160,30,30)
        } else {
            $statusLabel.Text="○  IDLE";  $statusLabel.ForeColor=$C.IDLE
            $startBtn.Text="▶  START";   $startBtn.BackColor=$C.ACCENT2
        }
    })
}

# ── Dividers ──────────────────────────────────────────────────────────────────
function MkDiv($y) {
    $p=New-Object System.Windows.Forms.Panel
    $p.Location=New-Object System.Drawing.Point(0,$y)
    $p.Size=New-Object System.Drawing.Size(460,1)
    $p.BackColor=$C.BORDER
    $form.Controls.Add($p)
}
MkDiv 36

# ── Helpers ───────────────────────────────────────────────────────────────────
function MkLbl($txt,$x,$y,$col) {
    $l=New-Object System.Windows.Forms.Label
    $l.Text=$txt; $l.ForeColor=$col
    $l.Location=New-Object System.Drawing.Point($x,$y)
    $l.AutoSize=$true
    $form.Controls.Add($l); return $l
}
function MkBtn($txt,$x,$y,$w,$h,$active=$false) {
    $b=New-Object System.Windows.Forms.Button
    $b.Text=$txt
    $b.Location=New-Object System.Drawing.Point($x,$y)
    $b.Size=New-Object System.Drawing.Size($w,$h)
    $b.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize=1
    $b.FlatAppearance.BorderColor=$C.BORDER
    $b.BackColor=if($active){$C.ACCENT}else{$C.SURFACE}
    $b.ForeColor=$C.TEXT
    $b.Font=New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($b); return $b
}

# ═══ ROW 1 — CPS + Button ════════════════════════════════════════════════════
MkLbl "Click Speed" 18 58 $C.SUBTEXT | Out-Null

$cpsBox=New-Object System.Windows.Forms.NumericUpDown
$cpsBox.Minimum=1; $cpsBox.Maximum=500; $cpsBox.Value=20
$cpsBox.Location=New-Object System.Drawing.Point(110,54)
$cpsBox.Size=New-Object System.Drawing.Size(72,28)
$cpsBox.BackColor=$C.SURFACE2; $cpsBox.ForeColor=$C.TEXT
$cpsBox.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle
$cpsBox.Font=New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$cpsBox.Add_ValueChanged({ [ClickEngine]::CPS=[int]$cpsBox.Value })
$form.Controls.Add($cpsBox)

MkLbl "cps" 187 58 $C.SUBTEXT | Out-Null
MkLbl "Button" 240 58 $C.SUBTEXT | Out-Null

$btnL=MkBtn "L" 292 53 34 28 $true
$btnM=MkBtn "M" 329 53 34 28 $false
$btnR=MkBtn "R" 366 53 34 28 $false
$mouseBtns=@($btnL,$btnM,$btnR); $mouseKeys=@("L","M","R")
for($i=0;$i-lt3;$i++){
    $mb=$mouseBtns[$i];$mk=$mouseKeys[$i]
    $mb.Add_Click({
        [ClickEngine]::Button=$mk
        foreach($x in $mouseBtns){$x.BackColor=$C.SURFACE}
        $mb.BackColor=$C.ACCENT
    }.GetNewClosure())
}
MkDiv 93

# ═══ ROW 2 — Hotkey + Mode ═══════════════════════════════════════════════════
MkLbl "Hotkey" 18 108 $C.SUBTEXT | Out-Null

$hotkeyDisplay=New-Object System.Windows.Forms.Label
$hotkeyDisplay.Text      = "Ctrl + Y"
$hotkeyDisplay.Font      = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$hotkeyDisplay.ForeColor = $C.ACCENT
$hotkeyDisplay.BackColor = $C.SURFACE2
$hotkeyDisplay.Location  = New-Object System.Drawing.Point(75,104)
$hotkeyDisplay.Size      = New-Object System.Drawing.Size(130,28)
$hotkeyDisplay.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($hotkeyDisplay)

$changeKeyBtn=MkBtn "Change Key" 215 104 110 28 $false
$changeKeyBtn.ForeColor=$C.ACCENT
$changeKeyBtn.FlatAppearance.BorderColor=$C.ACCENT
$changeKeyBtn.Add_Click({
    $script:listeningKey    = $true
    $changeKeyBtn.Text      = "Press keys..."
    $changeKeyBtn.ForeColor = $C.GREEN
    $hotkeyDisplay.Text     = "..."
    $hotkeyDisplay.ForeColor= $C.GREEN
    $form.Focus() | Out-Null   # make sure form gets keydown
})

MkLbl "Mode" 345 108 $C.SUBTEXT | Out-Null
$btnToggle=MkBtn "Toggle" 385 104 34 28 $true
$btnToggle.Font=New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Bold)
$btnToggle.Text="T"
$btnHold=MkBtn "Hold" 422 104 34 28 $false
$btnHold.Font=New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Bold)
$btnHold.Text="H"

$tip=New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($btnToggle,"Toggle mode")
$tip.SetToolTip($btnHold,"Hold mode")

$modeBtns=@($btnToggle,$btnHold); $modeKeys=@("Toggle","Hold")
for($i=0;$i-lt2;$i++){
    $mb=$modeBtns[$i];$mk=$modeKeys[$i]
    $mb.Add_Click({
        $script:mode=$mk
        foreach($x in $modeBtns){$x.BackColor=$C.SURFACE}
        $mb.BackColor=$C.ACCENT
        if($mk -eq "Toggle" -and [ClickEngine]::Clicking){
            [ClickEngine]::Clicking=$false; Update-Status
        }
    }.GetNewClosure())
}
MkDiv 143

# ═══ ROW 3 — Click Counter ═══════════════════════════════════════════════════
MkLbl "Clicks" 18 160 $C.SUBTEXT | Out-Null

$countLabel=New-Object System.Windows.Forms.Label
$countLabel.Text     ="0"
$countLabel.Font     =New-Object System.Drawing.Font("Segoe UI",18,[System.Drawing.FontStyle]::Bold)
$countLabel.ForeColor=$C.ACCENT
$countLabel.Location =New-Object System.Drawing.Point(75,150)
$countLabel.Size     =New-Object System.Drawing.Size(200,40)
$countLabel.TextAlign=[System.Drawing.ContentAlignment]::MiddleLeft
$form.Controls.Add($countLabel)

$resetBtn=MkBtn "Reset" 285 158 70 24 $false
$resetBtn.Font=New-Object System.Drawing.Font("Segoe UI",8)
$resetBtn.ForeColor=$C.SUBTEXT
$resetBtn.Add_Click({
    [System.Threading.Interlocked]::Exchange([ref][ClickEngine]::ClickCount,0)|Out-Null
    $countLabel.Text="0"
})

$countTimer=New-Object System.Windows.Forms.Timer
$countTimer.Interval=100
$countTimer.Add_Tick({ $countLabel.Text=[ClickEngine]::ClickCount.ToString("N0") })
$countTimer.Start()
MkDiv 205

# ═══ ROW 4 — Start/Stop ══════════════════════════════════════════════════════
$startBtn=New-Object System.Windows.Forms.Button
$startBtn.Text     ="▶  START"
$startBtn.Location =New-Object System.Drawing.Point(18,218)
$startBtn.Size     =New-Object System.Drawing.Size(424,46)
$startBtn.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
$startBtn.FlatAppearance.BorderSize=0
$startBtn.BackColor=$C.ACCENT2
$startBtn.ForeColor=$C.TEXT
$startBtn.Font     =New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$startBtn.Add_Click({
    [ClickEngine]::Clicking=-not [ClickEngine]::Clicking
    Update-Status
})
$startBtn.Add_MouseEnter({
    if([ClickEngine]::Clicking){$startBtn.BackColor=[System.Drawing.Color]::FromArgb(200,40,40)}
    else{$startBtn.BackColor=$C.ACCENT}
})
$startBtn.Add_MouseLeave({
    if([ClickEngine]::Clicking){$startBtn.BackColor=[System.Drawing.Color]::FromArgb(160,30,30)}
    else{$startBtn.BackColor=$C.ACCENT2}
})
$form.Controls.Add($startBtn)

# ═══ HOTKEY POLL ═════════════════════════════════════════════════════════════
$hkTimer=New-Object System.Windows.Forms.Timer
$hkTimer.Interval=30
$hkTimer.Add_Tick({
    if($script:listeningKey){return}

    $ctrl =([WinAPI]::GetAsyncKeyState(0x11)-band 0x8000)-ne 0
    $shift=([WinAPI]::GetAsyncKeyState(0x10)-band 0x8000)-ne 0
    $alt  =([WinAPI]::GetAsyncKeyState(0x12)-band 0x8000)-ne 0
    $key  =([WinAPI]::GetAsyncKeyState($script:hotkeyVK)-band 0x8000)-ne 0

    $needCtrl =$script:hotkeyMods -contains "Ctrl"
    $needShift=$script:hotkeyMods -contains "Shift"
    $needAlt  =$script:hotkeyMods -contains "Alt"

    $modOk=((-not $needCtrl)-or $ctrl)-and((-not $needShift)-or $shift)-and((-not $needAlt)-or $alt)
    $pressed=$modOk -and $key

    if($script:mode -eq "Toggle"){
        if($pressed -and -not $script:prevHeld){
            [ClickEngine]::Clicking=-not [ClickEngine]::Clicking
            Update-Status
        }
        $script:prevHeld=$pressed
    } else {
        if($pressed -ne [ClickEngine]::Clicking){
            [ClickEngine]::Clicking=$pressed
            Update-Status
        }
    }
})
$hkTimer.Start()

# ── Border paint ──────────────────────────────────────────────────────────────
$form.Add_Paint({
    $g=$_.Graphics
    $p=New-Object System.Drawing.Pen($C.BORDER,1)
    $g.DrawRectangle($p,0,0,$form.Width-1,$form.Height-1)
    $p.Dispose()
})

$form.Add_FormClosing({ $hkTimer.Stop(); $countTimer.Stop() })
[ClickEngine]::CPS=20
[System.Windows.Forms.Application]::Run($form)
