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
$AppVersion = "1.1"
$UpdateUrl = "https://raw.githubusercontent.com/D1verlin/DNS-Manager/main/dns.bat"

$e = [char]27
[Console]::CursorVisible = $false

function Set-XboxDNS {
    $IPV4 = @("111.88.96.50", "111.88.96.51")
    $IPV6 = @("2a00:ab00:1233:26::50", "2a00:ab00:1233:26::51")
    Apply-DNS -DnsList ($IPV4 + $IPV6) -DoHTemplate "https://xbox-dns.ru/dns-query" "XBOX DNS"
}

function Set-XboxReserveDNS {
    Apply-DNS -DnsList @("87.228.47.200", "87.228.47.201") -DoHTemplate "https://xbox-dns.ru/dns-query" "РЕЗЕРВ XBOX"
}

function Set-ComssDNS {
    $IPV4 = @("76.76.2.0", "76.76.10.0")
    $IPV6 = @("2606:1a40::", "2606:1a40:1::")
    Apply-DNS -DnsList ($IPV4 + $IPV6) -DoHTemplate "https://freedns.controld.com/comss" "COMSS DNS"
}

function Set-CloudflareDNS {
    $IPV4 = @("1.1.1.1", "1.0.0.1")
    $IPV6 = @("2606:4700:4700::1111", "2606:4700:4700::1001")
    Apply-DNS -DnsList ($IPV4 + $IPV6) -DoHTemplate "https://cloudflare-dns.com/dns-query" "CLOUDFLARE"
}

function Apply-DNS ($DnsList, $DoHTemplate, $Name) {
    $UpdatePanel = {
        param($percent, $status, $logLine1, $logLine2)
        [Console]::SetCursorPosition(0, 12)
        
        $barWidth = 44
        $filled = [math]::Round(($percent / 100) * $barWidth)
        $bar = ("█" * $filled) + ("░" * ($barWidth - $filled))
        
        $bg = "$e[48;2;30;30;30m"
        $rst = "$e[0m"
        $w = 66
        
        Write-Host "  $bg$(" " * $w)$rst"
        
        $l1 = "   $e[38;2;50;255;150mУСТАНОВКА ${Name}:$e[38;2;255;255;255m $status"
        $visibleL1 = "   УСТАНОВКА ${Name}: $status"
        $pad1 = $w - $visibleL1.Length
        if ($pad1 -lt 0) { $pad1 = 0 }
        Write-Host "  $bg$l1$(" " * $pad1)$rst"
        
        Write-Host "  $bg$(" " * $w)$rst"
        
        $l2 = "   $e[38;2;50;255;150m$bar$e[38;2;255;255;255m $($percent.ToString().PadLeft(3))% "
        $visibleL2 = "   $bar $($percent.ToString().PadLeft(3))% "
        $pad2 = $w - $visibleL2.Length
        if ($pad2 -lt 0) { $pad2 = 0 }
        Write-Host "  $bg$l2$(" " * $pad2)$rst"
        
        Write-Host "  $bg$(" " * $w)$rst"
        
        $visibleL3 = "   $logLine1"
        $pad3 = $w - $visibleL3.Length
        if ($pad3 -lt 0) { $pad3 = 0 }
        Write-Host "  $bg$e[38;2;180;180;180m$visibleL3$(" " * $pad3)$rst"
        
        $visibleL4 = "   $logLine2"
        $pad4 = $w - $visibleL4.Length
        if ($pad4 -lt 0) { $pad4 = 0 }
        Write-Host "  $bg$e[38;2;180;180;180m$visibleL4$(" " * $pad4)$rst"
        
        Write-Host "  $bg$(" " * $w)$rst"
    }

    &$UpdatePanel 10 "Инициализация параметров..." "" ""
    Start-Sleep -Milliseconds 250
    
    &$UpdatePanel 30 "Сканирование сетевых интерфейсов..." "" ""
    $adapters = Get-NetAdapter | Where-Object Status -eq 'Up'
    Start-Sleep -Milliseconds 250
    
    $l1 = ""
    $l2 = ""
    
    &$UpdatePanel 50 "Изменение конфигурации IP..." "" ""
    foreach ($adapter in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $DnsList -ErrorAction Stop
            $l1 = "[$($adapter.Name)] Адреса успешно назначены."
        } catch {
            $l1 = "[$($adapter.Name)] Ошибка конфигурации адресов."
        }
        &$UpdatePanel 65 "Изменение конфигурации IP..." $l1 ""
        Start-Sleep -Milliseconds 250
    }
    
    &$UpdatePanel 75 "Активация шифрования протокола DoH..." $l1 ""
    try {
        foreach ($server in $DnsList) {
            Set-DnsClientDohServerAddress -ServerAddress $server -DohTemplate $DoHTemplate -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
        }
        $l2 = "Безопасный туннель DoH запущен."
    } catch {
        $l2 = "Инфраструктура DoH недоступна в этой ОС."
    }
    &$UpdatePanel 90 "Перезагрузка кэша распознавателя..." $l1 $l2
    Start-Sleep -Milliseconds 250
    
    Clear-DnsClientCache
    &$UpdatePanel 100 "Операция успешно завершена!" $l1 $l2
    
    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

