@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem VPN connection test client for bash.ws.
rem Project: https://github.com/macvk/vpnleaktest
rem SPDX-License-Identifier: MIT

set "version=1.0.0"
set "api_domain=bash.ws"
set "program_name=%~nx0"
set "script_path=%~f0"
set "command_line=%program_name% %*"
set "interface="
set "verbose="
set "log_file="
set "probes=30"
set "parallel=30"
set "timeout=90"
set "short_output=0"
set "watch="
set "test_file=%TEMP%\vpnleaktest-%RANDOM%-%RANDOM%-test.tmp"
set "final_file=%TEMP%\vpnleaktest-%RANDOM%-%RANDOM%-final.tmp"

:parse_arguments
if "%~1" == "" goto arguments_parsed

if /I "%~1" == "-i" goto read_interface
if /I "%~1" == "--interface" goto read_interface
if /I "%~1" == "-p" goto read_probes
if /I "%~1" == "--probes" goto read_probes
if /I "%~1" == "-j" goto read_parallel
if /I "%~1" == "--parallel" goto read_parallel
if /I "%~1" == "-t" goto read_timeout
if /I "%~1" == "--timeout" goto read_timeout
if /I "%~1" == "-s" goto enable_short
if /I "%~1" == "--short" goto enable_short
if /I "%~1" == "-w" goto read_watch
if /I "%~1" == "--watch" goto read_watch
if /I "%~1" == "-v" goto read_verbose
if /I "%~1" == "--verbose" goto read_verbose
if /I "%~1" == "--log-file" goto read_log_file
if /I "%~1" == "-h" goto show_help
if /I "%~1" == "--help" goto show_help

call :argument_error "Unknown option: %~1"
exit /b 2

:read_interface
if "%~2" == "" (
    call :argument_error "Option %~1 requires a source IP address."
    exit /b 2
)
set "interface=%~2"
shift
shift
goto parse_arguments

:read_probes
if "%~2" == "" (
    call :argument_error "Option %~1 requires a number."
    exit /b 2
)
set "probes=%~2"
shift
shift
goto parse_arguments

:enable_short
set "short_output=1"
shift
goto parse_arguments

:read_watch
set "watch=0"
set "short_output=1"
shift
if "%~1" == "" goto parse_arguments
set "watch_value=%~1"
if "!watch_value:~0,1!" == "-" goto parse_arguments
set "watch=%~1"
shift
goto parse_arguments

:read_parallel
if "%~2" == "" (
    call :argument_error "Option %~1 requires a number."
    exit /b 2
)
set "parallel=%~2"
shift
shift
goto parse_arguments

:read_timeout
if "%~2" == "" (
    call :argument_error "Option %~1 requires a number."
    exit /b 2
)
set "timeout=%~2"
shift
shift
goto parse_arguments

:read_verbose
if "%~2" == "" (
    call :argument_error "Option %~1 requires info or trace."
    exit /b 2
)
set "verbose=%~2"
shift
shift
goto parse_arguments

:read_log_file
if "%~2" == "" (
    call :argument_error "Option --log-file requires a path."
    exit /b 2
)
set "log_file=%~2"
shift
shift
goto parse_arguments

:arguments_parsed
powershell -NoProfile -Command "if ($env:probes -notmatch '^[1-9][0-9]*$' -or [int]$env:probes -gt 100) { exit 1 }"

if errorlevel 1 (
    call :argument_error "Invalid probe count '%probes%'; expected an integer from 1 to 100."
    exit /b 2
)

if defined watch (
    powershell -NoProfile -Command "if ($env:watch -notmatch '^(0|[1-9][0-9]*)$') { exit 1 }"

    if errorlevel 1 (
        call :argument_error "Invalid watch interval '%watch%'; expected zero or a positive number of seconds."
        exit /b 2
    )
)

powershell -NoProfile -Command "if ($env:parallel -notmatch '^[1-9][0-9]*$' -or [int]$env:parallel -gt 100) { exit 1 }"

if errorlevel 1 (
    call :argument_error "Invalid parallel count '%parallel%'; expected an integer from 1 to 100."
    exit /b 2
)

powershell -NoProfile -Command "if ($env:timeout -notmatch '^[1-9][0-9]*$' -or [int]$env:timeout -lt 10 -or [int]$env:timeout -gt 300) { exit 1 }"

