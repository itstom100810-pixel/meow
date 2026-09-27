Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Threading;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class WinAPI {
    [DllImport("user32.dll")]  public static extern void  mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
    [DllImport("user32.dll")]  public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")]  public static extern bool  ReleaseCapture();
    [DllImport("user32.dll")]  public static extern int   SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
    [DllImport("winmm.dll")]   public static extern uint  timeBeginPeriod(uint uPeriod);
    [DllImport("winmm.dll")]   public static extern uint  timeEndPeriod(uint uPeriod);

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
    private static Thread         _thread;

    public static void Start() {
        // unlock Windows timer to 1ms resolution — this is what breaks the 64 CPS wall
        WinAPI.timeBeginPeriod(1);

        _thread = new Thread(() => {
            var sw = new Stopwatch();
            while (true) {
                if (Clicking && CPS > 0) {
                    // target interval in Stopwatch ticks
                    long intervalTicks = (long)(Stopwatch.Frequency / (double)CPS);
                    sw.Restart();
                    DoClick();
                    Interlocked.Increment(ref ClickCount);
                    // spin-sleep hybrid: sleep most of it, spinwait the tail
                    long remaining = intervalTicks - sw.ElapsedTicks;
                    long sleepTicks = remaining - (Stopwatch.Frequency / 1000); // leave 1ms for spinwait
                    if (sleepTicks > 0) {
                        int sleepMs = (int)(sleepTicks * 1000 / Stopwatch.Frequency);
                        if (sleepMs > 0) Thread.Sleep(sleepMs);
                    }
                    // spinwait the remainder for precision
                    while (sw.ElapsedTicks < intervalTicks) { Thread.SpinWait(10); }
                } else {
                    Thread.Sleep(5);
                }
            }
        });
        _thread.IsBackground = true;
        _thread.Priority = ThreadPriority.Highest;
        _thread.Start();
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
$script:hotkeyVK     = 0x59
$script:hotkeyMods   = @("Ctrl")
$script:hotkeyLabel  = "Ctrl + Y"

# ── Form ──────────────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Pot's Autoclicker"
$form.Size            = New-Object System.Drawing.Size(460,240)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor       = $C.BG
$form.ForeColor       = $C.TEXT
$form.Font            = New-Object System.Drawing.Font("Segoe UI",9)
$form.KeyPreview      = $true

$form.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        [WinAPI]::ReleaseCapture()
        [WinAPI]::SendMessage($form.Handle,[WinAPI]::WM_NCLBUTTONDOWN,[WinAPI]::HT_CAPTION,0)
    }
})

# ── KeyDown bind ──────────────────────────────────────────────────────────────
$form.Add_KeyDown({
    param($s,$e)
    if (-not $script:listeningKey) { return }
    $ignoredKeys = @(
        [System.Windows.Forms.Keys]::ControlKey,[System.Windows.Forms.Keys]::ShiftKey,
        [System.Windows.Forms.Keys]::Menu,[System.Windows.Forms.Keys]::LControlKey,
        [System.Windows.Forms.Keys]::RControlKey,[System.Windows.Forms.Keys]::LShiftKey,
        [System.Windows.Forms.Keys]::RShiftKey,[System.Windows.Forms.Keys]::LMenu,
        [System.Windows.Forms.Keys]::RMenu
    )
    if ($ignoredKeys -contains $e.KeyCode) { return }

    $script:hotkeyVK = [int]$e.KeyCode
    $mods = @(); $parts = @()
    if ($e.Control) { $mods += "Ctrl";  $parts += "Ctrl"  }
    if ($e.Shift)   { $mods += "Shift"; $parts += "Shift" }
    if ($e.Alt)     { $mods += "Alt";   $parts += "Alt"   }
    $script:hotkeyMods  = $mods
    $parts += $e.KeyCode.ToString()
    $script:hotkeyLabel = $parts -join " + "

    $hotkeyDisplay.Text      = $script:hotkeyLabel
    $hotkeyDisplay.ForeColor = $C.ACCENT
    $changeKeyBtn.Text       = "Change Key"
    $changeKeyBtn.ForeColor  = $C.ACCENT
    $script:listeningKey     = $false
    $e.Handled               = $true
    $e.SuppressKeyPress      = $true
})

# ── Top bar ───────────────────────────────────────────────────────────────────
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
$closeBtn.Add_Click({ [WinAPI]::timeEndPeriod(1); $form.Close() })
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

# ── Badge ─────────────────────────────────────────────────────────────────────
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
    if ([ClickEngine]::Clicking) {
        $statusLabel.Text="●  ACTIVE"; $statusLabel.ForeColor=$C.GREEN
    } else {
        $statusLabel.Text="○  IDLE";   $statusLabel.ForeColor=$C.IDLE
    }
}