function Clear-AllDNS {
    $UpdatePanel = {
        param($percent, $status, $logLine1, $logLine2)
        [Console]::SetCursorPosition(0, 12)
        
        $barWidth = 44
        $filled = [math]::Round(($percent / 100) * $barWidth)
        $bar = ("█" * $filled) + ("░" * ($barWidth - $filled))
        
        $bg = "$e[48;2;30;30;30m"
        $rst = "$e[0m"
        $w = 66
        
        Write-Host "  $bg$(" " * $w)$rst"
        
        $l1 = "   $e[38;2;255;255;0mСБРОС НАСТРОЕК:$e[38;2;255;255;255m $status"
        $visibleL1 = "   СБРОС НАСТРОЕК: $status"
        $pad1 = $w - $visibleL1.Length
        if ($pad1 -lt 0) { $pad1 = 0 }
        Write-Host "  $bg$l1$(" " * $pad1)$rst"
        
        Write-Host "  $bg$(" " * $w)$rst"
        
        $l2 = "   $e[38;2;50;255;150m$bar$e[38;2;255;255;255m $($percent.ToString().PadLeft(3))% "
        $visibleL2 = "   $bar $($percent.ToString().PadLeft(3))% "
        $pad2 = $w - $visibleL2.Length
        if ($pad2 -lt 0) { $pad2 = 0 }
        Write-Host "  $bg$l2$(" " * $pad2)$rst"
        
        Write-Host "  $bg$(" " * $w)$rst"
        
        $visibleL3 = "   $logLine1"
        $pad3 = $w - $visibleL3.Length
        if ($pad3 -lt 0) { $pad3 = 0 }
        Write-Host "  $bg$e[38;2;180;180;180m$visibleL3$(" " * $pad3)$rst"
        
        $visibleL4 = "   $logLine2"
        $pad4 = $w - $visibleL4.Length
        if ($pad4 -lt 0) { $pad4 = 0 }
        Write-Host "  $bg$e[38;2;180;180;180m$visibleL4$(" " * $pad4)$rst"
        
        Write-Host "  $bg$(" " * $w)$rst"
    }

    &$UpdatePanel 10 "Сканирование адаптеров..." "" ""
    Start-Sleep -Milliseconds 250
    
    $adapters = Get-NetAdapter | Where-Object Status -eq 'Up'
    $l1 = ""
    $l2 = ""
    
    &$UpdatePanel 40 "Перевод режимов в положение Авто..." "" ""
    foreach ($adapter in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
            $l1 = "[$($adapter.Name)] Возвращено автоматическое получение."
        } catch {
            $l1 = "[$($adapter.Name)] Ошибка деконфигурации адресов."
        }
        &$UpdatePanel 60 "Перевод режимов в положение Авто..." $l1 ""
        Start-Sleep -Milliseconds 250
    }
    
    &$UpdatePanel 75 "Очистка таблиц шифрования DoH..." $l1 ""
    $TargetIPs = @("176.99.11.77", "80.78.247.254", "2a00:f940:2:4:2::5d1b", "2a00:f940:2:4:2::21ed", "1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001", "111.88.96.50", "111.88.96.51", "87.228.47.200", "87.228.47.201", "76.76.2.0", "76.76.10.0")
    foreach ($ip in $TargetIPs) {
        Set-DnsClientDohServerAddress -ServerAddress $ip -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction SilentlyContinue
    }
    $l2 = "Параметры безопасности DoH аннулированы."
    
    &$UpdatePanel 90 "Очистка локального кэша DNS..." $l1 $l2
    Start-Sleep -Milliseconds 250
    
    Clear-DnsClientCache
    &$UpdatePanel 100 "Сброс успешно выполнен!" $l1 $l2
    
    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

function Clear-DNSCacheOnly {
    Write-Host "  $e[38;2;50;255;150mОчистка локального кэша DNS...$e[0m`n"
    Clear-DnsClientCache
    Write-Host "  $e[38;2;255;255;255mКэш успешно очищен.$e[0m"
    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

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
        Write-Host "  $e[38;2;255;100;100mОшибка при проверке обновлений. Проверьте соединение и URL.$e[0m"
    }
    Write-Host "`n  $e[38;2;120;120;120m[ENTER] Вернуться в главное меню...$e[0m"
    [void][Console]::ReadLine()
}

