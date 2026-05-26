<#
.SYNOPSIS
    Install or update all Kafkade agent skills to user-level skills directories.
.DESCRIPTION
    Copies each skill from the skills/ directory into the Copilot, Claude, and
    vendor-neutral agent skills folders so they work with Copilot CLI, Claude
    Code, and any agent supporting the Agent Skills open standard.

    Targets:
      - ~/.copilot/skills/  (or $env:COPILOT_HOME/skills/)
      - ~/.claude/skills/   (or $env:CLAUDE_HOME/skills/)
      - ~/.agents/skills/
.PARAMETER Uninstall
    Remove all Kafkade skills from all user-level directories.
.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SkillsSrc = Join-Path $ScriptDir 'skills'

$CopilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $HOME '.copilot' }
$ClaudeHome  = if ($env:CLAUDE_HOME)  { $env:CLAUDE_HOME }  else { Join-Path $HOME '.claude' }

$Targets = @(
    (Join-Path $CopilotHome 'skills'),
    (Join-Path $ClaudeHome  'skills'),
    (Join-Path $HOME '.agents' 'skills')
)

function Write-Info  { param($Msg) Write-Host "  + $Msg" -ForegroundColor Green }
function Write-Warn  { param($Msg) Write-Host "  ! $Msg" -ForegroundColor Yellow }
function Write-Err   { param($Msg) Write-Host "  x $Msg" -ForegroundColor Red }

if (-not (Test-Path $SkillsSrc)) {
    Write-Err "Skills directory not found: $SkillsSrc"
    exit 1
}

# Discover all skills (directories containing SKILL.md)
$Skills = Get-ChildItem -Path $SkillsSrc -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
    Select-Object -ExpandProperty Name

if ($Skills.Count -eq 0) {
    Write-Warn 'No skills found in skills/ directory'
    exit 0
}

Write-Host ''
Write-Host 'Kafkade Agent Skills' -ForegroundColor White
Write-Host ''

foreach ($Target in $Targets) {
    Write-Host "  -> $Target" -ForegroundColor DarkGray

    if ($Uninstall) {
        foreach ($Skill in $Skills) {
            $Dst = Join-Path $Target $Skill
            if (Test-Path $Dst) {
                Remove-Item -Recurse -Force $Dst
                Write-Info "Removed $Skill"
            } else {
                Write-Warn "Not installed: $Skill"
            }
        }
    } else {
        if (-not (Test-Path $Target)) {
            New-Item -ItemType Directory -Path $Target -Force | Out-Null
        }

        foreach ($Skill in $Skills) {
            $Src = Join-Path $SkillsSrc $Skill
            $Dst = Join-Path $Target $Skill

            if (Test-Path $Dst) {
                Remove-Item -Recurse -Force $Dst
                Copy-Item -Recurse -Force $Src $Dst
                Write-Info "Updated $Skill"
            } else {
                Copy-Item -Recurse -Force $Src $Dst
                Write-Info "Installed $Skill"
            }
        }
    }

    Write-Host ''
}

if ($Uninstall) {
    Write-Host 'Done. Restart your agent or run /skills reload to apply.'
} else {
    Write-Host "$($Skills.Count) skill(s) installed to $($Targets.Count) targets."
    Write-Host 'Restart your agent or run /skills reload to apply.'
}
