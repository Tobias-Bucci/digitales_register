[CmdletBinding()]
param(
  [ValidateRange(10, 600)]
  [int]$PerFileTimeoutSeconds = 45,

  [ValidateRange(1, 300)]
  [int]$PerTestTimeoutSeconds = 20,

  [string]$TestFilter,

  [switch]$FailFast,

  [switch]$VerboseOutput,

  [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
  @'
Flutter test runner with summary

Usage:
  .\tool\test_summary.ps1 [Options]

Modes and options:
  -Help
      Shows this help page.

  -VerboseOutput
      Also prints the full output of successful test files.
      By default, details are printed only for failures and timeouts.

  -FailFast
      Stops after the first failure or timeout.

  -TestFilter <RegularExpression>
      Runs only test files whose path matches the expression.
      Example: -TestFilter 'calendar_sync'

  -PerFileTimeoutSeconds <Seconds>
      Maximum runtime for one test file. Default: 45.

  -PerTestTimeoutSeconds <Seconds>
      Flutter timeout for each individual test case. Default: 20.

Examples:
  .\tool\test_summary.ps1
  .\tool\test_summary.ps1 -VerboseOutput
  .\tool\test_summary.ps1 -TestFilter 'absences|calendar'
  .\tool\test_summary.ps1 -FailFast -PerFileTimeoutSeconds 60

Logs are saved under build\test-results\ after every run.
'@ | Write-Host
  exit 0
}

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$flutter = if ($env:FLUTTER_ROOT) {
  Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
} else {
  'flutter'
}
if ($flutter -ne 'flutter' -and -not (Test-Path -LiteralPath $flutter)) { $flutter = 'flutter' }

$tests = Get-ChildItem -Path (Join-Path $workspace 'test') -Recurse -Filter '*_test.dart' |
  Where-Object { -not $TestFilter -or $_.FullName -match $TestFilter } |
  Sort-Object FullName
if (-not $tests) {
  throw 'No matching test files found.'
}

$runStarted = Get-Date
$runId = $runStarted.ToString('yyyyMMdd-HHmmss')
$logDirectory = Join-Path $workspace "build\test-results\$runId"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$failed = [System.Collections.Generic.List[string]]::new()
$timedOut = [System.Collections.Generic.List[string]]::new()
$passed = 0

function Format-Elapsed([TimeSpan]$time) {
  return '{0:00}:{1:00}:{2:00}' -f [Math]::Floor($time.TotalHours), $time.Minutes, $time.Seconds
}

function Stop-TestProcessTree([int]$processId, [datetime]$startedAt) {
  & taskkill /PID $processId /T /F 2>$null | Out-Null

  # flutter_tester may survive if Flutter itself was interrupted. Limit cleanup
  # to test processes from this workspace and this runner invocation.
  Get-CimInstance Win32_Process -Filter "Name = 'flutter_tester.exe'" |
    Where-Object {
      $_.CreationDate -and
      ([System.Management.ManagementDateTimeConverter]::ToDateTime($_.CreationDate) -ge $startedAt) -and
      $_.CommandLine -like "*$workspace*"
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

Write-Host "Starting $($tests.Count) test files (file timeout: $PerFileTimeoutSeconds s, test timeout: $PerTestTimeoutSeconds s)."
Write-Host "Logs: $logDirectory"

for ($index = 0; $index -lt $tests.Count; $index++) {
  $test = $tests[$index]
  $relativePath = [IO.Path]::GetRelativePath($workspace, $test.FullName)
  $safeName = $relativePath.Replace('\', '_').Replace('/', '_')
  $output = Join-Path $logDirectory "$safeName.out.log"
  $error = Join-Path $logDirectory "$safeName.err.log"
  $testStarted = Get-Date

  Write-Host "`n[$($index + 1)/$($tests.Count)] $relativePath"
  $process = Start-Process -FilePath $flutter -ArgumentList @(
    'test', $relativePath, '--reporter', 'compact', '--timeout', "${PerTestTimeoutSeconds}s"
  ) -WorkingDirectory $workspace -NoNewWindow -PassThru `
    -RedirectStandardOutput $output -RedirectStandardError $error

  $timedOutThisTest = $false
  while (-not $process.HasExited) {
    $testElapsed = (Get-Date) - $testStarted
    $totalElapsed = (Get-Date) - $runStarted
    Write-Host -NoNewline ("`r  Total elapsed: {0} | current file: {1} | remaining until timeout: {2,2} s " -f `
      (Format-Elapsed $totalElapsed), (Format-Elapsed $testElapsed),
      [Math]::Max(0, $PerFileTimeoutSeconds - [Math]::Floor($testElapsed.TotalSeconds)))
    Start-Sleep -Seconds 1
    $process.Refresh()
    if ($testElapsed.TotalSeconds -ge $PerFileTimeoutSeconds) {
      $timedOutThisTest = $true
      Stop-TestProcessTree -processId $process.Id -startedAt $testStarted
      break
    }
  }
  Write-Host ''

  $content = @(Get-Content -LiteralPath $output,$error -ErrorAction SilentlyContinue)
  if ($VerboseOutput -or $timedOutThisTest -or $process.ExitCode -ne 0) {
    $content | ForEach-Object { Write-Host $_ }
  }

  if ($timedOutThisTest) {
    $timedOut.Add($relativePath)
    Write-Host "TIMEOUT after $PerFileTimeoutSeconds s" -ForegroundColor Yellow
  } elseif ($process.ExitCode -eq 0) {
    $passed++
    Write-Host "PASSED in $(Format-Elapsed ((Get-Date) - $testStarted))" -ForegroundColor Green
  } else {
    $failed.Add($relativePath)
    Write-Host "FAILED (exit code $($process.ExitCode))" -ForegroundColor Red
  }

  if ($FailFast -and ($timedOutThisTest -or $process.ExitCode -ne 0)) {
    break
  }
}

$total = $passed + $failed.Count + $timedOut.Count
Write-Host "`n================ Test Summary ================"
Write-Host "Total elapsed: $(Format-Elapsed ((Get-Date) - $runStarted))"
Write-Host "Executed: $total/$($tests.Count) | Passed: $passed | Failed: $($failed.Count) | Timed out: $($timedOut.Count)"
if ($failed.Count) {
  Write-Host 'Failed test files:' -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "  - $_" }
}
if ($timedOut.Count) {
  Write-Host 'Test files that timed out:' -ForegroundColor Yellow
  $timedOut | ForEach-Object { Write-Host "  - $_" }
}
Write-Host "Full logs: $logDirectory"
if ($failed.Count -or $timedOut.Count) { exit 1 }
Write-Host 'All tests passed.' -ForegroundColor Green