function MkDiv($y) {
    $p=New-Object System.Windows.Forms.Panel
    $p.Location=New-Object System.Drawing.Point(0,$y)
    $p.Size=New-Object System.Drawing.Size(460,1)
    $p.BackColor=$C.BORDER
    $form.Controls.Add($p)
}
function MkLbl($txt,$x,$y,$col) {
    $l=New-Object System.Windows.Forms.Label
    $l.Text=$txt; $l.ForeColor=$col
    $l.Location=New-Object System.Drawing.Point($x,$y)
    $l.AutoSize=$true; $form.Controls.Add($l); return $l
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

MkDiv 36

# ═══ ROW 1 — CPS + Mouse Button ══════════════════════════════════════════════
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

# ═══ ROW 2 — Hotkey + Mode ════════════════════════════════════════════════════
MkLbl "Hotkey" 18 108 $C.SUBTEXT | Out-Null

$hotkeyDisplay=New-Object System.Windows.Forms.Label
$hotkeyDisplay.Text      ="Ctrl + Y"
$hotkeyDisplay.Font      =New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$hotkeyDisplay.ForeColor =$C.ACCENT
$hotkeyDisplay.BackColor =$C.SURFACE2
$hotkeyDisplay.Location  =New-Object System.Drawing.Point(75,104)
$hotkeyDisplay.Size      =New-Object System.Drawing.Size(130,28)
$hotkeyDisplay.TextAlign =[System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($hotkeyDisplay)

$changeKeyBtn=MkBtn "Change Key" 215 104 110 28 $false
$changeKeyBtn.ForeColor=$C.ACCENT
$changeKeyBtn.FlatAppearance.BorderColor=$C.ACCENT
$changeKeyBtn.Add_Click({
    $script:listeningKey     = $true
    $changeKeyBtn.Text       = "Press keys..."
    $changeKeyBtn.ForeColor  = $C.GREEN
    $hotkeyDisplay.Text      = "..."
    $hotkeyDisplay.ForeColor = $C.GREEN
    $form.ActiveControl      = $null
    $form.Focus() | Out-Null
})

MkLbl "Mode" 345 108 $C.SUBTEXT | Out-Null
$btnToggle=MkBtn "T" 383 104 34 28 $true
$btnToggle.Font=New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Bold)
$btnHold=MkBtn "H" 420 104 34 28 $false
$btnHold.Font=New-Object System.Drawing.Font("Segoe UI",7,[System.Drawing.FontStyle]::Bold)

$tip=New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($btnToggle,"Toggle — press once start, again stop")
$tip.SetToolTip($btnHold,  "Hold — hold to click, release to stop")

$modeBtns=@($btnToggle,$btnHold); $modeKeys2=@("Toggle","Hold")
for($i=0;$i-lt2;$i++){
    $mb=$modeBtns[$i];$mk=$modeKeys2[$i]
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

# ═══ ROW 3 — Click Counter ════════════════════════════════════════════════════
MkLbl "Clicks" 18 165 $C.SUBTEXT | Out-Null

$countLabel=New-Object System.Windows.Forms.Label
$countLabel.Text     ="0"
$countLabel.Font     =New-Object System.Drawing.Font("Segoe UI",20,[System.Drawing.FontStyle]::Bold)
$countLabel.ForeColor=$C.ACCENT
$countLabel.Location =New-Object System.Drawing.Point(75,153)
$countLabel.Size     =New-Object System.Drawing.Size(220,44)
$countLabel.TextAlign=[System.Drawing.ContentAlignment]::MiddleLeft
$form.Controls.Add($countLabel)

$resetBtn=MkBtn "Reset" 310 162 70 24 $false
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

# ── Border ────────────────────────────────────────────────────────────────────
$form.Add_Paint({
    $g=$_.Graphics
    $p=New-Object System.Drawing.Pen($C.BORDER,1)
    $g.DrawRectangle($p,0,0,$form.Width-1,$form.Height-1)
    $p.Dispose()
})

# ═══ HOTKEY POLL ══════════════════════════════════════════════════════════════
$hkTimer=New-Object System.Windows.Forms.Timer
$hkTimer.Interval=16
$hkTimer.Add_Tick({
    if($script:listeningKey){return}
    $ctrl =([WinAPI]::GetAsyncKeyState(0x11)-band 0x8000)-ne 0
    $shift=([WinAPI]::GetAsyncKeyState(0x10)-band 0x8000)-ne 0
    $alt  =([WinAPI]::GetAsyncKeyState(0x12)-band 0x8000)-ne 0
    $keyDown=([WinAPI]::GetAsyncKeyState($script:hotkeyVK)-band 0x8000)-ne 0

    $needCtrl =$script:hotkeyMods -contains "Ctrl"
    $needShift=$script:hotkeyMods -contains "Shift"
    $needAlt  =$script:hotkeyMods -contains "Alt"

    $modOk=((-not $needCtrl)-or $ctrl)-and((-not $needShift)-or $shift)-and((-not $needAlt)-or $alt)
    $pressed=$modOk -and $keyDown

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

$form.Add_FormClosing({ [WinAPI]::timeEndPeriod(1); $hkTimer.Stop(); $countTimer.Stop() })
[ClickEngine]::CPS=20
[System.Windows.Forms.Application]::Run($form)