if errorlevel 1 (
    call :argument_error "Invalid timeout '%timeout%'; expected an integer from 10 to 300."
    exit /b 2
)

if defined verbose (
    if /I not "%verbose%" == "info" (
        if /I not "%verbose%" == "trace" (
            call :argument_error "Invalid verbosity level '%verbose%'; expected info or trace."
            exit /b 2
        )
    )
)

if defined log_file (
    if not defined verbose set "verbose=info"
)

if defined verbose (
    if not defined log_file (
        if defined LOCALAPPDATA (
            set "log_file=%LOCALAPPDATA%\vpnleaktest\vpnleaktest.log"
        ) else (
            set "log_file=%USERPROFILE%\AppData\Local\vpnleaktest\vpnleaktest.log"
        )
    )

    for %%D in ("!log_file!\..") do set "log_dir=%%~fD"

    if not exist "!log_dir!" mkdir "!log_dir!" 2>nul

    if not exist "!log_dir!" (
        call :argument_error "Cannot create diagnostic log directory: !log_dir!"
        exit /b 2
    )

    type nul >> "!log_file!"

    if errorlevel 1 (
        call :argument_error "Cannot create diagnostic log: !log_file!"
        exit /b 2
    )

    if not "%VPNLEAK_WATCH_CHILD%" == "1" echo Diagnostic log: !log_file!
)

call :log_info "%program_name% version %version% started; OS=Windows; requested_interface=%interface%; probes=%probes%; parallel=%parallel%"
call :log_info "Command line: !command_line!"

where curl.exe >nul 2>&1

if errorlevel 1 (
    call :fail "curl.exe is required."
    exit /b 1
)

call :log_info "Requesting test ID"

if /I "%verbose%" == "trace" (
    if defined interface (
        for /f "usebackq delims=" %%I in (`curl.exe --verbose --silent --show-error --fail --max-time "!timeout!" --interface "%interface%" "https://%api_domain%/id" 2^>^>"%log_file%"`) do set "leak_id=%%I"
    ) else (
        for /f "usebackq delims=" %%I in (`curl.exe --verbose --silent --show-error --fail --max-time "!timeout!" "https://%api_domain%/id" 2^>^>"%log_file%"`) do set "leak_id=%%I"
    )
) else (
    if defined interface (
        for /f "usebackq delims=" %%I in (`curl.exe --silent --show-error --fail --max-time "!timeout!" --interface "%interface%" "https://%api_domain%/id"`) do set "leak_id=%%I"
    ) else (
        for /f "usebackq delims=" %%I in (`curl.exe --silent --show-error --fail --max-time "!timeout!" "https://%api_domain%/id"`) do set "leak_id=%%I"
    )
)

if not defined leak_id (
    call :fail "Unable to obtain a test ID from %api_domain%."
    exit /b 1
)

powershell -NoProfile -Command "if ($env:leak_id -notmatch '^[a-zA-Z0-9]{16}$') { exit 1 }"

if errorlevel 1 (
    call :fail "Invalid test ID returned by %api_domain%."
    exit /b 1
)

call :log_info "Test ID received; bytes available"

if defined interface (
    call :log_info "Starting %probes% DNS probes with source IP %interface%"

    powershell -NoProfile -Command "& { for ($start = 1; $start -le %probes%; $start += %parallel%) { $end = [Math]::Min($start + %parallel% - 1, %probes%); $procs = $start..$end | ForEach-Object { $hostName = ('{0}.%leak_id%.%api_domain%' -f $_); Start-Process ping.exe -ArgumentList @('-n','1','-w','1000','-S','%interface%',$hostName) -WindowStyle Hidden -PassThru }; $procs | Wait-Process -Timeout 3 -ErrorAction SilentlyContinue; $procs | Where-Object { -not $_.HasExited } | Stop-Process -Force } }"
) else (
    call :log_info "Starting %probes% DNS probes with the default route"

    powershell -NoProfile -Command "& { for ($start = 1; $start -le %probes%; $start += %parallel%) { $end = [Math]::Min($start + %parallel% - 1, %probes%); $tasks = $start..$end | ForEach-Object { [System.Net.Dns]::GetHostAddressesAsync(('{0}.%leak_id%.%api_domain%' -f $_)) }; try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks,2500) } catch {} } }"
)

