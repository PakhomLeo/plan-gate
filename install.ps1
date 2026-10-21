<#
.SYNOPSIS
    Install, update or uninstall plan-gate. The skill it installs is named
    code-project-flow (see README, "Skill name").

.DESCRIPTION
    Same behaviour as install.sh. Components:
      skill  The workflow skill (SKILL.md + references/) for any agent client
             that reads the SKILL.md format. Default target: the Qoder skills
             folder. Documents live under docs/ in the consuming project.
      dsh    The DSH "quick dev" mode: the same skill rendered for the
             project-root document layout, the plan-arm plugin, and a preset
             block in every profile's cordis.patch.yml.

    Safety rules:
      - Never elevates and never writes outside the chosen skills folder, the
        DSH home and (only with -MigrateLegacy) the backup folder.
      - Only overwrites or removes files it installed itself: those listed in
        the .plan-gate-manifest file in each skill folder, a plugin file whose
        content matches a shipped version, and the one preset block it inserts.
      - An install made by the former code-project-flow or dsh-quick-dev
        installers has no manifest. It is left alone unless you pass
        -MigrateLegacy or answer "y" at the prompt; then it is moved into
        ~\.plan-gate-backups\<timestamp>\, never deleted.

    Messages are English and this file is ASCII on purpose: without a BOM,
    Windows PowerShell 5.1 decodes a script as ANSI and would mangle anything else.

.PARAMETER Components
    Comma-separated: skill, dsh, all. Default: auto-detect.
.PARAMETER SkillsDir
    Skills folder for the "skill" component. Alias: -SkillsRoot (former installer).
.PARAMETER DshHome
    DSH home for the "dsh" component. Defaults to $env:DSH_HOME, then ~/.dsh.
.PARAMETER Uninstall
    Remove what this script installed.
.PARAMETER MigrateLegacy
    Move installs made by the former installers into a backup folder, then continue.
.PARAMETER DryRun
    Print what would change and change nothing.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Components dsh -DshHome D:\dsh-home
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$Components,
    [Alias('SkillsRoot')]
    [string]$SkillsDir,
    [string]$DshHome,
    [switch]$Uninstall,
    [switch]$MigrateLegacy,
    [switch]$DryRun
)

