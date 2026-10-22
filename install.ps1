<#
.SYNOPSIS
    Install, update, or uninstall Kafkade agent skills in user-level skills directories.
.DESCRIPTION
    Runs an interactive, two-step installer:

      1. Select skills: a checkbox list of the skills in skills/ with their
         available version, installed version, and status. Skills that are
         new or have updates are preselected.
      2. Select targets: a checkbox list of the agent skills directories, each
         showing what would change there.

    It then shows a summary and asks for confirmation.

    Targets:
      - copilot: ~/.copilot/skills/  (or $env:COPILOT_HOME/skills/)
      - claude:  ~/.claude/skills/   (or $env:CLAUDE_HOME/skills/)
      - agents:  ~/.agents/skills/   (vendor-neutral)

    Passing -Skill or -All skips the menus. When input is redirected
    (non-interactive), all skills are processed. Without -Target, these modes
    use all targets.
.PARAMETER Skill
    One or more skill names to process without showing the menus.
.PARAMETER Target
    One or more targets (copilot, claude, agents). Defaults to all targets.
.PARAMETER All
    Process all skills without showing the menus.
.PARAMETER List
    Show the skills and their status, then exit.
.PARAMETER Uninstall
    Remove skills instead of installing them.
.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -All
.EXAMPLE
    .\install.ps1 -Skill staff-explain -Target copilot,claude
.EXAMPLE
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Skill,
    [ValidateSet('copilot', 'claude', 'agents')]
    [string[]]$Target,
    [switch]$All,
    [switch]$List,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SkillsSrc = Join-Path $ScriptDir 'skills'

$CopilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
$ClaudeHome  = if ($env:CLAUDE_HOME)  { $env:CLAUDE_HOME }  else { Join-Path $HOME '.claude' }

$Targets = @(
    [pscustomobject]@{ Id = 'copilot'; Label = 'GitHub Copilot'; Path = (Join-Path $CopilotHome 'skills') }
    [pscustomobject]@{ Id = 'claude';  Label = 'Claude Code';    Path = (Join-Path $ClaudeHome 'skills') }
    [pscustomobject]@{ Id = 'agents';  Label = 'Agents (vendor-neutral)'; Path = (Join-Path (Join-Path $HOME '.agents') 'skills') }
)

$Esc = [char]27

function Write-Info  { param($Msg) Write-Host "  + $Msg" -ForegroundColor Green }
function Write-Warn  { param($Msg) Write-Host "  ! $Msg" -ForegroundColor Yellow }
function Write-Err   { param($Msg) Write-Host "  x $Msg" -ForegroundColor Red }

function Format-Path {
    param([string]$Path)
    if ($Path.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) { return '~' + $Path.Substring($HOME.Length) }
    return $Path
}

function Get-SkillVersion {
    param([string]$SkillDir)
    $SkillMd = Join-Path $SkillDir 'SKILL.md'
    if (-not (Test-Path $SkillMd)) { return $null }
    $Lines = Get-Content -LiteralPath $SkillMd
    if ($Lines.Count -eq 0 -or $Lines[0].Trim() -ne '---') { return $null }
    for ($i = 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq '---') { break }
        if ($Lines[$i] -match '^\s*version:\s*[''"]?([^''"\s]+)[''"]?\s*$') { return $Matches[1] }
    }
    return $null
}

function Get-DirSignature {
    param([string]$Dir)
    $Root = (Resolve-Path -LiteralPath $Dir).Path
    $Entries = Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
        $Rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
        "$Rel=$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    }
    return ($Entries -join "`n")
}

# Compares semantic versions. Returns -1, 0, or 1, or $null if either is missing or unparsable.
function Compare-SkillVersion {
    param([string]$A, [string]$B)
    $Re = '^v?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$'
    if (-not $A -or -not $B -or $A -notmatch $Re) { return $null }
    $ACore = $Matches[1]; $APre = $Matches[2]
    if ($B -notmatch $Re) { return $null }
    $BCore = $Matches[1]; $BPre = $Matches[2]
    $AParts = @($ACore.Split('.') | ForEach-Object { [long]$_ })
    $BParts = @($BCore.Split('.') | ForEach-Object { [long]$_ })
    for ($i = 0; $i -lt [Math]::Max($AParts.Count, $BParts.Count); $i++) {
        $X = if ($i -lt $AParts.Count) { $AParts[$i] } else { 0 }
        $Y = if ($i -lt $BParts.Count) { $BParts[$i] } else { 0 }
        if ($X -ne $Y) { return [Math]::Sign($X - $Y) }
    }
    # A pre-release (1.0.0-beta) sorts before its release (1.0.0).
    if ($APre -and -not $BPre) { return -1 }
    if ($BPre -and -not $APre) { return 1 }
    return [Math]::Sign([string]::CompareOrdinal("$APre", "$BPre"))
}