if errorlevel 1 (
    call :fail "DNS probes failed."
    exit /b 1
)

call :request_test "https://%api_domain%/dnsleak/test/%leak_id%?txt" "DNS"
if errorlevel 1 exit /b 1

call :complete_vpn_checks
if errorlevel 1 exit /b 1

if "%short_output%" == "1" (
    call :print_line "%date%T%time% !test_result!"
) else (
    call :print_utf8_file "!final_file!"
    set "test_result=completed"
)

call :log_info "result=!test_result!"
call :log_info "vpnleaktest finished; exit=0"

del /q "%test_file%" "%final_file%" >nul 2>&1

if not defined watch exit /b 0

set "watch_args=-s -p %probes% -j %parallel% -t %timeout%"

if defined interface set "watch_args=!watch_args! -i "!interface!""
if defined verbose set "watch_args=!watch_args! -v !verbose!"
if defined log_file set "watch_args=!watch_args! --log-file "!log_file!""

:watch_loop
if not "%watch%" == "0" timeout /t %watch% /nobreak >nul
set "VPNLEAK_WATCH_CHILD=1"
call "!script_path!" !watch_args!
goto watch_loop

:complete_vpn_checks
set "ipv4="
set "ipv6="

if defined interface (
    for /f "usebackq delims=" %%I in (`curl.exe --silent --show-error --fail --max-time "!timeout!" -4 --interface "!interface!" "https://ipv4.%api_domain%/myip/test/%leak_id%" 2^>nul`) do set "ipv4=%%I"
    for /f "usebackq delims=" %%I in (`curl.exe --silent --show-error --fail --max-time "!timeout!" -6 --interface "!interface!" "https://ipv6.%api_domain%/myip/test/%leak_id%" 2^>nul`) do set "ipv6=%%I"
) else (
    for /f "usebackq delims=" %%I in (`curl.exe --silent --show-error --fail --max-time "!timeout!" -4 "https://ipv4.%api_domain%/myip/test/%leak_id%" 2^>nul`) do set "ipv4=%%I"
    for /f "usebackq delims=" %%I in (`curl.exe --silent --show-error --fail --max-time "!timeout!" -6 "https://ipv6.%api_domain%/myip/test/%leak_id%" 2^>nul`) do set "ipv6=%%I"
)

call :start_test "/open-port-check/test/%leak_id%" "port"
if errorlevel 1 exit /b 1

call :request_test "https://%api_domain%/open-port-check/test/%leak_id%?txt" "port"
if errorlevel 1 exit /b 1

if defined ipv4 (
    call :start_test "/ip-blacklist-check/test/%leak_id%/ipv4" "IPv4 blacklist"
    if errorlevel 1 exit /b 1

    call :request_test "https://%api_domain%/ip-blacklist-check/test/%leak_id%/ipv4?txt" "IPv4 blacklist"
    if errorlevel 1 exit /b 1
)

if defined ipv6 (
    call :start_test "/ip-blacklist-check/test/%leak_id%/ipv6" "IPv6 blacklist"
    if errorlevel 1 exit /b 1

    call :request_test "https://%api_domain%/ip-blacklist-check/test/%leak_id%/ipv6?txt" "IPv6 blacklist"
    if errorlevel 1 exit /b 1
)

call :request_final
if errorlevel 1 exit /b 1

if "%short_output%" == "1" set "test_result=!final_conclusion!"
exit /b 0

:start_test
call :log_info "Starting %~2 check"

if defined interface (
    curl.exe --silent --show-error --fail --max-time "!timeout!" --interface "!interface!" --request POST "https://%api_domain%%~1" --output "!test_file!"
) else (
    curl.exe --silent --show-error --fail --max-time "!timeout!" --request POST "https://%api_domain%%~1" --output "!test_file!"
)

if errorlevel 1 (
    call :fail "Unable to start the %~2 check."
    exit /b 1
)

findstr /c:"done" "!test_file!" >nul

if errorlevel 1 (
    call :fail "Unable to start the %~2 check."
    exit /b 1
)

exit /b 0

