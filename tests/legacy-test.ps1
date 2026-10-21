# Makes real installs with the former installers' own install.ps1 (from the
# git bundles in tests/fixtures/legacy, offline), then checks that install.ps1
# recognises and migrates them. Runs under Windows PowerShell 5.1 and pwsh:
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\legacy-test.ps1
#   pwsh -NoProfile -File tests/legacy-test.ps1
#
# Everything happens under a temp folder, removed at the end. Paths are passed
# explicitly; child processes also get it as HOME / USERPROFILE for backups.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixtures = Join-Path $root 'tests/fixtures/legacy'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('plan-gate-legacy-' + [guid]::NewGuid().ToString('N'))
$home2 = Join-Path $work 'home'
New-Item -ItemType Directory -Force -Path $home2 | Out-Null
$env:HOME = $home2; $env:USERPROFILE = $home2
Remove-Item Env:DSH_HOME -ErrorAction SilentlyContinue
$shell = (Get-Process -Id $PID).Path
$script:failed = 0; $script:passed = 0

function Check([string]$Name, [bool]$Ok) {
    if ($Ok) { $script:passed++; Write-Host "  ok   $Name" } else { $script:failed++; Write-Host "  FAIL $Name" }
}
function Invoke-Git {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & git -c init.defaultBranch=main @args 2>&1 | Out-Null
    $code = $LASTEXITCODE; $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "git $args failed ($code)" }
}
function Invoke-Script([string]$Path, [string[]]$Arguments) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return New-Object PSObject -Property @{ Code = $code; Out = $out }
}
function Get-TreeHash([string]$Dir) {
    $full = (Resolve-Path -LiteralPath $Dir).Path
    $lines = @(Get-ChildItem -LiteralPath $full -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | ForEach-Object {
        $_.FullName.Substring($full.Length).Replace('\', '/') + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    } | Sort-Object)
    return ($lines -join "`n")
}
function Get-BackupOf([string]$Out, [string]$Path) {
    foreach ($line in ($Out -split "`r?`n")) {
        $prefix = "==> Moved legacy install $Path to "
        if ($line.StartsWith($prefix)) { return ($line.Substring($prefix.Length) -replace ' \(delete it yourself.*$', '') }
    }
    return ''
}

try {
    Write-Host '1. former code-project-flow install.ps1'
    $src = Join-Path $work 'cpf-src'; $bare = Join-Path $work 'cpf.git'
    Invoke-Git clone -q (Join-Path $fixtures 'code-project-flow.bundle') $src
    Invoke-Git clone -q --bare (Join-Path $fixtures 'code-project-flow.bundle') $bare
    $skills = Join-Path $home2 '.qoder/skills'
    New-Item -ItemType Directory -Force -Path $skills | Out-Null
    # Point the GitHub URL the former script clones at the local bundle copy.
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'url.' + (New-Object System.Uri $bare).AbsoluteUri + '.insteadOf'
    $env:GIT_CONFIG_VALUE_0 = 'https://github.com/PakhomLeo/code-project-flow.git'
    $old = Invoke-Script (Join-Path $src 'install.ps1') @('-SkillsRoot', $skills)
    Remove-Item Env:GIT_CONFIG_COUNT, Env:GIT_CONFIG_KEY_0, Env:GIT_CONFIG_VALUE_0
    $L = Join-Path $skills 'code-project-flow'
    Check 'fixture: the former installer cloned PakhomLeo/code-project-flow' (($old.Code -eq 0) -and (Select-String -LiteralPath (Join-Path $L '.git/config') -SimpleMatch 'url = https://github.com/PakhomLeo/code-project-flow.git' -Quiet) -and (Test-Path -LiteralPath (Join-Path $L 'README.en.md')))
    Set-Content -LiteralPath (Join-Path $L 'my-notes.md') -Value 'mine'
    $before = Get-TreeHash $L
    $r = Invoke-Script (Join-Path $root 'install.ps1') @('-Components', 'skill', '-SkillsDir', $skills)
    Check 'recognised as a code-project-flow git checkout' ($r.Out.Contains("Found a code-project-flow git checkout made by a former installer: $L"))
    Check 'lists the user file only' (($r.Out -match '(?m)^      my-notes\.md\s*$') -and (@($r.Out -split "`r?`n" | Where-Object { $_ -match '^      \S' }).Count -eq 1))
    Check 'without -MigrateLegacy: exit 3, untouched' (($r.Code -eq 3) -and ($before -eq (Get-TreeHash $L)))
    $r = Invoke-Script (Join-Path $root 'install.ps1') @('-Components', 'skill', '-SkillsDir', $skills, '-MigrateLegacy')
    $B = Get-BackupOf $r.Out $L
    Check 'with -MigrateLegacy: whole checkout in the backup, unchanged' (($r.Code -eq 0) -and $B -and (Test-Path -LiteralPath (Join-Path $B '.git')) -and ($before -eq (Get-TreeHash $B)))
    Check 'with -MigrateLegacy: new install with manifest, no .git' ((Test-Path -LiteralPath (Join-Path $L '.plan-gate-manifest')) -and -not (Test-Path -LiteralPath (Join-Path $L '.git')))

    Write-Host '2. former dsh-quick-dev install.ps1'
    $src = Join-Path $work 'dsh-src'
    Invoke-Git clone -q (Join-Path $fixtures 'dsh-quick-dev.bundle') $src
    $D = Join-Path $home2 '.dsh'
    $web = Join-Path $D 'profiles/web'
    New-Item -ItemType Directory -Force -Path $web | Out-Null
    $layer = Join-Path $web 'cordis.patch.yml'
    [System.IO.File]::WriteAllText($layer, "# user layer`n- insert:`n    - id: my-row`n      name: my-plugin`n")
    $layerHash = (Get-FileHash -LiteralPath $layer -Algorithm SHA256).Hash
    $old = Invoke-Script (Join-Path $src 'install.ps1') @('-DshHome', $D)
    $skill = Join-Path $D 'skills/code-project-flow'
    Check 'fixture: the former installer wrote skill, plugin and block' (($old.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $skill 'SKILL.md')) -and (Test-Path -LiteralPath (Join-Path $D 'plugins/quick-dev-plan-arm.mjs')) -and (Select-String -LiteralPath $layer -SimpleMatch 'id: preset-quick-dev' -Quiet))
    $tmp = $layer + '.dsh-quick-dev.tmp'
    Set-Content -LiteralPath $tmp -Value 'partial'   # what an interrupted former run leaves
    $before = Get-TreeHash $D
    $r = Invoke-Script (Join-Path $root 'install.ps1') @('-Components', 'dsh', '-DshHome', $D)
    Check 'recognised as a dsh-quick-dev copy, leftover reported' ($r.Out.Contains("Found a dsh-quick-dev copy made by a former installer: $skill") -and $r.Out.Contains('leftover of an interrupted dsh-quick-dev run'))
    Check 'without -MigrateLegacy: exit 3, nothing changed' (($r.Code -eq 3) -and ($before -eq (Get-TreeHash $D)))
    $r = Invoke-Script (Join-Path $root 'install.ps1') @('-Components', 'dsh', '-DshHome', $D, '-MigrateLegacy')
    $plugin = Join-Path $D 'plugins/quick-dev-plan-arm.mjs'
    Check 'with -MigrateLegacy: skill copy and leftover moved to the backup' (($r.Code -eq 0) -and (Get-BackupOf $r.Out $skill) -and (Get-BackupOf $r.Out $tmp) -and -not (Test-Path -LiteralPath $tmp))
    Check 'plugin recognised as shipped: replaced, not backed up' ((-not (Get-BackupOf $r.Out $plugin)) -and ((Get-FileHash -LiteralPath $plugin).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root 'dsh/plugin/quick-dev-plan-arm.mjs')).Hash))
    Check 'one preset block, replaced in place' ($r.Out.Contains('Replaced the existing preset') -and (@(Select-String -LiteralPath $layer -SimpleMatch 'id: preset-quick-dev').Count -eq 1))
    $r = Invoke-Script (Join-Path $root 'install.ps1') @('-Components', 'dsh', '-DshHome', $D, '-Uninstall')
    Check 'uninstall: layer byte-identical to before the former install' (($r.Code -eq 0) -and ((Get-FileHash -LiteralPath $layer -Algorithm SHA256).Hash -eq $layerHash))
}
finally {
    Write-Host ''
    Write-Host "passed: $script:passed  failed: $script:failed"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:failed -ne 0) { exit 1 }
