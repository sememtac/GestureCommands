# Runs every test suite, each in its own process. Uses luajit, or Neovim's built-in LuaJIT (nvim -l).
# Usage: tests/run.ps1 [suite...]   e.g. tests/run.ps1 engine ui
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$lua = @()
if (Get-Command luajit -ErrorAction SilentlyContinue) { $lua = @("luajit") }
elseif (Get-Command nvim -ErrorAction SilentlyContinue) { $lua = @("nvim", "-l") }
elseif (Test-Path "$env:DEV_ROOT\Editors\Neovim\bin\nvim.exe") { $lua = @("$env:DEV_ROOT\Editors\Neovim\bin\nvim.exe", "-l") }
else { Write-Error "needs luajit or nvim" }
$suites = $args
if ($suites.Count -eq 0) { $suites = Get-ChildItem tests\*_test.lua | ForEach-Object { $_.Name -replace "_test\.lua$", "" } }
$env:GC_TESTS_QUIET = "1"
$failed = $false
foreach ($s in $suites) {
	$exe = $lua[0]; $rest = @($lua | Select-Object -Skip 1) + @("tests/${s}_test.lua")
	$out = & $exe @rest 2>&1 | ForEach-Object { "$_" }
	"{0,-8} {1}" -f $s, ($out | Select-Object -Last 1)
	if ($LASTEXITCODE -ne 0) { $out | Where-Object { $_ -notmatch "^ALL PASSED" } | ForEach-Object { "    $_" }; $failed = $true }
}
if ($failed) { exit 1 }
