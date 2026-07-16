[CmdletBinding()]
param(
  [ValidateRange(10, 600)]
  [int]$PerFileTimeoutSeconds = 45,

  [ValidateRange(1, 300)]
  [int]$PerTestTimeoutSeconds = 20,

  [string]$TestFilter,

  [ValidateRange(1, 16)]
  [int]$Parallel = 1,

  [ValidateRange(0, 3600)]
  [int]$ParallelSafetyTimeoutSeconds = 0,

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

  -Parallel <Workers>
      Runs test files concurrently through Flutter's own isolated test runner.
      Default: 1 (sequential). Recommended maximum: 4.

  -ParallelSafetyTimeoutSeconds <Seconds>
      Stops the entire parallel run after this time. Use this when one
      Flutter worker becomes stuck. Default: calculated from file timeout.

  -PerFileTimeoutSeconds <Seconds>
      Maximum runtime for one test file. Default: 45.

  -PerTestTimeoutSeconds <Seconds>
      Flutter timeout for each individual test case. Default: 20.

Examples:
  .\tool\test_summary.ps1
  .\tool\test_summary.ps1 -VerboseOutput
  .\tool\test_summary.ps1 -TestFilter 'absences|calendar'
  .\tool\test_summary.ps1 -Parallel 4
  .\tool\test_summary.ps1 -Parallel 4 -ParallelSafetyTimeoutSeconds 45
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
$activeTestProcesses = [System.Collections.Generic.List[object]]::new()

function Format-Elapsed([TimeSpan]$time) {
  return '{0:00}:{1:00}:{2:00}' -f [Math]::Floor($time.TotalHours), $time.Minutes, $time.Seconds
}

function Stop-TestProcessTree([int]$processId, [datetime]$startedAt) {
  & taskkill /PID $processId /T /F 2>$null | Out-Null

  # flutter_tester may survive if Flutter itself was interrupted. Limit cleanup
  # to test processes from this workspace and this runner invocation.
  Get-CimInstance Win32_Process -Filter "Name = 'flutter_tester.exe'" |
    Where-Object {
      if ($null -eq $_.CreationDate) { return $false }
      $createdAt = if ($_.CreationDate -is [datetime]) {
        $_.CreationDate
      } else {
        [System.Management.ManagementDateTimeConverter]::ToDateTime(
          [string]$_.CreationDate
        )
      }
      ($createdAt -ge $startedAt) -and
      $_.CommandLine -like "*$workspace*"
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Stop-ActiveTestProcesses {
  foreach ($active in @($activeTestProcesses)) {
    Stop-TestProcessTree -processId $active.ProcessId -startedAt $active.StartedAt
  }
  $activeTestProcesses.Clear()
}

trap {
  Write-Host "`nTest run interrupted. Cleaning up test processes..." -ForegroundColor Yellow
  Stop-ActiveTestProcesses
  exit 130
}

function Get-ParallelProgress([string]$path) {
  $suiteTestCounts = @{}
  $testSuites = @{}
  $completedTests = @{}

  foreach ($line in Get-Content -LiteralPath $path -ErrorAction SilentlyContinue) {
    if (-not $line.StartsWith('{')) { continue }
    try { $event = $line | ConvertFrom-Json } catch { continue }
    if ($event.type -eq 'group' -and $null -eq $event.group.parentID) {
      $suiteTestCounts[[int]$event.group.suiteID] = [int]$event.group.testCount
    } elseif ($event.type -eq 'testStart') {
      $testSuites[[int]$event.test.id] = [int]$event.test.suiteID
    } elseif ($event.type -eq 'testDone') {
      $testId = [int]$event.testID
      if ($testSuites.ContainsKey($testId) -and -not [bool]$event.hidden) {
        $suiteId = $testSuites[$testId]
        $completedTests[$suiteId] = 1 + ($completedTests[$suiteId] ?? 0)
      }
    }
  }

  return @($suiteTestCounts.Keys | Where-Object {
    $completedTests[$_] -ge $suiteTestCounts[$_]
  }).Count
}

Write-Host "Starting $($tests.Count) test files (file timeout: $PerFileTimeoutSeconds s, test timeout: $PerTestTimeoutSeconds s)."
Write-Host "Logs: $logDirectory"

if ($Parallel -gt 1) {
  Write-Host "Parallel mode: $Parallel independent test processes."
  $nextIndex = 0
  $running = [System.Collections.Generic.List[object]]::new()
  while ($nextIndex -lt $tests.Count -or $running.Count) {
    while ($nextIndex -lt $tests.Count -and $running.Count -lt $Parallel) {
      $test = $tests[$nextIndex++]
      $relativePath = [IO.Path]::GetRelativePath($workspace, $test.FullName)
      $safeName = $relativePath.Replace('\', '_').Replace('/', '_')
      $output = Join-Path $logDirectory "$safeName.out.log"
      $error = Join-Path $logDirectory "$safeName.err.log"
      $startedAt = Get-Date
      $process = Start-Process -FilePath $flutter -ArgumentList @(
        'test', $relativePath, '--reporter', 'compact', '--timeout', "${PerTestTimeoutSeconds}s"
      ) -WorkingDirectory $workspace -NoNewWindow -PassThru `
        -RedirectStandardOutput $output -RedirectStandardError $error
      $entry = [pscustomobject]@{
        Process = $process; StartedAt = $startedAt; Path = $relativePath
        Output = $output; Error = $error
      }
      $running.Add($entry)
      $activeTestProcesses.Add([pscustomobject]@{ ProcessId = $process.Id; StartedAt = $startedAt })
    }

    foreach ($entry in @($running)) {
      $entry.Process.Refresh()
      $elapsed = (Get-Date) - $entry.StartedAt
      $timedOutThisTest = -not $entry.Process.HasExited -and
        $elapsed.TotalSeconds -ge $PerFileTimeoutSeconds
      if (-not $entry.Process.HasExited -and -not $timedOutThisTest) { continue }
      if ($timedOutThisTest) { Stop-TestProcessTree $entry.Process.Id $entry.StartedAt }
      $null = $running.Remove($entry)
      $null = $activeTestProcesses.RemoveAll([Predicate[object]]{ param($p) $p.ProcessId -eq $entry.Process.Id })
      if ($timedOutThisTest) {
        $timedOut.Add($entry.Path)
        Write-Host "`nTIMEOUT: $($entry.Path)" -ForegroundColor Yellow
      } elseif ($entry.Process.ExitCode -eq 0) {
        $passed++
        Write-Host "`nPASSED: $($entry.Path)" -ForegroundColor Green
      } else {
        $failed.Add($entry.Path)
        Write-Host "`nFAILED: $($entry.Path)" -ForegroundColor Red
      }
      if ($VerboseOutput -or $timedOutThisTest -or $entry.Process.ExitCode -ne 0) {
        Get-Content -LiteralPath $entry.Output,$entry.Error -ErrorAction SilentlyContinue
      }
    }

    $completed = $passed + $failed.Count + $timedOut.Count
    $elapsed = (Get-Date) - $runStarted
    $eta = if ($completed) {
      Format-Elapsed ([TimeSpan]::FromSeconds($elapsed.TotalSeconds / $completed * ($tests.Count - $completed)))
    } else { '--:--:--' }
    Write-Host -NoNewline ("`r  Files: {0}/{1} complete | running: {2} | elapsed: {3} | ETA: {4} " -f `
      $completed, $tests.Count, $running.Count, (Format-Elapsed $elapsed), $eta)
    Start-Sleep -Seconds 1
  }
  Stop-ActiveTestProcesses
  Write-Host ''
  $total = $passed + $failed.Count + $timedOut.Count
  Write-Host "`n================ Test Summary ================"
  Write-Host "Total elapsed: $(Format-Elapsed ((Get-Date) - $runStarted))"
  Write-Host "Executed: $total/$($tests.Count) | Passed: $passed | Failed: $($failed.Count) | Timed out: $($timedOut.Count)"
  if ($failed.Count) { Write-Host 'Failed test files:' -ForegroundColor Red; $failed | ForEach-Object { Write-Host "  - $_" } }
  if ($timedOut.Count) { Write-Host 'Test files that timed out:' -ForegroundColor Yellow; $timedOut | ForEach-Object { Write-Host "  - $_" } }
  Write-Host "Full logs: $logDirectory"
  if ($failed.Count -or $timedOut.Count) { exit 1 }
  Write-Host 'All tests passed.' -ForegroundColor Green
  exit 0
}

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
  $activeTestProcesses.Add([pscustomobject]@{ ProcessId = $process.Id; StartedAt = $testStarted })

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
  Stop-ActiveTestProcesses
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
