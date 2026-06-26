<# :
@echo off
cd /d "%~dp0"

>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    powershell -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
    exit /b
)

set "SCRIPT_PATH=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SCRIPT_PATH))"
exit /b
#>

$ScriptPath = $env:SCRIPT_PATH
$AppVersion = "1.3"
$UpdateUrl  = "https://raw.githubusercontent.com/D1verlin/DNS-Manager/main/dns.bat"

$e       = [char]27
$MenuRow = 13   # Строка старта меню/панелей (шапка 11 строк + статус + пустая)

# Глобальный кэш статуса DNS для моментального рендеринга меню
$global:cachedProfileName = "Авто / Провайдер"
$global:cachedLatencyStr  = ""
$global:cachedDoHStr      = ""

[Console]::CursorVisible = $false
[Console]::Title = "DNS Manager v$AppVersion"

try {
    if ($host.Name -eq "ConsoleHost") {
        $w = 95
        $h = 32
        $rect = New-Object System.Management.Automation.Host.Size($w, $h)
        if ($host.UI.RawUI.BufferSize.Width -lt $w) {
            $host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size($w, $host.UI.RawUI.BufferSize.Height)
        }
        $host.UI.RawUI.WindowSize = $rect
        $host.UI.RawUI.BufferSize = $rect
    }
} catch {}

# ──────────────────────────────────────────────────────────────────────────────
# Централизованная база DNS-профилей
# ──────────────────────────────────────────────────────────────────────────────
$DnsProfiles = [ordered]@{
    "Xbox DNS (RU)"     = @{
        IPv4 = @("111.88.96.50", "111.88.96.51")
        IPv6 = @("2a00:ab00:1233:26::50", "2a00:ab00:1233:26::51")
        DoH  = "https://xbox-dns.ru/dns-query"
    }
    "Xbox DNS (РЕЗЕРВ)" = @{
        IPv4 = @("87.228.47.200", "87.228.47.201")
        IPv6 = @()
        DoH  = "https://xbox-dns.ru/dns-query"
    }
    "Comss DNS"         = @{
        IPv4 = @("76.76.2.0", "76.76.10.0")
        IPv6 = @("2606:1a40::", "2606:1a40:1::")
        DoH  = "https://freedns.controld.com/comss"
    }
    "Cloudflare DNS"    = @{
        IPv4 = @("1.1.1.1", "1.0.0.1")
        IPv6 = @("2606:4700:4700::1111", "2606:4700:4700::1001")
        DoH  = "https://cloudflare-dns.com/dns-query"
    }
}


# ──────────────────────────────────────────────────────────────────────────────
# Определение текущего активного DNS-профиля
# ──────────────────────────────────────────────────────────────────────────────
function Get-CurrentDNSProfile {
    try {
        $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | 
            Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' }
        if (-not $interfaces) { return "Нет активных адаптеров" }
        foreach ($iface in $interfaces) {
            $props = $iface.GetIPProperties()
            if ($props -and $props.DnsAddresses) {
                $dnsList = $props.DnsAddresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
                if ($dnsList -and $dnsList.Count -gt 0) {
                    $firstDns = $dnsList[0].ToString()
                    foreach ($name in $DnsProfiles.Keys) {
                        if ($firstDns -eq $DnsProfiles[$name].IPv4[0]) { return $name }
                    }
                }
            }
        }
    } catch {}
    return "Авто / Провайдер"
}

# ──────────────────────────────────────────────────────────────────────────────
# Задержка (ping) до первого IP активного профиля
# ──────────────────────────────────────────────────────────────────────────────
function Get-CurrentDNSLatency {
    param([string]$ProfileName)
    $profile = $DnsProfiles[$ProfileName]
    if (-not $profile) { return $null }
    $ip = $profile.IPv4[0]
    if (-not $ip) { return $null }
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($ip, 500)
        if ($reply.Status -eq 'Success') { return $reply.RoundtripTime }
    } catch {}
    return $null
}