# Kinds: NotInstalled, UpToDate, Update, Modified, Newer, Partial
function Get-SkillStatus {
    param([string]$Name)
    $Src = Join-Path $SkillsSrc $Name
    $SrcSig = Get-DirSignature $Src
    $Available = Get-SkillVersion $Src
    $InstalledCount = 0
    $Differs = $false
    $InstalledVersion = $null
    # Per-target state: Missing, Current, or Differs
    $TargetState = @{}
    foreach ($T in $Targets) {
        $Dst = Join-Path $T.Path $Name
        if (-not (Test-Path $Dst)) { $TargetState[$T.Id] = 'Missing'; continue }
        $InstalledCount++
        if ((Get-DirSignature $Dst) -ne $SrcSig) {
            $Differs = $true
            $TargetState[$T.Id] = 'Differs'
        } else {
            $TargetState[$T.Id] = 'Current'
        }
        # Track the lowest installed version so any outdated target counts.
        $V = Get-SkillVersion $Dst
        if ($V -and (-not $InstalledVersion -or (Compare-SkillVersion $V $InstalledVersion) -lt 0)) {
            $InstalledVersion = $V
        }
    }
    $Cmp = Compare-SkillVersion $Available $InstalledVersion

    if ($InstalledCount -eq 0) {
        $Kind = 'NotInstalled'; $Status = 'not installed'
    } elseif (-not $Differs -and $InstalledCount -eq $Targets.Count) {
        $Kind = 'UpToDate'; $Status = 'up to date'
    } elseif ($Cmp -gt 0) {
        $Kind = 'Update'; $Status = "update available ($InstalledVersion -> $Available)"
    } elseif ($Cmp -lt 0) {
        $Kind = 'Newer'; $Status = "installed is newer ($InstalledVersion > $Available)"
    } elseif ($Differs -and $Cmp -eq 0) {
        $Kind = 'Modified'; $Status = 'modified (version not bumped)'
    } elseif ($Differs) {
        $Kind = 'Update'; $Status = 'update available'
    } else {
        $Kind = 'Partial'; $Status = "partially installed ($InstalledCount/$($Targets.Count) targets)"
    }

    [pscustomobject]@{
        Name           = $Name
        Available      = $Available
        Installed      = $InstalledVersion
        InstalledCount = $InstalledCount
        Kind           = $Kind
        Status         = $Status
        TargetState    = $TargetState
    }
}

function Get-KindColor {
    param([string]$Kind)
    switch ($Kind) {
        'UpToDate' { 'Green' }
        'Update'   { 'Yellow' }
        'Partial'  { 'Yellow' }
        'Modified' { 'Magenta' }
        'Newer'    { 'Cyan' }
        default    { 'Gray' }
    }
}