function Invoke-PlanGateInstall {
    param([string]$Components, [string]$SkillsDir, [string]$DshHome,
          [bool]$Uninstall, [bool]$MigrateLegacy, [bool]$DryRun, [string]$ScriptRoot)

    $ErrorActionPreference = 'Stop'
    $RepoUrl = if ($env:PLAN_GATE_REPO_URL) { $env:PLAN_GATE_REPO_URL } else { 'https://github.com/PakhomLeo/plan-gate.git' }
    $RepoRef = $env:PLAN_GATE_REF
    $SkillName = 'code-project-flow'
    $PluginFile = 'quick-dev-plan-arm.mjs'
    $Placeholder = '__QUICK_DEV_PLUGIN_URL__'
    $PresetId = 'preset-quick-dev'
    $Manifest = '.plan-gate-manifest'
    # sha256 of every plugin version ever shipped (LF line endings).
    $KnownPluginSha256 = @('414735eda972288f2f7d58a8cf9986290f1697f1578d8ad1e8699c317f337826')
    $SkillFiles = @('SKILL.md', 'references/AGENTS.md', 'references/HARNESS.md', 'references/MAP.md', 'references/TASK.md', 'LICENSE')
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    $script:skipped = $false
    $handled = @()

    function Say([string]$Text) { Write-Host "==> $Text" }
    function Warn([string]$Text) { Write-Warning $Text }
    function Plan([string]$Text) { if ($DryRun) { Write-Host "[dry-run] $Text" } }

    function Get-Sha256Lf([string]$Path) {
        $text = [System.IO.File]::ReadAllText($Path).Replace("`r", '')
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $bytes = $sha.ComputeHash($Utf8.GetBytes($text)) } finally { $sha.Dispose() }
        return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
    }

    # --- where the files come from ------------------------------------------
    $temporary = $null
    $sourceRoot = $null
    if ($ScriptRoot -and (Test-Path -LiteralPath (Join-Path $ScriptRoot 'SKILL.md')) -and (Test-Path -LiteralPath (Join-Path $ScriptRoot "dsh/plugin/$PluginFile"))) {
        $sourceRoot = $ScriptRoot
    }
    elseif (-not $Uninstall) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required but was not found on PATH.' }
        $temporary = Join-Path ([System.IO.Path]::GetTempPath()) ('plan-gate-' + [guid]::NewGuid().ToString('N'))
        Say "Fetching $RepoUrl"
        if ($RepoRef) { git clone --quiet --depth 1 --branch $RepoRef $RepoUrl $temporary }
        else { git clone --quiet --depth 1 $RepoUrl $temporary }
        if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }
        $sourceRoot = $temporary
    }
    $version = 'unknown'
    if ($sourceRoot -and (Test-Path -LiteralPath (Join-Path $sourceRoot 'VERSION'))) {
        $version = ([System.IO.File]::ReadAllText((Join-Path $sourceRoot 'VERSION'))).Trim()
    }

    try {
        # --- targets ---------------------------------------------------------
        if ($DshHome) { $dshRoot = $DshHome }
        elseif ($env:DSH_HOME) { $dshRoot = $env:DSH_HOME }
        else { $dshRoot = Join-Path $HOME '.dsh' }
        $qoderCn = Join-Path $HOME '.qoder-cn/skills'
        $qoderGlobal = Join-Path $HOME '.qoder/skills'
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupRoot = Join-Path $HOME ".plan-gate-backups/$stamp"

        if ($SkillsDir) { $skillsRoot = $SkillsDir }
        else {
            $skillsRoot = $null
            # An existing install wins, so an update lands where the old copy is.
            foreach ($root in @($qoderCn, $qoderGlobal)) {
                if (-not $skillsRoot -and (Test-Path -LiteralPath (Join-Path $root $SkillName))) { $skillsRoot = $root }
            }
            foreach ($root in @($qoderCn, $qoderGlobal)) {
                if (-not $skillsRoot -and (Test-Path -LiteralPath $root -PathType Container)) { $skillsRoot = $root }
            }
            if (-not $skillsRoot) { $skillsRoot = $qoderCn }
        }

        if (-not $Components) {
            $auto = @()
            if ($SkillsDir -or (Test-Path -LiteralPath $qoderCn -PathType Container) -or (Test-Path -LiteralPath $qoderGlobal -PathType Container)) { $auto += 'skill' }
            if ($DshHome -or (Test-Path -LiteralPath (Join-Path $dshRoot 'profiles') -PathType Container)) { $auto += 'dsh' }
            if ($auto.Count -eq 0) { $auto = @('skill') }
            $Components = $auto -join ','
            Say "Components (auto-detected): $Components"
        }
        $wantSkill = $false; $wantDsh = $false
        foreach ($c in ($Components -split ',')) {
            switch ($c.Trim()) {
                'skill' { $wantSkill = $true }
                'dsh' { $wantDsh = $true }
                'all' { $wantSkill = $true; $wantDsh = $true }
                '' { }
                default { Write-Error "Unknown component: $c (use skill, dsh or all)" -ErrorAction Continue; return 2 }
            }
        }

        # --- skill folders ---------------------------------------------------
        function Get-SkillState([string]$Dir) {
            if (-not (Test-Path -LiteralPath $Dir)) { return 'absent' }
            if (Test-Path -LiteralPath (Join-Path $Dir $Manifest)) { return 'owned' }
            $skillMd = Join-Path $Dir 'SKILL.md'
            if ((Test-Path -LiteralPath $skillMd) -and (Select-String -LiteralPath $skillMd -Pattern "^name: $SkillName\s*$" -Quiet)) { return 'legacy' }
            return 'foreign'
        }

        # What the two former installers wrote (checked against their source):
        #   code-project-flow (2026-09-28..10-03): `git clone --depth 1` of the
        #     whole repository into <skills>\code-project-flow (<skills> was
        #     -SkillsRoot, ~\.qoder\skills or ~\.qoder-cn\skills). Marker:
        #     .git\config with origin github.com/PakhomLeo/code-project-flow.
        #   dsh-quick-dev (2026-09-29..10-21): $DSH_HOME\skills\code-project-flow\
        #     (SKILL.md + references\, no LICENSE, no marker file), the plugin
        #     (see $KnownPluginSha256), one preset-quick-dev block per profile
        #     layer and, only after an interrupted run, cordis.patch.yml.dsh-quick-dev.tmp.
        $LegacyCheckoutFiles = @('.gitattributes', '.gitignore', 'LICENSE', 'README.en.md', 'README.md', 'SKILL.md', 'install.ps1', 'install.sh', 'references/AGENTS.md', 'references/HARNESS.md', 'references/MAP.md', 'references/TASK.md')
        $LegacyCopyFiles = @('SKILL.md', 'references/AGENTS.md', 'references/HARNESS.md', 'references/MAP.md', 'references/TASK.md')
        $LegacyTmpSuffix = '.dsh-quick-dev.tmp'

        function Get-LegacyKind([string]$Dir) {
            $config = Join-Path $Dir '.git/config'
            if ((Test-Path -LiteralPath $config -PathType Leaf) -and (Select-String -LiteralPath $config -Pattern 'github\.com[:/]PakhomLeo/code-project-flow(\.git)?\s*$' -Quiet)) {
                return 'code-project-flow git checkout'
            }
            if (Test-Path -LiteralPath (Join-Path $Dir '.git')) { return 'git checkout of unknown origin' }
            if ($Dir.StartsWith((Join-Path $dshRoot 'skills') + [System.IO.Path]::DirectorySeparatorChar)) { return 'dsh-quick-dev copy' }
            return 'manual copy'
        }

        function Get-LegacyExtras([string]$Dir) {
            $known = if ((Get-LegacyKind $Dir) -eq 'code-project-flow git checkout') { $LegacyCheckoutFiles } else { $LegacyCopyFiles }
            $full = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\', '/')
            $files = @(Get-ChildItem -LiteralPath $full -Recurse -File -Force | ForEach-Object {
                $_.FullName.Substring($full.Length + 1).Replace('\', '/')
            } | Where-Object { -not ($_ -eq '.git' -or $_.StartsWith('.git/')) } | Sort-Object -CaseSensitive)
            return @($files | Where-Object { $known -notcontains $_ })
        }

        function Show-Legacy([string]$Dir) {
            Say "Found a $(Get-LegacyKind $Dir) made by a former installer: $Dir"
            $extras = @(Get-LegacyExtras $Dir)
            if ($extras.Count -gt 0) {
                Say '  Files the former installer did not write (they stay in the folder or its backup):'
                foreach ($e in $extras) { Write-Host "      $e" }
            }
        }

        function Get-Label([string]$Path) { return (($Path -replace '^[A-Za-z]:', '') -replace '^[\\/]+', '' -replace '[\\/: ]', '_') }

        function Move-ToBackup([string]$Path) {
            $dest = Join-Path $backupRoot (Get-Label $Path)
            Plan "move $Path to $dest"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
                Move-Item -LiteralPath $Path -Destination $dest
            }
            Say "Moved legacy install $Path to $dest (delete it yourself once you no longer need it)"
        }

        function Confirm-Legacy([string]$Path) {
            if ($MigrateLegacy) { return $true }
            if (-not $DryRun -and -not [Console]::IsInputRedirected) {
                $answer = Read-Host "Found an install made by a former installer: $Path`nMove it to $backupRoot and continue? [y/N]"
                return ($answer -match '^(y|yes)$')
            }
            return $false
        }

        # The source uses docs/MAP.md etc. The DSH mode auto-loads documents by
        # bare file name from the project root, so "root" drops the docs/ prefix.
        function Write-Rendered([string]$Src, [string]$Dest, [string]$Layout) {
            if ($Layout -eq 'root') {
                $text = [System.IO.File]::ReadAllText($Src)
                $text = $text.Replace('docs/MAP.md', 'MAP.md').Replace('docs/HARNESS.md', 'HARNESS.md').Replace('docs/TASK.md', 'TASK.md')
                [System.IO.File]::WriteAllText($Dest, $text, $Utf8)
            }
            else { Copy-Item -LiteralPath $Src -Destination $Dest -Force }
        }

        function Install-Skill([string]$Dir, [string]$Layout) {
            $state = Get-SkillState $Dir
            if ($state -eq 'foreign') {
                Warn "$Dir exists and is not a code-project-flow install. Rename or remove it yourself, then run again."
                $script:skipped = $true; return $false
            }
            if ($state -eq 'legacy') {
                Show-Legacy $Dir
                if (Confirm-Legacy $Dir) { Move-ToBackup $Dir; $state = 'absent' }
                else {
                    Warn "Legacy install left untouched: $Dir. Re-run with -MigrateLegacy to move it to a backup folder and install."
                    $script:skipped = $true; return $false
                }
            }
            $old = @()
            if ($state -eq 'owned') { $old = @(Get-Content -LiteralPath (Join-Path $Dir $Manifest) | Where-Object { $_ -and -not $_.StartsWith('#') }) }
            foreach ($f in $SkillFiles) {
                $dest = Join-Path $Dir $f
                Plan "write $dest"
                if (-not $DryRun) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
                    Write-Rendered (Join-Path $sourceRoot $f) $dest $Layout
                }
            }
            foreach ($f in $old) {
                $stale = Join-Path $Dir $f
                if (($SkillFiles -notcontains $f) -and (Test-Path -LiteralPath $stale -PathType Leaf)) {
                    Plan "remove stale $stale"
                    if (-not $DryRun) { Remove-Item -LiteralPath $stale -Force }
                }
            }
            if (-not $DryRun) {
                $lines = @("# plan-gate $version skill=code-project-flow layout=$Layout. Files below were written by install.sh/install.ps1.") + $SkillFiles
                [System.IO.File]::WriteAllText((Join-Path $Dir $Manifest), (($lines -join "`n") + "`n"), $Utf8)
            }
            Say "Installed skill ($Layout layout) $Dir"
            return $true
        }

        function Uninstall-Skill([string]$Dir) {
            switch (Get-SkillState $Dir) {
                'absent' { Say "Nothing at $Dir" }
                'foreign' { Warn "$Dir is not a code-project-flow install; left untouched." }
                'legacy' {
                    Show-Legacy $Dir
                    if (Confirm-Legacy $Dir) { Move-ToBackup $Dir }
                    else { Warn "Legacy install left untouched: $Dir. Re-run with -MigrateLegacy to move it to a backup folder."; $script:skipped = $true }
                }
                'owned' {
                    $files = @(Get-Content -LiteralPath (Join-Path $Dir $Manifest) | Where-Object { $_ -and -not $_.StartsWith('#') }) + @($Manifest)
                    foreach ($f in $files) {
                        $p = Join-Path $Dir $f
                        if (Test-Path -LiteralPath $p -PathType Leaf) { Plan "remove $p"; if (-not $DryRun) { Remove-Item -LiteralPath $p -Force } }
                    }
                    if (-not $DryRun) {
                        foreach ($d in @((Join-Path $Dir 'references'), $Dir)) {
                            if ((Test-Path -LiteralPath $d) -and -not (Get-ChildItem -LiteralPath $d -Force)) { Remove-Item -LiteralPath $d -Force }
                        }
                        if (Test-Path -LiteralPath $Dir) { Warn "Kept ${Dir}: it still holds files this script did not install." }
                    }
                    Say "Removed skill $Dir"
                }
            }
        }

        # --- DSH patch layer -------------------------------------------------
        function Get-Eol([string]$Text) { if ($Text.Contains("`r`n")) { return "`r`n" } return "`n" }

        # Line list plus the original trailing-newline state: install and
        # uninstall write it back unchanged, so a round trip is byte-identical.
        function Split-Lines([string]$Text, [string]$Eol) {
            $trailing = $Text.EndsWith($Eol)
            $body = if ($trailing) { $Text.Substring(0, $Text.Length - $Eol.Length) } else { $Text }
            # Assigning an if-expression unrolls a one-element array into a bare
            # string, so wrap it again: a layer holding only `[]` is one line.
            $lines = @(if ($body -ne '') { $body -split [regex]::Escape($Eol) })
            return [pscustomobject]@{ Lines = $lines; Trailing = $trailing }
        }
        function Join-Lines([string[]]$Lines, [string]$Eol, [bool]$Trailing) {
            if ($Lines.Count -eq 0) { return '' }
            $text = $Lines -join $Eol
            if ($Trailing) { $text += $Eol }
            return $text
        }
        function Select-Range([string[]]$Lines, [int]$From, [int]$To) {
            if ($From -gt $To) { return @() }
            return @($Lines[$From..$To])
        }
        # The block is found as YAML structure (the top-level `- insert:` entry
        # that inserts preset-quick-dev), never by comment markers: a trailing
        # marker comment would land inside the last plugin row's text.
        function Find-Entry([string[]]$Lines) {
            for ($i = 0; $i -lt $Lines.Count; $i++) {
                if ($Lines[$i] -ne '- insert:') { continue }
                $end = $i + 1
                while ($end -lt $Lines.Count -and -not $Lines[$end].StartsWith('- ')) { $end++ }
                for ($k = $i + 1; $k -lt $end; $k++) {
                    if ($Lines[$k] -match "^\s*- id: $PresetId\s*$") { return [pscustomobject]@{ Start = $i; End = $end } }
                }
                $i = $end - 1
            }
            return $null
        }
        function Write-Block([string]$PatchPath, [string[]]$BlockLines) {
            $text = [System.IO.File]::ReadAllText($PatchPath)
            $eol = Get-Eol $text
            $file = Split-Lines $text $eol
            $lines = @($file.Lines)
            $entry = Find-Entry $lines
            if ($entry) {
                $updated = (Select-Range $lines 0 ($entry.Start - 1)) + $BlockLines + (Select-Range $lines $entry.End ($lines.Count - 1))
            }
            else {
                $significant = @($lines | Where-Object { $_ -notmatch '^\s*(#|$)' })
                if ($significant.Count -eq 1 -and $significant[0].Trim() -eq '[]') {
                    $index = 0
                    while ($lines[$index].Trim() -ne '[]') { $index++ }
                    $updated = (Select-Range $lines 0 ($index - 1)) + $BlockLines + (Select-Range $lines ($index + 1) ($lines.Count - 1))
                }
                else { $updated = @($lines) + $BlockLines }
            }
            [System.IO.File]::WriteAllText($PatchPath, (Join-Lines $updated $eol $file.Trailing), $Utf8)
        }
        function Remove-Block([string]$PatchPath) {
            $text = [System.IO.File]::ReadAllText($PatchPath)
            $eol = Get-Eol $text
            $file = Split-Lines $text $eol
            $lines = @($file.Lines)
            $entry = Find-Entry $lines
            if (-not $entry) { return $false }
            $updated = @(Select-Range $lines 0 ($entry.Start - 1)) + @(Select-Range $lines $entry.End ($lines.Count - 1))
            # The block may have replaced the empty array, and a patch layer
            # still needs one: put `[]` back when nothing else is left.
            if (-not ($updated | Where-Object { $_ -notmatch '^\s*(#|$)' })) { $updated += '[]' }
            [System.IO.File]::WriteAllText($PatchPath, (Join-Lines $updated $eol $file.Trailing), $Utf8)
            return $true
        }

        function Test-PluginOurs([string]$Path) {
            $sum = Get-Sha256Lf $Path
            if ($sourceRoot -and ($sum -eq (Get-Sha256Lf (Join-Path $sourceRoot "dsh/plugin/$PluginFile")))) { return $true }
            return ($KnownPluginSha256 -contains $sum)
        }

        function Invoke-Dsh {
            $profilesDir = Join-Path $dshRoot 'profiles'
            if (-not (Test-Path -LiteralPath $profilesDir -PathType Container)) {
                Warn "Not a DSH home directory (no profiles folder): $dshRoot. Start DSH once first, or pass -DshHome."
                $script:skipped = $true; return
            }
            $patches = @(Get-ChildItem -LiteralPath $profilesDir -Directory | ForEach-Object {
                $p = Join-Path $_.FullName 'cordis.patch.yml'
                if (Test-Path -LiteralPath $p -PathType Leaf) { $p }
            })
            if ($patches.Count -eq 0) { Warn "No profile patch layer under $profilesDir. Start DSH once first."; $script:skipped = $true; return }
            $plugin = Join-Path $dshRoot "plugins/$PluginFile"
            $skill = Join-Path $dshRoot "skills/$SkillName"
            $pluginUrl = (New-Object System.Uri ([System.IO.Path]::GetFullPath($plugin))).AbsoluteUri

            # Leftovers of an interrupted dsh-quick-dev run: moved aside only on request.
            foreach ($d in @(Get-ChildItem -LiteralPath $profilesDir -Directory)) {
                $tmp = Join-Path $d.FullName ('cordis.patch.yml' + $LegacyTmpSuffix)
                if (-not (Test-Path -LiteralPath $tmp -PathType Leaf)) { continue }
                if ($MigrateLegacy) { Move-ToBackup $tmp }
                else { Say "Note: leftover of an interrupted dsh-quick-dev run: $tmp (not changed; -MigrateLegacy moves it to the backup folder)." }
            }

            if ($Uninstall) {
                foreach ($patch in $patches) {
                    if (Select-String -LiteralPath $patch -SimpleMatch "- id: $PresetId" -Quiet) {
                        Plan "remove preset block from $patch"
                        if (-not $DryRun) { [void](Remove-Block $patch) }
                        Say "Removed preset block from $patch"
                    }
                }
                if (Test-Path -LiteralPath $plugin -PathType Leaf) {
                    if (Test-PluginOurs $plugin) { Plan "remove $plugin"; if (-not $DryRun) { Remove-Item -LiteralPath $plugin -Force }; Say "Removed $plugin" }
                    elseif (Confirm-Legacy $plugin) { Move-ToBackup $plugin }
                    else { Warn "Kept ${plugin}: its content differs from every shipped version. Re-run with -MigrateLegacy to move it to a backup folder."; $script:skipped = $true }
                }
                Uninstall-Skill $skill
                Say 'DSH: restart DSH for the mode to disappear from the picker.'
                return
            }

            # Skill first: if it is a legacy copy the user declines to move,
            # stop before the preset points DSH at a half-updated install.
            if (-not (Install-Skill $skill 'root')) { return }

            if ((Test-Path -LiteralPath $plugin -PathType Leaf) -and -not (Test-PluginOurs $plugin)) {
                if (Confirm-Legacy $plugin) { Move-ToBackup $plugin }
                else { Warn "Kept ${plugin}: its content differs from every shipped version. Re-run with -MigrateLegacy to replace it (the old file goes to a backup folder)."; $script:skipped = $true; return }
            }
            Plan "write $plugin"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $plugin) | Out-Null
                Copy-Item -LiteralPath (Join-Path $sourceRoot "dsh/plugin/$PluginFile") -Destination $plugin -Force
            }
            Say "Installed $plugin"

            $blockText = [System.IO.File]::ReadAllText((Join-Path $sourceRoot 'dsh/preset/quick-dev.patch.yml'))
            $blockLines = @($blockText.Replace($Placeholder, $pluginUrl).TrimEnd("`r", "`n") -split "`r?`n")
            foreach ($patch in $patches) {
                $verb = if (Select-String -LiteralPath $patch -SimpleMatch "- id: $PresetId" -Quiet) { 'Replaced the existing' } else { 'Wrote the' }
                Plan "write preset block into $patch"
                if (-not $DryRun) { Write-Block $patch $blockLines }
                Say "$verb preset 'quick-dev' block in $patch"
            }
            Say 'DSH: restart DSH, start a new blank session and pick the quick dev mode (second in the list).'
        }

        # --- run -------------------------------------------------------------
        if ($DryRun) { Say 'Dry run: nothing will be changed.' }
        if ($wantSkill) {
            $target = Join-Path $skillsRoot $SkillName
            $handled += $target
            if ($Uninstall) { Uninstall-Skill $target }
            else {
                Plan "create $skillsRoot"
                if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $skillsRoot | Out-Null }
                if (Install-Skill $target 'docs') { Say 'Skill: start a new agent session for it to take effect.' }
            }
        }
        if ($wantDsh) {
            $handled += (Join-Path $dshRoot "skills/$SkillName")
            Invoke-Dsh
        }
        # Point at old copies this run does not handle, without touching them.
        foreach ($root in @($qoderCn, $qoderGlobal, (Join-Path $dshRoot 'skills'))) {
            $dir = Join-Path $root $SkillName
            if (($handled -notcontains $dir) -and ((Get-SkillState $dir) -eq 'legacy')) {
                Say "Note: a $(Get-LegacyKind $dir) also exists at $dir (not changed). Use -Components/-SkillsDir to manage it."
            }
        }
        if ($script:skipped) { Write-Warning 'Finished with skipped steps (see warnings above).'; return 3 }
        Write-Host 'Done.'
        return 0
    }
    finally {
        if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -Recurse -Force -LiteralPath $temporary }
    }
}

# Only the last pipeline value is the exit code; anything a helper leaks before it is ignored.
$code = @(Invoke-PlanGateInstall -Components $Components -SkillsDir $SkillsDir -DshHome $DshHome `
    -Uninstall:$Uninstall.IsPresent -MigrateLegacy:$MigrateLegacy.IsPresent -DryRun:$DryRun.IsPresent -ScriptRoot $PSScriptRoot)[-1]
# Piped through Invoke-Expression there is no script file, and `exit` would
# close the caller's PowerShell window, so only exit when run as a file.
if ($PSCommandPath) { exit $code }