function Show-Header {
    $c = "$e[38;2;50;255;150m"
    $rst = "$e[0m"
    $vStr = "      v$AppVersion"
    
    $logo = @(
        "╭──────────────────────────────────────────────────────────────────╮",
        "│                                                                  │",
        "│      ██████╗ ███╗   ██╗███████╗                                  │",
        "│      ██╔══██╗████╗  ██║██╔════╝                                  │",
        "│      ██║  ██║██╔██╗ ██║███████╗                                  │",
        "│      ██║  ██║██║╚██╗██║╚════██║                                  │",
        "│      ██████╔╝██║ ╚████║███████║                                  │",
        "│      ╚═════╝ ╚═╝  ╚═══╝╚══════╝                                  │",
        "│                                                                  │",
        "│$($vStr.PadRight(66))│",
        "╰──────────────────────────────────────────────────────────────────╯"
    )
    
    foreach ($line in $logo) {
        Write-Host "$c$line$rst"
    }
    Write-Host ""
}

$options = @(
    "Xbox DNS (RU)",
    "Xbox DNS (РЕЗЕРВ)",
    "Comss DNS (Нейросети)",
    "Cloudflare DNS (Global)",
    "СБРОСИТЬ ВСЁ (Авто/Провайдер)",
    "Очистить кэш DNS",
    "Проверить обновления",
    "Выход"
)

$descriptions = @(
    "Основной DNS для обхода ограничений на консолях Xbox.",
    "Резервный DNS для Xbox. Используйте при ошибках основного.",
    "Smart DNS (Control D) для доступа к ChatGPT, Claude, Gemini.",
    "Глобальный быстрый DNS от Cloudflare. Стабильность и скорость.",
    "Полный возврат к автоматическому получению DNS от провайдера.",
    "Быстрая очистка локального кэша DNS без изменения настроек.",
    "Загрузка и установка последней версии скрипта с сервера.",
    "Закрыть программу."
)

$selectedIndex = 0
$tileWidth = 31

Clear-Host
Show-Header

while ($true) {
    [Console]::SetCursorPosition(0, 12)
    
    for ($r = 0; $r -lt 4; $r++) {
        $idx1 = $r * 2
        $idx2 = $r * 2 + 1
        
        for ($line = 1; $line -le 3; $line++) {
            $rowStr = "  "
            
            foreach ($i in @($idx1, $idx2)) {
                $text = $options[$i]
                $len = $text.Length
                $padLeft = [math]::Floor(($tileWidth - $len) / 2)
                $padRight = $tileWidth - $len - $padLeft
                
                if ($i -eq $selectedIndex) {
                    $bg = "$e[48;2;50;255;150m"
                    $fg = "$e[38;2;0;0;0m$e[1m"
                } else {
                    $bg = "$e[48;2;35;35;35m"
                    $fg = "$e[38;2;200;200;200m"
                }
                $rst = "$e[0m"
                
                if ($line -eq 1 -or $line -eq 3) {
                    $empty = " " * $tileWidth
                    $rowStr += "$bg$empty$rst"
                } else {
                    $centeredText = (" " * $padLeft) + $text + (" " * $padRight)
                    $rowStr += "$bg$fg$centeredText$rst"
                }
                
                if ($i -eq $idx1) { $rowStr += "    " }
            }
            Write-Host $rowStr
        }
        Write-Host ""
    }
    
    Write-Host "  $e[38;2;120;120;120m──────────────────────────────────────────────────────────────────$e[0m"
    Write-Host "  $e[38;2;0;255;255mИнфо:$e[0m $($descriptions[$selectedIndex].PadRight(80))"
    Write-Host "  $e[38;2;120;120;120m──────────────────────────────────────────────────────────────────$e[0m"
    Write-Host "  $e[38;2;120;120;120m[СТРЕЛКИ] Навигация   [ENTER] Выбор                               $e[0m"
    
    $key = [Console]::ReadKey($true)
    
    if ($key.Key -eq 'RightArrow') {
        $selectedIndex = ($selectedIndex + 1) % $options.Count
    } elseif ($key.Key -eq 'LeftArrow') {
        $selectedIndex = ($selectedIndex - 1 + $options.Count) % $options.Count
    } elseif ($key.Key -eq 'DownArrow') {
        $selectedIndex = ($selectedIndex + 2) % $options.Count
    } elseif ($key.Key -eq 'UpArrow') {
        $selectedIndex = ($selectedIndex - 2 + $options.Count) % $options.Count
    } elseif ($key.Key -eq 'Enter') {
        Clear-Host
        Show-Header
        [Console]::SetCursorPosition(0, 12)
        switch ($selectedIndex) {
            0 { Set-XboxDNS }
            1 { Set-XboxReserveDNS }
            2 { Set-ComssDNS }
            3 { Set-CloudflareDNS }
            4 { Clear-AllDNS }
            5 { Clear-DNSCacheOnly }
            6 { Check-Update }
            7 { Exit }
        }
        Clear-Host
        Show-Header
    }
}