# ──────────────────────────────────────────────────────────────────────────────
# Статус DoH для активного профиля
# ──────────────────────────────────────────────────────────────────────────────
function Get-CurrentDoHStatus {
    param([string]$ProfileName)
    $profile = $DnsProfiles[$ProfileName]
    if (-not $profile) { return $false }
    $ip = $profile.IPv4[0]
    if (-not $ip) { return $false }
    try {
        $doh = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
        return ($doh -and $doh.AutoUpgrade -eq $true -and $doh.AllowFallbackToUdp -eq $false)
    } catch { return $false }
}

# ──────────────────────────────────────────────────────────────────────────────
# Единая функция прогресс-панели
# ──────────────────────────────────────────────────────────────────────────────
function Show-ProgressPanel {
    param(
        [int]    $Percent,
        [string] $Status,
        [string] $Label,
        [string] $LogLine1,
        [string] $LogLine2,
        [string] $LabelColor = "50;255;150"
    )
    [Console]::SetCursorPosition(0, $MenuRow)
    $barWidth = 44
    $filled   = [math]::Round(($Percent / 100) * $barWidth)
    $bar      = ("█" * $filled) + ("░" * ($barWidth - $filled))
    $bg  = "$e[48;2;30;30;30m"
    $rst = "$e[0m"
    $w   = 66

    Write-Host "  $bg$(" " * $w)$rst"
    $l1 = "   $e[38;2;${LabelColor}m${Label}:$e[38;2;255;255;255m $Status"
    $pad1 = [math]::Max(0, $w - "   ${Label}: $Status".Length)
    Write-Host "  $bg$l1$(" " * $pad1)$rst"

    Write-Host "  $bg$(" " * $w)$rst"
    $l2 = "   $e[38;2;50;255;150m$bar$e[38;2;255;255;255m $($Percent.ToString().PadLeft(3))% "
    $pad2 = [math]::Max(0, $w - "   $bar $($Percent.ToString().PadLeft(3))% ".Length)
    Write-Host "  $bg$l2$(" " * $pad2)$rst"

    Write-Host "  $bg$(" " * $w)$rst"
    $v3 = "   $LogLine1"; $pad3 = [math]::Max(0, $w - $v3.Length)
    Write-Host "  $bg$e[38;2;180;180;180m$v3$(" " * $pad3)$rst"
    $v4 = "   $LogLine2"; $pad4 = [math]::Max(0, $w - $v4.Length)
    Write-Host "  $bg$e[38;2;180;180;180m$v4$(" " * $pad4)$rst"
    Write-Host "  $bg$(" " * $w)$rst"
}

# ──────────────────────────────────────────────────────────────────────────────
# Применение выбранного DNS-профиля
# ──────────────────────────────────────────────────────────────────────────────
function Apply-DNS {
    param([string]$ProfileName)
    $profile     = $DnsProfiles[$ProfileName]
    $DnsList     = $profile.IPv4 + $profile.IPv6
    $DoHTemplate = $profile.DoH

    Show-ProgressPanel -Percent 10 -Status "Инициализация параметров..." `
        -Label "УСТАНОВКА $ProfileName" -LogLine1 "" -LogLine2 ""
    Start-Sleep -Milliseconds 250

    Show-ProgressPanel -Percent 30 -Status "Сканирование сетевых интерфейсов..." `
        -Label "УСТАНОВКА $ProfileName" -LogLine1 "" -LogLine2 ""
    $adapters = Get-NetAdapter | Where-Object Status -eq 'Up'
    Start-Sleep -Milliseconds 250

    $l1 = ""; $l2 = ""
    Show-ProgressPanel -Percent 50 -Status "Изменение конфигурации IP..." `
        -Label "УСТАНОВКА $ProfileName" -LogLine1 "" -LogLine2 ""
    foreach ($adapter in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                -ServerAddresses $DnsList -ErrorAction Stop
            $l1 = "[$($adapter.Name)] Адреса успешно назначены."
        } catch {
            $l1 = "[$($adapter.Name)] Ошибка конфигурации адресов."
        }
        Show-ProgressPanel -Percent 65 -Status "Изменение конфигурации IP..." `
            -Label "УСТАНОВКА $ProfileName" -LogLine1 $l1 -LogLine2 ""
        Start-Sleep -Milliseconds 250
    }

    Show-ProgressPanel -Percent 75 -Status "Активация шифрования DoH..." `
        -Label "УСТАНОВКА $ProfileName" -LogLine1 $l1 -LogLine2 ""
    try {
        foreach ($server in $DnsList) {
            Set-DnsClientDohServerAddress -ServerAddress $server -DohTemplate $DoHTemplate `
                -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
        }
        $l2 = "Безопасный туннель DoH запущен."
    } catch {
        $l2 = "Инфраструктура DoH недоступна в этой ОС."
    }

    Show-ProgressPanel -Percent 90 -Status "Перезагрузка кэша распознавателя..." `
        -Label "УСТАНОВКА $ProfileName" -LogLine1 $l1 -LogLine2 $l2
    Start-Sleep -Milliseconds 250

    Clear-DnsClientCache
    Show-ProgressPanel -Percent 100 -Status "Операция успешно завершена!" `
        -Label "УСТАНОВКА $ProfileName" -LogLine1 $l1 -LogLine2 $l2

    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