function Show-SkillTable {
    param([object[]]$Rows)
    $NameWidth = [Math]::Max(5, ($Rows | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
    $Fmt = "  {0,3}  {1,-$NameWidth}  {2,-10}  {3,-10}  {4}"
    Write-Host ($Fmt -f '#', 'Skill', 'Available', 'Installed', 'Status') -ForegroundColor DarkGray
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $R = $Rows[$i]
        $Avail = if ($R.Available) { $R.Available } else { '-' }
        $Inst  = if ($R.InstalledCount -gt 0) { if ($R.Installed) { $R.Installed } else { 'yes' } } else { '-' }
        Write-Host ($Fmt -f ($i + 1), $R.Name, $Avail, $Inst, $R.Status) -ForegroundColor (Get-KindColor $R.Kind)
    }
    Write-Host ''
}

# Returns a normalized key: up, down, space, enter, esc, or a lowercase character.
function Read-MenuKey {
    $K = [Console]::ReadKey($true)
    switch ($K.Key) {
        'UpArrow'   { return 'up' }
        'DownArrow' { return 'down' }
        'Spacebar'  { return 'space' }
        'Enter'     { return 'enter' }
        'Escape'    { return 'esc' }
    }
    return "$($K.KeyChar)".ToLowerInvariant()
}

# Interactive checkbox list. Items have Label, Detail, and Color.
# Returns the selected indices, or an empty array when cancelled.
function Show-CheckboxMenu {
    param([string]$Title, [object[]]$Items, [bool[]]$Checked)
    $Count = $Items.Count
    $LabelWidth = ($Items | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
    $Cursor = 0
    $Msg = ''
    $Drawn = $false

    Write-Host "  $Title" -ForegroundColor White
    [Console]::Write("$Esc[?25l")
    try {
        while ($true) {
            if ($Drawn) { [Console]::Write("$Esc[$($Count + 2)A") }
            $Drawn = $true
            for ($i = 0; $i -lt $Count; $i++) {
                $Pointer = if ($i -eq $Cursor) { '>' } else { ' ' }
                $Box = if ($Checked[$i]) { '[x]' } else { '[ ]' }
                [Console]::Write("$Esc[2K")
                $RowColor = if ($i -eq $Cursor) { 'Cyan' } else { 'Gray' }
                Write-Host ("  $Pointer $Box " + $Items[$i].Label.PadRight($LabelWidth) + '  ') -NoNewline -ForegroundColor $RowColor
                Write-Host $Items[$i].Detail -ForegroundColor $Items[$i].Color
            }
            [Console]::Write("$Esc[2K")
            Write-Host '  up/down move, space toggle, a all, enter confirm, q cancel' -ForegroundColor DarkGray
            [Console]::Write("$Esc[2K")
            Write-Host "  $Msg" -ForegroundColor Yellow
            $Msg = ''

            switch (Read-MenuKey) {
                { $_ -in 'up', 'k' }   { $Cursor = ($Cursor - 1 + $Count) % $Count }
                { $_ -in 'down', 'j' } { $Cursor = ($Cursor + 1) % $Count }
                'space' { $Checked[$Cursor] = -not $Checked[$Cursor] }
                'a' {
                    $State = $Checked -contains $false
                    for ($i = 0; $i -lt $Count; $i++) { $Checked[$i] = $State }
                }
                'enter' {
                    $Picked = @(for ($i = 0; $i -lt $Count; $i++) { if ($Checked[$i]) { $i } })
                    if ($Picked.Count -gt 0) { Write-Host ''; return $Picked }
                    $Msg = 'Select at least one item, or press q to cancel.'
                }
                { $_ -in 'esc', 'q' } { Write-Host ''; return @() }
            }
        }
    } finally {
        [Console]::Write("$Esc[?25h")
    }
}

function Get-TargetDetail {
    param([object]$T, [object[]]$SelectedRows, [bool]$IsUninstall)
    $Path = Format-Path $T.Path
    $States = @($SelectedRows | ForEach-Object { $_.TargetState[$T.Id] })
    if ($IsUninstall) {
        $Installed = @($States | Where-Object { $_ -ne 'Missing' }).Count
        $Note = if ($Installed) { "$Installed to remove" } else { 'nothing to remove' }
    } else {
        $Parts = @()
        $New = @($States | Where-Object { $_ -eq 'Missing' }).Count
        $Upd = @($States | Where-Object { $_ -eq 'Differs' }).Count
        $Cur = @($States | Where-Object { $_ -eq 'Current' }).Count
        if ($New) { $Parts += "$New new" }
        if ($Upd) { $Parts += "$Upd update" }
        if ($Cur) { $Parts += "$Cur current" }
        $Note = $Parts -join ', '
    }
    return "$Path  ($Note)"
}

if (-not (Test-Path $SkillsSrc)) {
    Write-Err "Skills directory not found: $SkillsSrc"
    exit 1
}

# Discover all skills (directories containing SKILL.md)
$Skills = @(Get-ChildItem -Path $SkillsSrc -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
    Sort-Object Name |
    Select-Object -ExpandProperty Name)

if ($Skills.Count -eq 0) {
    Write-Warn 'No skills found in skills/ directory'
    exit 0
}

Write-Host ''
Write-Host 'Kafkade Agent Skills' -ForegroundColor White
Write-Host ''

$Rows = @($Skills | ForEach-Object { Get-SkillStatus $_ })

if ($List) {
    Show-SkillTable $Rows
    exit 0
}

$Interactive = -not ($Skill -or $All -or [Console]::IsInputRedirected)

if ($Interactive) {
    # Step 1: skills
    $MenuRows = if ($Uninstall) { @($Rows | Where-Object InstalledCount -gt 0) } else { $Rows }
    if ($MenuRows.Count -eq 0) {
        Write-Warn 'No skills are installed.'
        exit 0
    }
    $NameWidth = ($MenuRows | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $Items = @($MenuRows | ForEach-Object {
        $Ver = if ($_.Available) { $_.Available } else { '-' }
        [pscustomobject]@{ Label = $_.Name.PadRight($NameWidth); Detail = ('{0,-10}  {1}' -f $Ver, $_.Status); Color = (Get-KindColor $_.Kind) }
    })
    # Preselect new and outdated skills; never preselect a downgrade.
    [bool[]]$Checked = @($MenuRows | ForEach-Object { -not $Uninstall -and $_.Kind -notin 'UpToDate', 'Newer' })
    $Title = if ($Uninstall) { 'Select skills to uninstall' } else { 'Select skills to install or update' }
    $Picked = @(Show-CheckboxMenu $Title $Items $Checked)
    if ($Picked.Count -eq 0) { Write-Host 'Cancelled.'; exit 0 }
    $SelectedRows = @($Picked | ForEach-Object { $MenuRows[$_] })

    # Step 2: targets
    $Items = @($Targets | ForEach-Object {
        [pscustomobject]@{ Label = $_.Label; Detail = (Get-TargetDetail $_ $SelectedRows $Uninstall.IsPresent); Color = 'DarkGray' }
    })
    [bool[]]$Checked = @($Targets | ForEach-Object {
        $T = $_
        if ($Uninstall) { @($SelectedRows | Where-Object { $_.TargetState[$T.Id] -ne 'Missing' }).Count -gt 0 } else { $true }
    })
    $Title = if ($Uninstall) { 'Select targets to remove from' } else { 'Select targets to install to' }
    $Picked = @(Show-CheckboxMenu $Title $Items $Checked)
    if ($Picked.Count -eq 0) { Write-Host 'Cancelled.'; exit 0 }
    $SelectedTargets = @($Picked | ForEach-Object { $Targets[$_] })

    # Step 3: confirm
    $Action = if ($Uninstall) { 'Uninstall' } else { 'Install' }
    Write-Host "  $Action skills: " -NoNewline -ForegroundColor DarkGray
    Write-Host (($SelectedRows | ForEach-Object Name) -join ', ')
    Write-Host '  Targets: ' -NoNewline -ForegroundColor DarkGray
    Write-Host (($SelectedTargets | ForEach-Object Label) -join ', ')
    Write-Host ''
    Write-Host '  Proceed? [Y/n] ' -NoNewline
    $Answer = Read-MenuKey
    Write-Host ''
    if ($Answer -notin 'enter', 'y') { Write-Host 'Cancelled.'; exit 0 }
    Write-Host ''
    $Selected = @($SelectedRows | ForEach-Object Name)
} else {
    if ($Skill) {
        $Unknown = @($Skill | Where-Object { $Skills -notcontains $_ })
        if ($Unknown.Count -gt 0) {
            Write-Err "Unknown skill(s): $($Unknown -join ', '). Available: $($Skills -join ', ')"
            exit 1
        }
        $Selected = @($Skill | Select-Object -Unique)
    } else {
        $Selected = $Skills
    }
    $SelectedTargets = if ($Target) { @($Targets | Where-Object { $Target -contains $_.Id }) } else { $Targets }
}

foreach ($T in $SelectedTargets) {
    Write-Host "  -> $($T.Label): $($T.Path)" -ForegroundColor DarkGray

    if ($Uninstall) {
        foreach ($Name in $Selected) {
            $Dst = Join-Path $T.Path $Name
            if (Test-Path $Dst) {
                Remove-Item -Recurse -Force $Dst
                Write-Info "Removed $Name"
            } else {
                Write-Warn "Not installed: $Name"
            }
        }
    } else {
        if (-not (Test-Path $T.Path)) {
            New-Item -ItemType Directory -Path $T.Path -Force | Out-Null
        }

        foreach ($Name in $Selected) {
            $Src = Join-Path $SkillsSrc $Name
            $Dst = Join-Path $T.Path $Name

            if (Test-Path $Dst) {
                Remove-Item -Recurse -Force $Dst
                Copy-Item -Recurse -Force $Src $Dst
                Write-Info "Updated $Name"
            } else {
                Copy-Item -Recurse -Force $Src $Dst
                Write-Info "Installed $Name"
            }
        }
    }

    Write-Host ''
}

if ($Uninstall) {
    Write-Host "$($Selected.Count) skill(s) removed from $($SelectedTargets.Count) target(s)."
} else {
    Write-Host "$($Selected.Count) skill(s) installed to $($SelectedTargets.Count) target(s)."
}
Write-Host 'Restart your agent or run /skills reload to apply.'