:request_test
call :log_info "Requesting %~2 result"
if defined interface (
    curl.exe --silent --show-error --fail --max-time "!timeout!" --interface "!interface!" "%~1" --output "!test_file!"
) else (
    curl.exe --silent --show-error --fail --max-time "!timeout!" "%~1" --output "!test_file!"
)
if errorlevel 1 (
    call :fail "Unable to complete the %~2 check."
    exit /b 1
)

for %%I in ("!test_file!") do if %%~zI EQU 0 (
    call :fail "Empty response from the %~2 check."
    exit /b 1
)

set "test_error="
for /f "usebackq delims=" %%I in (`findstr /b /c:"ERROR: " "!test_file!" 2^>nul`) do if not defined test_error set "test_error=%%I"
if defined test_error (
    set "test_error=!test_error:~7!"
    call :fail "!test_error!"
    exit /b 1
)
exit /b 0

:request_final
call :log_info "Requesting final VPN connection result"
set "final_format=json"
if not "%short_output%" == "1" set "final_format=txt"
if defined interface (
    curl.exe --silent --show-error --fail --max-time "!timeout!" --interface "!interface!" "https://%api_domain%/vpn-leak-test/test/%leak_id%?!final_format!" --output "!final_file!"
) else (
    curl.exe --silent --show-error --fail --max-time "!timeout!" "https://%api_domain%/vpn-leak-test/test/%leak_id%?!final_format!" --output "!final_file!"
)
if errorlevel 1 (
    call :fail "Unable to retrieve the VPN connection result."
    exit /b 1
)

if not "%short_output%" == "1" exit /b 0

set "final_error="
set "final_conclusion="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$c = Get-Content -Raw -LiteralPath $env:final_file; if ($c.TrimStart().StartsWith('[')) { $j = ConvertFrom-Json -InputObject $c; foreach ($row in $j) { if ($row.type -eq 'error') { [Console]::Write([string]$row.text); break } } }"`) do set "final_error=%%I"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$c = Get-Content -Raw -LiteralPath $env:final_file; if ($c.TrimStart().StartsWith('[')) { $j = ConvertFrom-Json -InputObject $c; foreach ($row in $j) { if ($row.type -eq 'conclusion') { [Console]::Write([string]$row.text); break } } }"`) do set "final_conclusion=%%I"

if defined final_error (
    call :fail "!final_error!"
    exit /b 1
)

if not defined final_conclusion (
    call :fail "Invalid response from the VPN connection check."
    exit /b 1
)
exit /b 0

:print_utf8_file
set "console_code_page="
for /f "tokens=2 delims=:" %%I in ('chcp') do set "console_code_page=%%I"
set "console_code_page=!console_code_page: =!"
chcp 65001 >nul
type "%~1"
if defined console_code_page chcp !console_code_page! >nul
exit /b 0

:print_line
echo(%~1
call :log_info "%~1"
exit /b 0

:log_info
if not defined verbose exit /b 0
>>"!log_file!" echo %date%T%time% [INFO] %~1
exit /b 0

:log_trace
if /I not "!verbose!" == "trace" exit /b 0
>>"!log_file!" echo %date%T%time% [TRACE] %~1
exit /b 0

:argument_error
echo %~1 1>&2
echo Try '%program_name% --help' for more information. 1>&2
exit /b 0

:fail
echo %~1 1>&2
call :log_info "ERROR: %~1"
call :log_info "vpnleaktest finished; exit=1"
del /q "%test_file%" "%final_file%" >nul 2>&1
exit /b 1

:show_help
echo Usage: %program_name% [OPTIONS]
echo.
echo Options:
echo   -i, --interface IP        Use a specific source IP address
echo   -p, --probes NUMBER      Number of DNS probes to send ^(default: 30^)
echo   -j, --parallel NUMBER    Maximum simultaneous probes ^(default: 30^)
echo   -t, --timeout SECONDS    Maximum time for each request ^(default: 90^)
echo   -s, --short              Print a one-line result
echo   -w, --watch [SECONDS]    Repeat continuously ^(default interval: 0^)
echo   -v, --verbose LEVEL      Write diagnostics: info or trace
echo       --log-file FILE      Set the log path ^(implies --verbose info^)
echo   -h, --help               Show this help
exit /b 0