# ──────────────────────────────────────────────────────────────────────────────
# Сброс всех DNS
# ──────────────────────────────────────────────────────────────────────────────
function Clear-AllDNS {
    Show-ProgressPanel -Percent 10 -Status "Сканирование адаптеров..." `
        -Label "СБРОС НАСТРОЕК" -LogLine1 "" -LogLine2 "" -LabelColor "255;255;0"
    Start-Sleep -Milliseconds 250

    $adapters = Get-NetAdapter | Where-Object Status -eq 'Up'
    $l1 = ""; $l2 = ""

    Show-ProgressPanel -Percent 40 -Status "Перевод режимов в положение Авто..." `
        -Label "СБРОС НАСТРОЕК" -LogLine1 "" -LogLine2 "" -LabelColor "255;255;0"
    foreach ($adapter in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
                -ResetServerAddresses -ErrorAction Stop
            $l1 = "[$($adapter.Name)] Возвращено автоматическое получение."
        } catch {
            $l1 = "[$($adapter.Name)] Ошибка деконфигурации адресов."
        }
        Show-ProgressPanel -Percent 60 -Status "Перевод режимов в положение Авто..." `
            -Label "СБРОС НАСТРОЕК" -LogLine1 $l1 -LogLine2 "" -LabelColor "255;255;0"
        Start-Sleep -Milliseconds 250
    }

    Show-ProgressPanel -Percent 75 -Status "Очистка таблиц шифрования DoH..." `
        -Label "СБРОС НАСТРОЕК" -LogLine1 $l1 -LogLine2 "" -LabelColor "255;255;0"
    $TargetIPs = @()
    foreach ($profile in $DnsProfiles.Values) {
        foreach ($ip in ($profile.IPv4 + $profile.IPv6)) {
            if ($ip) { $TargetIPs += $ip }
        }
    }
    foreach ($ip in $TargetIPs) {
        Set-DnsClientDohServerAddress -ServerAddress $ip `
            -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction SilentlyContinue
    }
    $l2 = "Параметры безопасности DoH аннулированы."

    Show-ProgressPanel -Percent 90 -Status "Очистка локального кэша DNS..." `
        -Label "СБРОС НАСТРОЕК" -LogLine1 $l1 -LogLine2 $l2 -LabelColor "255;255;0"
    Start-Sleep -Milliseconds 250

    Clear-DnsClientCache
    Show-ProgressPanel -Percent 100 -Status "Сброс успешно выполнен!" `
        -Label "СБРОС НАСТРОЕК" -LogLine1 $l1 -LogLine2 $l2 -LabelColor "255;255;0"

    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

# ──────────────────────────────────────────────────────────────────────────────
# Очистка только кэша DNS
# ──────────────────────────────────────────────────────────────────────────────
function Clear-DNSCacheOnly {
    Write-Host "  $e[38;2;50;255;150mОчистка локального кэша DNS...$e[0m`n"
    Clear-DnsClientCache
    Write-Host "  $e[38;2;255;255;255mКэш успешно очищен.$e[0m"
    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

# ──────────────────────────────────────────────────────────────────────────────
# Проверка задержки (ping) до всех DNS-серверов
# ──────────────────────────────────────────────────────────────────────────────
function Test-DNSLatency {
    Write-Host "  $e[38;2;50;255;150mПроверка задержки и разрешения DNS-серверов...$e[0m`n"
    $testDomains = @("google.com", "github.com", "microsoft.com")
    foreach ($name in $DnsProfiles.Keys) {
        Write-Host "  $e[38;2;100;200;255m$name$e[0m"
        foreach ($ip in $DnsProfiles[$name].IPv4) {
            Write-Host -NoNewline "    $e[38;2;180;180;180m$($ip.PadRight(20))$e[0m"
            $ping = Test-Connection -ComputerName $ip -Count 2 -ErrorAction SilentlyContinue
            if ($ping) {
                $avg   = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average)
                $color = if ($avg -lt 50) { "50;255;150" } elseif ($avg -lt 150) { "255;200;0" } else { "255;100;100" }
                Write-Host "$e[38;2;${color}m${avg} ms$e[0m $e[38;2;120;120;120m(ping)$e[0m"
            } else {
                Write-Host "$e[38;2;255;100;100mНЕДОСТУПЕН$e[0m"
            }
        }
        $primaryIp = $DnsProfiles[$name].IPv4[0]
        if ($primaryIp) {
            Write-Host -NoNewline "    $e[38;2;180;180;180m$("Resolve-DnsName".PadRight(20))$e[0m"
            $totalMs = 0; $success = 0
            foreach ($domain in $testDomains) {
                try {
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    Resolve-DnsName -Name $domain -Server $primaryIp -Type A -ErrorAction Stop | Out-Null
                    $sw.Stop()
                    $totalMs += $sw.ElapsedMilliseconds
                    $success++
                } catch { }
            }
            if ($success -gt 0) {
                $avgRes  = [math]::Round($totalMs / $success)
                $resColor = if ($avgRes -lt 100) { "50;255;150" } elseif ($avgRes -lt 300) { "255;200;0" } else { "255;100;100" }
                Write-Host "$e[38;2;${resColor}m${avgRes} ms$e[0m $e[38;2;120;120;120m(resolve avg/$($testDomains.Count) domains)$e[0m"
            } else {
                Write-Host "$e[38;2;255;100;100mНЕ РАБОТАЕТ$e[0m $e[38;2;120;120;120m(resolve)$e[0m"
            }
        }
        Write-Host ""
    }
    Write-Host "  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

# ──────────────────────────────────────────────────────────────────────────────
# Проверка и установка обновлений
# ──────────────────────────────────────────────────────────────────────────────
function Check-Update {
    Write-Host "  $e[38;2;50;255;150mПоиск обновлений...$e[0m`n"
    try {
        $remoteScript = Invoke-RestMethod -Uri $UpdateUrl -UseBasicParsing
        if ($remoteScript -match '\$AppVersion\s*=\s*"([^"]+)"') {
            $remoteVersion = $matches[1]
            if ([version]$remoteVersion -gt [version]$AppVersion) {
                Write-Host "  $e[38;2;50;255;150mНайдена новая версия: v$remoteVersion$e[0m"
                Write-Host "  $e[38;2;255;255;255mСкачивание и установка...$e[0m"
                [System.IO.File]::WriteAllText($ScriptPath, $remoteScript)
                Write-Host "  $e[38;2;50;255;150mОбновление завершено! Перезапуск...$e[0m"
                Start-Sleep -Seconds 2
                Start-Process -FilePath $ScriptPath
                Exit
            } else {
                Write-Host "  $e[38;2;255;255;255mУ вас установлена последняя версия (v$AppVersion).$e[0m"
            }
        } else {
            Write-Host "  $e[38;2;255;100;100mНе удалось определить версию на сервере.$e[0m"
        }
    } catch {
        Write-Host "  $e[38;2;255;100;100mОшибка при проверке обновлений. Проверьте соединение.$e[0m"
    }
    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

# ──────────────────────────────────────────────────────────────────────────────
# Редактирование обходного листа (файла hosts)
# ──────────────────────────────────────────────────────────────────────────────
function Edit-BypassList {
    Write-Host "  $e[38;2;50;255;150mОткрытие обходного листа (hosts)...$e[0m`n"
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    
    if (-not (Test-Path $hostsPath)) {
        try {
            # Создаем файл hosts, если его нет
            New-Item -Path $hostsPath -ItemType File -Force | Out-Null
            # Заполняем базовым содержимым
            $defaultContent = @"
# Host database lookup table for Microsoft TCP/IP for Windows.
#
# This file contains the mappings of IP addresses to host names. Each
# entry should be kept on an individual line. The IP address should
# be placed in the first column followed by the corresponding host name.
# The IP address and the host name should be separated by at least one
# space.
#
# Additionally, comments (such as these) may be inserted on individual
# lines or following the machine name denoted by a '#' symbol.
#
# For example:
#
#      102.54.94.97     rhino.acme.com          # source server
#       38.25.63.10     x.acme.com              # x client host

127.0.0.1       localhost
::1             localhost
"@
            [System.IO.File]::WriteAllText($hostsPath, $defaultContent)
            Write-Host "  $e[38;2;255;255;255mФайл hosts не найден. Создан новый шаблон.$e[0m"
        } catch {
            Write-Host "  $e[38;2;255;100;100mНе удалось создать файл hosts: $_$e[0m"
            Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
            [void][Console]::ReadLine()
            return
        }
    }
    
    Write-Host "  $e[38;2;255;255;255mЗапущен Блокнот для редактирования обходного листа.$e[0m"
    Write-Host "  $e[38;2;255;255;255mПожалуйста, отредактируйте файл, сохраните его (Ctrl+S) и закройте Блокнот.$e[0m"
    
    try {
        # Запуск блокнота и ожидание его закрытия
        $process = Start-Process notepad.exe -ArgumentList "`"$hostsPath`"" -Wait -NoNewWindow -PassThru
        
        Write-Host "`n  $e[38;2;50;255;150mФайл сохранен и закрыт. Применение настроек...$e[0m"
        Clear-DnsClientCache
        Write-Host "  $e[38;2;255;255;255mКэш DNS успешно очищен. Настройки обхода применены!$e[0m"
    } catch {
        Write-Host "  $e[38;2;255;100;100mОшибка при редактировании/применении файла: $_$e[0m"
    }
    
    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

# ──────────────────────────────────────────────────────────────────────────────
# Обновление кэшированного статуса DNS
# ──────────────────────────────────────────────────────────────────────────────
function Update-DNSStatusCache {
    $global:cachedProfileName = Get-CurrentDNSProfile
    $global:cachedLatencyStr  = ""
    $global:cachedDoHStr      = ""
    
    if ($global:cachedProfileName -ne "Авто / Провайдер" -and $global:cachedProfileName -ne "Нет активных адаптеров") {
        $lat = Get-CurrentDNSLatency -ProfileName $global:cachedProfileName
        if ($null -ne $lat) {
            $lc = if ($lat -lt 50) { "50;255;150" } elseif ($lat -lt 150) { "255;200;0" } else { "255;100;100" }
            $global:cachedLatencyStr = "  $e[38;2;90;90;90m—$e[0m  $e[38;2;${lc}m${lat} ms$e[0m"
        }
        $dohOn = Get-CurrentDoHStatus -ProfileName $global:cachedProfileName
        $global:cachedDoHStr = if ($dohOn) { "  $e[38;2;50;200;255m[DoH $([char]0x2713)]$e[0m" } else { "  $e[38;2;100;100;100m[UDP]$e[0m" }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Заголовок с отображением текущего активного DNS
# ──────────────────────────────────────────────────────────────────────────────
function Show-Header {
    $c   = "$e[38;2;50;255;150m"
    $rst = "$e[0m"
    $vStr = "      v$AppVersion"

    $logo = @(
        "╭───────────────────────────────────────────────────────────────────────────────────────╮",
        "│                                                                                       │",
        "│      ██████╗ ███╗   ██╗███████╗                                                       │",
        "│      ██╔══██╗████╗  ██║██╔════╝                                                       │",
        "│      ██║  ██║██╔██╗ ██║███████╗                                                       │",
        "│      ██║  ██║██║╚██╗██║╚════██║                                                       │",
        "│      ██████╔╝██║ ╚████║███████║                                                       │",
        "│      ╚═════╝ ╚═╝  ╚═══╝╚══════╝                                                       │",
        "│                                                                                       │",
        "│$($vStr.PadRight(87))│",
        "╰───────────────────────────────────────────────────────────────────────────────────────╯"
    )
    foreach ($line in $logo) { Write-Host "$c$line$rst" }

    Write-Host "  $e[38;2;120;120;120mАктивный DNS: $e[38;2;50;255;150m$global:cachedProfileName$rst$global:cachedLatencyStr$global:cachedDoHStr"
    Write-Host ""
}

# ──────────────────────────────────────────────────────────────────────────────
# Диспетчер действий
# ──────────────────────────────────────────────────────────────────────────────
function Invoke-MenuOption {
    param([int]$Index)
    switch ($Index) {
        0 { Apply-DNS "Xbox DNS (RU)" }
        1 { Apply-DNS "Xbox DNS (РЕЗЕРВ)" }
        2 { Apply-DNS "Comss DNS" }
        3 { Apply-DNS "Cloudflare DNS" }
        4 { Clear-AllDNS }
        5 { Test-DNSLatency }
        6 { Clear-DNSCacheOnly }
        7 { Edit-BypassList }
        8 { Check-Update }
        9 { Exit }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Данные меню
# tileWidth=20, tileGap=3 → строка меню = 2 + (20 * 4) + (3 * 3) = 91 символ
# (совпадает с шириной шапки)
# ──────────────────────────────────────────────────────────────────────────────
$options = @(
    "Xbox DNS (RU)",        # ≤ 20 ✓
    "Xbox DNS (РЕЗЕРВ)",    # ≤ 20 ✓
    "Comss DNS",            # ≤ 20 ✓
    "Cloudflare DNS",       # ≤ 20 ✓
    "СБРОСИТЬ ВСЁ (Авто)", # ≤ 20 ✓
    "Скорость DNS",         # ≤ 20 ✓
    "Очистить кэш DNS",     # ≤ 20 ✓
    "Обходной лист",        # ≤ 20 ✓
    "Проверить обновления", # ≤ 20 ✓
    "Выход"                 # ≤ 20 ✓
)

$descriptions = @(
    "Основной DNS для обхода ограничений на консолях Xbox.",
    "Резервный DNS для Xbox. Используйте при ошибках основного.",
    "Smart DNS (Control D) для доступа к ChatGPT, Claude, Gemini.",
    "Глобальный быстрый DNS от Cloudflare. Стабильность и скорость.",
    "Полный возврат к автоматическому получению DNS от провайдера.",
    "Тест задержки (ping) до всех известных DNS-серверов.",
    "Быстрая очистка локального кэша DNS без изменения настроек.",
    "Редактирование локального списка обхода DNS (файла hosts).",
    "Загрузка и установка последней версии скрипта с сервера.",
    "Закрыть программу."
)

$tileWidth = 20
$tileGap   = 3
$numCols   = 4

$selectedIndex = 0

Clear-Host
Update-DNSStatusCache
Show-Header

# ──────────────────────────────────────────────────────────────────────────────
# Главный цикл меню — сетка 3 × 4
# ──────────────────────────────────────────────────────────────────────────────
while ($true) {
    [Console]::SetCursorPosition(0, $MenuRow)
    $currentProfileName = $global:cachedProfileName

    $numRows = [math]::Ceiling($options.Count / $numCols)

    for ($r = 0; $r -lt $numRows; $r++) {
        if ($r -eq 0) {
            Write-Host "  $e[38;2;100;200;255m⚡ НАСТРОЙКА DNS-ПРОФИЛЯ$e[0m"
        } elseif ($r -eq 1) {
            Write-Host ""
            Write-Host "  $e[38;2;255;180;100m🛠️ УТИЛИТЫ И ИНСТРУМЕНТЫ$e[0m"
        }

        for ($line = 1; $line -le 3; $line++) {
            $rowStr = "  "

            for ($c = 0; $c -lt $numCols; $c++) {
                $i = $r * $numCols + $c

                if ($i -lt $options.Count) {
                    $text     = $options[$i]
                    $len      = $text.Length
                    $padLeft  = [math]::Floor(($tileWidth - $len) / 2)
                    $padRight = $tileWidth - $len - $padLeft

                    if ($i -eq $selectedIndex) {
                        $bg = "$e[48;2;50;255;150m"; $fg = "$e[38;2;0;0;0m$e[1m"
                    } elseif ($options[$i] -eq $currentProfileName) {
                        $bg = "$e[48;2;0;80;180m";   $fg = "$e[38;2;255;255;255m$e[1m"
                    } else {
                        if ($i -lt 4) {
                            $bg = "$e[48;2;25;40;50m";  $fg = "$e[38;2;150;200;255m"
                        } else {
                            $bg = "$e[48;2;40;35;30m";  $fg = "$e[38;2;220;180;140m"
                        }
                    }
                    $rst = "$e[0m"

                    if ($line -eq 1 -or $line -eq 3) {
                        $rowStr += "$bg$(" " * $tileWidth)$rst"
                    } else {
                        $rowStr += "$bg$fg$((" " * $padLeft) + $text + (" " * $padRight))$rst"
                    }
                } else {
                    # пустая ячейка (если количество пунктов не кратно numCols)
                    $rowStr += (" " * $tileWidth)
                }

                if ($c -lt $numCols - 1) { $rowStr += (" " * $tileGap) }
            }
            Write-Host $rowStr
        }
        Write-Host ""
    }

    Write-Host "  $e[38;2;120;120;120m───────────────────────────────────────────────────────────────────────────────────────$e[0m"
    Write-Host "  $e[38;2;0;255;255mИнфо:$e[0m $($descriptions[$selectedIndex].PadRight(80))"
    Write-Host "  $e[38;2;120;120;120m───────────────────────────────────────────────────────────────────────────────────────$e[0m"
    Write-Host "  $e[38;2;120;120;120m[СТРЕЛКИ] Навигация  [ENTER] Выбор  [1-9, 0] Быстрый выбор  [ESC] Выход$e[0m"

    $key = [Console]::ReadKey($true)

    if     ($key.Key -eq 'Escape')     { Exit }
    elseif ($key.Key -eq 'RightArrow') { $selectedIndex = ($selectedIndex + 1)              % $options.Count }
    elseif ($key.Key -eq 'LeftArrow')  { $selectedIndex = ($selectedIndex - 1 + $options.Count) % $options.Count }
    elseif ($key.Key -eq 'DownArrow')  { $selectedIndex = ($selectedIndex + $numCols)        % $options.Count }
    elseif ($key.Key -eq 'UpArrow')    { $selectedIndex = ($selectedIndex - $numCols + $options.Count) % $options.Count }
    elseif ($key.Key -eq 'Enter') {
        Clear-Host; Show-Header
        [Console]::SetCursorPosition(0, $MenuRow)
        Invoke-MenuOption $selectedIndex
        Update-DNSStatusCache
        Clear-Host; Show-Header
    } elseif ($key.KeyChar -ge [char]'1' -and $key.KeyChar -le [char]'9') {
        $numIdx = [int]$key.KeyChar - [int][char]'1'
        if ($numIdx -lt $options.Count) {
            $selectedIndex = $numIdx
            Clear-Host; Show-Header
            [Console]::SetCursorPosition(0, $MenuRow)
            Invoke-MenuOption $selectedIndex
            Update-DNSStatusCache
            Clear-Host; Show-Header
        }
    } elseif ($key.KeyChar -eq [char]'0') {
        $selectedIndex = 9
        Clear-Host; Show-Header
        [Console]::SetCursorPosition(0, $MenuRow)
        Invoke-MenuOption $selectedIndex
        Update-DNSStatusCache
        Clear-Host; Show-Header
    }
}