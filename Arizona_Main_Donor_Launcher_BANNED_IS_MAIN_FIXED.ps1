#requires -version 5.1
param(
    [switch]$PreparationWorker,
    [string]$PreparationConfigPath,
    [string]$PreparationProgressPath,
    [string]$PreparationResultPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LegacySettingsPath = Join-Path $ScriptDir 'Arizona_Account_Pair_Launcher.settings.json'
$SettingsDir = Join-Path $env:LOCALAPPDATA 'ArizonaMainDonorLauncher'
[IO.Directory]::CreateDirectory($SettingsDir) | Out-Null
$SettingsPath = Join-Path $SettingsDir 'settings.json'
$HelpTextPath = Join-Path $ScriptDir 'help.txt'
$HelpShownPath = Join-Path $SettingsDir 'help_v2_shown.flag'
$OnboardingCompletedPath = Join-Path $SettingsDir 'onboarding_v1_completed.flag'

$LogsDir = Join-Path $ScriptDir 'logs'
[IO.Directory]::CreateDirectory($LogsDir) | Out-Null
$DeveloperLogPath = Join-Path $LogsDir ('launcher_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
$LauncherBuild = 'prepare-launch-wpf-v2-github-layout-fix1'

# All launcher-managed download sources are intentionally configured here.
$PayloadOwner = 'NikitaQuant'
$PayloadRepo = 'ArzMarket-by-Quant'
$PayloadBranch = 'main'
$PayloadRemotePath = '' # project files are discovered from the current repository tree
$CustomArzMarketInfoUrl = 'https://raw.githubusercontent.com/NikitaQuant/ArzMarket-by-Quant/main/updateArzMarket.js'
$OriginalArzMarketInfoUrl = 'https://raw.githubusercontent.com/FREYM1337/forumnick/main/ArzMarketV3/updateArzMarket.js'

$AntiAfkOwner = 'NikitaQuant'
$AntiAfkRepo = 'ArzMarket-by-Quant'
$AntiAfkBranch = 'main'
$AntiAfkRemotePath = '#AntiAFK_' # root-level file prefix; all matching files are discovered dynamically
$AntiAfkLocalRelativePath = '' # legacy field, actual destinations are derived from file extension

$GitHubRequestTimeoutSeconds = 30
$GitHubRequestAttempts = 3
$PreparationStateFileName = 'launcher_payload_state.json'

# Arizona RP server numbering and launch hosts.
# 1-32 use the public arizona-rp.com hostnames. Server 33 Home follows
# the same hostname scheme and is kept here as home.arizona-rp.com.
$ArizonaServers = @{
    1  = [pscustomobject]@{ Name='Phoenix';      Host='phoenix.arizona-rp.com';    Port=7777 }
    2  = [pscustomobject]@{ Name='Tucson';       Host='tucson.arizona-rp.com';     Port=7777 }
    3  = [pscustomobject]@{ Name='Scottdale';    Host='scottdale.arizona-rp.com';  Port=7777 }
    4  = [pscustomobject]@{ Name='Chandler';     Host='chandler.arizona-rp.com';   Port=7777 }
    5  = [pscustomobject]@{ Name='Brainburg';    Host='brainburg.arizona-rp.com';  Port=7777 }
    6  = [pscustomobject]@{ Name='Saint-Rose';   Host='saintrose.arizona-rp.com';  Port=7777 }
    7  = [pscustomobject]@{ Name='Mesa';          Host='mesa.arizona-rp.com';       Port=7777 }
    8  = [pscustomobject]@{ Name='Red-Rock';      Host='redrock.arizona-rp.com';    Port=7777 }
    9  = [pscustomobject]@{ Name='Yuma';          Host='yuma.arizona-rp.com';       Port=7777 }
    10 = [pscustomobject]@{ Name='Surprise';      Host='surprise.arizona-rp.com';   Port=7777 }
    11 = [pscustomobject]@{ Name='Prescott';      Host='prescott.arizona-rp.com';   Port=7777 }
    12 = [pscustomobject]@{ Name='Glendale';      Host='glendale.arizona-rp.com';   Port=7777 }
    13 = [pscustomobject]@{ Name='Kingman';       Host='kingman.arizona-rp.com';    Port=7777 }
    14 = [pscustomobject]@{ Name='Winslow';       Host='winslow.arizona-rp.com';    Port=7777 }
    15 = [pscustomobject]@{ Name='Payson';        Host='payson.arizona-rp.com';     Port=7777 }
    16 = [pscustomobject]@{ Name='Gilbert';       Host='gilbert.arizona-rp.com';    Port=7777 }
    17 = [pscustomobject]@{ Name='Show Low';      Host='showlow.arizona-rp.com';    Port=7777 }
    18 = [pscustomobject]@{ Name='Casa-Grande';   Host='casagrande.arizona-rp.com'; Port=7777 }
    19 = [pscustomobject]@{ Name='Page';          Host='page.arizona-rp.com';       Port=7777 }
    20 = [pscustomobject]@{ Name='Sun-City';      Host='suncity.arizona-rp.com';    Port=7777 }
    21 = [pscustomobject]@{ Name='Queen-Creek';   Host='queencreek.arizona-rp.com'; Port=7777 }
    22 = [pscustomobject]@{ Name='Sedona';        Host='sedona.arizona-rp.com';     Port=7777 }
    23 = [pscustomobject]@{ Name='Holiday';       Host='holiday.arizona-rp.com';    Port=7777 }
    24 = [pscustomobject]@{ Name='Wednesday';     Host='wednesday.arizona-rp.com';  Port=7777 }
    25 = [pscustomobject]@{ Name='Yava';          Host='yava.arizona-rp.com';       Port=7777 }
    26 = [pscustomobject]@{ Name='Faraway';       Host='faraway.arizona-rp.com';    Port=7777 }
    27 = [pscustomobject]@{ Name='Bumble Bee';    Host='bumblebee.arizona-rp.com';  Port=7777 }
    28 = [pscustomobject]@{ Name='Christmas';     Host='christmas.arizona-rp.com';  Port=7777 }
    29 = [pscustomobject]@{ Name='Mirage';        Host='mirage.arizona-rp.com';     Port=7777 }
    30 = [pscustomobject]@{ Name='Love';          Host='love.arizona-rp.com';       Port=7777 }
    31 = [pscustomobject]@{ Name='Drake';         Host='drake.arizona-rp.com';      Port=7777 }
    32 = [pscustomobject]@{ Name='Space';         Host='space.arizona-rp.com';      Port=7777 }
    33 = [pscustomobject]@{ Name='Home';          Host='home.arizona-rp.com';       Port=7777 }
}

$DefaultArizonaArgs = '-mem 2048 -window -modern_scale -x -widescreen -trees_new -enable_grass -arizona -cdn 0,0,0'

function Write-DevLog([string]$Text) {
    try {
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        [IO.File]::AppendAllText($DeveloperLogPath, "[$stamp] $Text`r`n", [Text.UTF8Encoding]::new($false))
    } catch {}
}


$ProxyDpapiEntropyText = 'ArizonaMainDonorLauncher.Proxy.v1'
$ProxyIpCheckUrl = 'https://api.ipify.org'
$ProxyDefaultTimeout = 45
$ProxyAllowedTypes = @('http', 'https', 'socks4', 'socks4a', 'socks5', 'socks5h')

function Protect-LauncherSecret([string]$PlainText) {
    if ([string]::IsNullOrEmpty($PlainText)) { return '' }
    $plainBytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $entropy = [Text.Encoding]::UTF8.GetBytes($ProxyDpapiEntropyText)
    $protected = [Security.Cryptography.ProtectedData]::Protect(
        $plainBytes,
        $entropy,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($protected)
}

function Unprotect-LauncherSecret([string]$ProtectedText) {
    if ([string]::IsNullOrWhiteSpace($ProtectedText)) { return '' }
    try {
        $encrypted = [Convert]::FromBase64String($ProtectedText)
        $entropy = [Text.Encoding]::UTF8.GetBytes($ProxyDpapiEntropyText)
        $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted,
            $entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Text.Encoding]::UTF8.GetString($plainBytes)
    } catch {
        Write-DevLog "Proxy password decrypt failed: $($_.Exception.Message)"
        return ''
    }
}

function Get-ProxySettingsForStorage {
    if ($null -eq $proxyEnabled -or $null -eq $proxyType -or $null -eq $proxyHost -or $null -eq $proxyPort -or $null -eq $proxyUsername -or $null -eq $proxyPassword) {
        return $null
    }

    $storedType = [string]$proxyType.Text
    $storedHost = [string]$proxyHost.Text
    $storedPort = [string]$proxyPort.Text
    $storedUsername = [string]$proxyUsername.Text
    $storedPassword = [string]$proxyPassword.Password
    if ($storedHost -match '://') {
        try {
            $uriConfig = ConvertFrom-ProxyInputText $storedHost
            if ($null -ne $uriConfig) {
                $storedType = [string]$uriConfig.Type
                $storedHost = [string]$uriConfig.Host
                $storedPort = [string]$uriConfig.Port
                $storedUsername = [string]$uriConfig.Username
                $storedPassword = [string]$uriConfig.Password
            }
        } catch {
            # Never persist a partially typed proxy URL that may contain credentials.
            $storedHost = ''
            $storedPort = ''
            $storedUsername = ''
            $storedPassword = ''
        }
    }

    $protectedPassword = ''
    if (-not [string]::IsNullOrEmpty($storedPassword)) {
        try {
            $protectedPassword = Protect-LauncherSecret $storedPassword
        } catch {
            Write-DevLog "Proxy password save protection failed: $($_.Exception.Message)"
        }
    }

    return [ordered]@{
        Enabled = [bool]$proxyEnabled.IsChecked
        Type = $storedType
        Host = $storedHost
        Port = $storedPort
        Username = $storedUsername
        PasswordProtected = $protectedPassword
        Timeout = $ProxyDefaultTimeout
    }
}

function Set-UiFromProxySettings($cfg) {
    if ($null -eq $cfg) { return }

    if ($cfg.PSObject.Properties.Name -contains 'Enabled') {
        $proxyEnabled.IsChecked = [bool]$cfg.Enabled
    }

    $savedType = [string]$cfg.Type
    if ($ProxyAllowedTypes -contains $savedType.ToLowerInvariant()) {
        $proxyType.SelectedItem = $savedType.ToLowerInvariant()
    }
    if ($proxyType.SelectedIndex -lt 0) { $proxyType.SelectedItem = 'http' }

    if ($cfg.PSObject.Properties.Name -contains 'Host') { $proxyHost.Text = [string]$cfg.Host }
    if ($cfg.PSObject.Properties.Name -contains 'Port') { $proxyPort.Text = [string]$cfg.Port }
    if ($cfg.PSObject.Properties.Name -contains 'Username') { $proxyUsername.Text = [string]$cfg.Username }

    $password = ''
    if ($cfg.PSObject.Properties.Name -contains 'PasswordProtected' -and -not [string]::IsNullOrWhiteSpace([string]$cfg.PasswordProtected)) {
        $password = Unprotect-LauncherSecret ([string]$cfg.PasswordProtected)
    } elseif ($cfg.PSObject.Properties.Name -contains 'Password') {
        $password = [string]$cfg.Password
    }
    $proxyPassword.Password = $password
    Update-ProxyUiEnabled
}

function ConvertFrom-ProxyUriText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text -notmatch '://') { return $null }

    $parsedUri = $null
    if (-not [Uri]::TryCreate($Text.Trim(), [UriKind]::Absolute, [ref]$parsedUri)) {
        throw 'Некорректный URL прокси.'
    }

    $proxyScheme = $parsedUri.Scheme.ToLowerInvariant()
    if (-not ($ProxyAllowedTypes -contains $proxyScheme)) {
        throw 'URL содержит неподдерживаемый тип прокси.'
    }
    if ([string]::IsNullOrWhiteSpace($parsedUri.Host) -or $parsedUri.Port -lt 1 -or $parsedUri.Port -gt 65535) {
        throw 'URL прокси должен содержать корректные host и port.'
    }

    $proxyUser = ''
    $proxySecret = ''
    if (-not [string]::IsNullOrEmpty($parsedUri.UserInfo)) {
        $separator = $parsedUri.UserInfo.IndexOf(':')
        if ($separator -ge 0) {
            $proxyUser = [Uri]::UnescapeDataString($parsedUri.UserInfo.Substring(0, $separator))
            $proxySecret = [Uri]::UnescapeDataString($parsedUri.UserInfo.Substring($separator + 1))
        } else {
            $proxyUser = [Uri]::UnescapeDataString($parsedUri.UserInfo)
        }
    }

    return [pscustomobject]@{
        Type = $proxyScheme
        Host = $parsedUri.Host
        Port = [int]$parsedUri.Port
        Username = $proxyUser
        Password = $proxySecret
    }
}

function ConvertFrom-ProxyInputText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $value = $Text.Trim()

    # Разрешаем вставлять целиком команды вида:
    # curl --proxy "http://user:pass@host:port/" https://ipv4.webshare.io/
    # curl -x "socks5://user:pass@host:port" https://example.com/
    if ($value -match '(?is)^\s*curl(?:\.exe)?\b') {
        $proxyArg = $null
        $match = [regex]::Match(
            $value,
            '(?is)(?:^|\s)(?:--proxy|-x)(?:\s+|=)(?:"(?<dq>[^"]+)"|''(?<sq>[^'']+)''|(?<bare>[^\s]+))'
        )
        if (-not $match.Success) {
            throw 'В curl-команде не найден параметр --proxy или -x.'
        }

        if ($match.Groups['dq'].Success) {
            $proxyArg = $match.Groups['dq'].Value
        } elseif ($match.Groups['sq'].Success) {
            $proxyArg = $match.Groups['sq'].Value
        } else {
            $proxyArg = $match.Groups['bare'].Value
        }

        if ([string]::IsNullOrWhiteSpace($proxyArg)) {
            throw 'В curl-команде указан пустой proxy URL.'
        }
        return ConvertFrom-ProxyUriText $proxyArg
    }

    return ConvertFrom-ProxyUriText $value
}

function Get-ProxyUiConfig {
    $enabled = $proxyEnabled.IsChecked -eq $true
    $type = ([string]$proxyType.Text).Trim().ToLowerInvariant()
    $proxyHostValue = ([string]$proxyHost.Text).Trim()
    $portText = ([string]$proxyPort.Text).Trim()
    $username = [string]$proxyUsername.Text
    $password = [string]$proxyPassword.Password

    if (-not $enabled) {
        return [pscustomobject]@{
            Enabled = $false
            Type = $(if ($ProxyAllowedTypes -contains $type) { $type } else { 'http' })
            Host = ''
            Port = 0
            Username = ''
            Password = ''
            Timeout = $ProxyDefaultTimeout
        }
    }

    $uriConfig = ConvertFrom-ProxyInputText $proxyHostValue
    if ($null -ne $uriConfig) {
        $type = [string]$uriConfig.Type
        $proxyHostValue = [string]$uriConfig.Host
        $portText = [string]$uriConfig.Port
        $username = [string]$uriConfig.Username
        $password = [string]$uriConfig.Password

        # Normalize immediately so credentials are stored only via DPAPI settings,
        # never embedded as plaintext in the saved Host field.
        $proxyType.SelectedItem = $type
        $proxyHost.Text = $proxyHostValue
        $proxyPort.Text = $portText
        $proxyUsername.Text = $username
        $proxyPassword.Password = $password
    }

    if (-not ($ProxyAllowedTypes -contains $type)) {
        throw 'Выберите поддерживаемый тип прокси.'
    }
    if ([string]::IsNullOrWhiteSpace($proxyHostValue)) { throw 'Укажите IP или хост прокси.' }
    if ($proxyHostValue -notmatch '^[A-Za-z0-9._:\-\[\]]+$') { throw 'IP/Host прокси содержит недопустимые символы.' }

    [int]$port = 0
    if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw 'Порт прокси должен быть числом от 1 до 65535.'
    }

    if ($username -match '[\r\n\x00]' -or $password -match '[\r\n\x00]') {
        throw 'Логин или пароль прокси содержит недопустимый перевод строки.'
    }
    if ([string]::IsNullOrEmpty($username) -and -not [string]::IsNullOrEmpty($password)) {
        throw 'Указан пароль прокси, но не указан логин.'
    }
    if ($username -match ':') {
        throw 'Двоеточие в логине прокси не поддерживается.'
    }
    if ($username -ne $username.Trim() -or $password -ne $password.Trim()) {
        throw 'Пробелы в начале или конце логина/пароля прокси не поддерживаются.'
    }

    return [pscustomobject]@{
        Enabled = $true
        Type = $type
        Host = $proxyHostValue
        Port = $port
        Username = $username
        Password = $password
        Timeout = $ProxyDefaultTimeout
    }
}

function ConvertTo-CurlConfigQuoted([string]$Value) {
    if ($null -eq $Value) { return '' }
    if ($Value -match '[\r\n\x00]') { throw 'Недопустимое значение для curl config.' }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Get-ProxyUri($cfg) {
    $proxyHostValue = [string]$cfg.Host
    if ($proxyHostValue.Contains(':') -and -not ($proxyHostValue.StartsWith('[') -and $proxyHostValue.EndsWith(']'))) {
        $proxyHostValue = '[' + $proxyHostValue + ']'
    }
    return ('{0}://{1}:{2}' -f [string]$cfg.Type, $proxyHostValue, [int]$cfg.Port)
}

function Get-CurlExecutable {
    $cmd = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) {
        throw 'Не найден curl.exe. Он нужен и программе, и прокси-версии ArzMarket.'
    }
    return [string]$cmd.Source
}

function Invoke-DirectPublicIp {
    $curl = Get-CurlExecutable
    $args = @(
        '--silent', '--show-error', '--fail',
        '--connect-timeout', '8', '--max-time', '15',
        '--proto', '=https', '--proto-redir', '=https',
        '--noproxy', '*',
        $ProxyIpCheckUrl
    )
    $output = & $curl @args 2>&1
    $exitCode = $LASTEXITCODE
    $textResult = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    if ($exitCode -ne 0) { throw "Не удалось определить обычный IP: $textResult" }
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($textResult, [ref]$parsed)) {
        throw "Сервис проверки вернул некорректный обычный IP: $textResult"
    }
    return $textResult
}

function Invoke-ProxyPublicIp($cfg) {
    $curl = Get-CurlExecutable
    $tempPath = Join-Path $SettingsDir ('curl_proxy_test_{0}_{1}.cfg' -f $PID, [Guid]::NewGuid().ToString('N'))
    $proxyUri = Get-ProxyUri $cfg

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('silent')
    $lines.Add('show-error')
    $lines.Add('fail')
    $lines.Add('connect-timeout = 8')
    $lines.Add('max-time = 20')
    $lines.Add('proto = "=https"')
    $lines.Add('proto-redir = "=https"')
    $lines.Add('noproxy = ""')
    $lines.Add('proxy = "' + (ConvertTo-CurlConfigQuoted $proxyUri) + '"')
    if (-not [string]::IsNullOrEmpty([string]$cfg.Username)) {
        $proxyUser = ([string]$cfg.Username) + ':' + ([string]$cfg.Password)
        $lines.Add('proxy-user = "' + (ConvertTo-CurlConfigQuoted $proxyUser) + '"')
    }
    $lines.Add('url = "' + (ConvertTo-CurlConfigQuoted $ProxyIpCheckUrl) + '"')

    try {
        [IO.File]::WriteAllLines($tempPath, $lines, [Text.UTF8Encoding]::new($false))
        $oldNoProxyUpper = $env:NO_PROXY
        $oldNoProxyLower = $env:no_proxy
        try {
            $env:NO_PROXY = ''
            $env:no_proxy = ''
            $output = & $curl '--config' $tempPath 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $env:NO_PROXY = $oldNoProxyUpper
            $env:no_proxy = $oldNoProxyLower
        }

        $textResult = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
        if ($exitCode -ne 0) { throw "Прокси не прошел HTTPS-проверку: $textResult" }
        $parsed = $null
        if (-not [Net.IPAddress]::TryParse($textResult, [ref]$parsed)) {
            throw "Сервис проверки вернул некорректный IP прокси: $textResult"
        }
        return $textResult
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-ArzMarketProxyConnection($cfg) {
    if ($null -eq $cfg -or $cfg.Enabled -ne $true) { throw 'Сначала включите прокси для ArzMarket.' }
    $directIp = Invoke-DirectPublicIp
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $proxyIp = Invoke-ProxyPublicIp $cfg
    } finally {
        $timer.Stop()
    }
    if ([string]$directIp -eq [string]$proxyIp) {
        throw "Прокси работает, но внешний IP не изменился: $proxyIp"
    }
    return [pscustomobject]@{ DirectIp=$directIp; ProxyIp=$proxyIp; LatencyMs=[int]$timer.ElapsedMilliseconds }
}

function Test-PairProxyLua([string]$GameDir) {
    $moon = Join-Path $GameDir 'moonloader'
    try {
        foreach ($f in (Get-ChildItem -LiteralPath $moon -Filter '*.lua' -File -ErrorAction SilentlyContinue)) {
            if (Select-String -LiteralPath $f.FullName -SimpleMatch 'ARZ_PROXY_CONFIG_PATH' -Quiet -ErrorAction SilentlyContinue) { return $true }
        }
    } catch {}
    return $false
}

function Write-ArzMarketProxyConfig($cfg, $proxyCfg) {
    $configDir = Join-Path $cfg.GameDir 'moonloader\config\ArzMarket'
    [IO.Directory]::CreateDirectory($configDir) | Out-Null
    $configPath = Join-Path $configDir 'network_proxy.ini'
    $requiredFlag = Join-Path $configDir 'proxy_required.flag'
    $tempPath = $configPath + '.launcher_tmp_' + [Guid]::NewGuid().ToString('N')

    if ($proxyCfg.Enabled -eq $true) {
        $lines = @(
            '[proxy]',
            'enabled=1',
            ('type=' + [string]$proxyCfg.Type),
            ('host=' + [string]$proxyCfg.Host),
            ('port=' + [string][int]$proxyCfg.Port),
            ('username=' + [string]$proxyCfg.Username),
            ('password=' + [string]$proxyCfg.Password),
            ('timeout=' + [string][int]$proxyCfg.Timeout),
            ''
        )
    } else {
        $lines = @(
            '[proxy]',
            'enabled=0',
            'type=http',
            'host=',
            'port=0',
            'username=',
            'password=',
            ('timeout=' + [string]$ProxyDefaultTimeout),
            ''
        )
    }

    try {
        [IO.File]::WriteAllText($tempPath, ($lines -join "`r`n"), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tempPath -Destination $configPath -Force
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    if ($proxyCfg.Enabled -eq $true) {
        [IO.File]::WriteAllText($requiredFlag, '1', [Text.UTF8Encoding]::new($false))
        if (-not (Test-Path -LiteralPath $requiredFlag -PathType Leaf)) {
            throw "Не удалось включить fail-closed маркер прокси: $requiredFlag"
        }
    } else {
        Remove-Item -LiteralPath $requiredFlag -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $requiredFlag) {
            throw "Не удалось отключить fail-closed маркер прокси: $requiredFlag"
        }
    }

    Write-DevLog "ArzMarket proxy config written. enabled=$($proxyCfg.Enabled) type=$($proxyCfg.Type) host=$($proxyCfg.Host) port=$($proxyCfg.Port) root=$($cfg.GameDir)"
}

function Get-ServerInfo([int]$Number) {
    if (-not $ArizonaServers.ContainsKey($Number)) {
        throw "Номер сервера должен быть от 1 до 33."
    }
    return $ArizonaServers[$Number]
}

function Get-ServerNumberFromHost([string]$HostName) {
    if ([string]::IsNullOrWhiteSpace($HostName)) { return 0 }
    foreach ($key in $ArizonaServers.Keys) {
        if ([string]$ArizonaServers[$key].Host -ieq [string]$HostName) { return [int]$key }
    }
    return 0
}

function Get-RussianState([string]$State) {
    switch ([string]$State) {
        'ONLINE'          { return 'в сети' }
        'STARTING'        { return 'запускается' }
        'DISCONNECTED'    { return 'отключен' }
        'NOT_LOGGED_IN'   { return 'не авторизован' }
        'WRONG_ACCOUNT'   { return 'неверный аккаунт' }
        'WRONG_SERVER'    { return 'неверный сервер' }
        'NO_STATE'        { return 'нет данных' }
        'UNKNOWN'         { return 'неизвестно' }
        default           { if ([string]::IsNullOrWhiteSpace($State)) { return 'нет данных' }; return $State.ToLowerInvariant() }
    }
}

function Get-RussianPhase([string]$Phase) {
    switch ([string]$Phase) {
        'IDLE'       { return 'не запущена' }
        'WAIT_DONOR' { return 'ожидание донора' }
        'RUNNING'    { return 'работает' }
        'TIMEOUT'    { return 'время ожидания вышло' }
        'STOPPED'    { return 'остановлена' }
        default      { return $Phase }
    }
}

$WatchdogTemplate = @'
@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

title Arizona Account Watchdog - __NICK__

rem This BAT controls only the second Arizona installation.
rem The launch command uses the same full Arizona arguments that already worked.
rem It never uses taskkill /IM gta_sa.exe and therefore does not kill the other SA-MP window.
set "MAIN_DIR=__MAIN_DIR__"
set "ROOT=__ROOT__"
set "GTA_EXE=%ROOT%\gta_sa.exe"
set "USER_ID=__USER_ID__"
set "EXTRA_ARGS=__EXTRA_ARGS__"
set "WATCHDOG_DIR=%ROOT%\moonloader\ArzMarket\watchdog"
set "CONFIG_FILE=%WATCHDOG_DIR%\watchdog_config.ini"
set "STATE_FILE=%WATCHDOG_DIR%\state.ini"
set "BAT_HEARTBEAT=%WATCHDOG_DIR%\bat_heartbeat.ini"
set "LOG_FILE=__DEV_LOG_FILE__"
set "STOP_FILE=%WATCHDOG_DIR%\stop.flag"

set "CHECK_INTERVAL=3"
set "STALE_SECONDS=12"
set "RESTART_COOLDOWN=5"

rem Fallbacks are used only before Lua creates watchdog_config.ini.
set "CFG_ENABLED=1"
set "CFG_NICK=__NICK__"
set "LAUNCH_SERVER=__SERVER__"
set "CFG_SERVER="
set "CFG_PORT=__PORT__"
set "CFG_DISCONNECT_TIMEOUT=15"
set "CFG_STARTUP_GRACE=90"
set "CFG_UNSPAWNED_TIMEOUT=30"

set "OWNED_PID="
set "LAUNCH_EPOCH=0"
set "LAST_PRINTED_STATE="

if not exist "%ROOT%" (
    echo [ERROR] GTA folder not found: %ROOT%
    pause
    exit /b 1
)
if not exist "%GTA_EXE%" (
    echo [ERROR] gta_sa.exe not found: %GTA_EXE%
    pause
    exit /b 1
)
if not exist "%WATCHDOG_DIR%" mkdir "%WATCHDOG_DIR%" >nul 2>&1

call :PrepareArizona
if errorlevel 1 (
    pause
    exit /b 1
)

call :EnsureConfig
call :Log "BAT watchdog started"

goto :MainLoop

:MainLoop
if exist "%STOP_FILE%" (
    del /q "%STOP_FILE%" >nul 2>&1
    call :Log "Watchdog stopped by GUI"
    exit /b 0
)
call :LoadConfig
call :WriteBatHeartbeat
call :ReadState

if defined STATE_PID call :TryAdoptStatePid

if not "%CFG_ENABLED%"=="1" (
    if /I not "!LAST_PRINTED_STATE!"=="DISABLED" (
        echo [WATCHDOG] Disabled in Authorization.
        set "LAST_PRINTED_STATE=DISABLED"
    )
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)

if not defined OWNED_PID (
    call :LaunchAccount "no_owned_process"
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)

call :IsOwnedProcessAlive
if not "!PROCESS_ALIVE!"=="1" (
    call :RestartAccount "process_gone"
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)

if not exist "%STATE_FILE%" (
    call :GetNowEpoch
    set /a START_AGE=!NOW_EPOCH!-!LAUNCH_EPOCH! 2>nul
    if !LAUNCH_EPOCH! GTR 0 if !START_AGE! GEQ %CFG_STARTUP_GRACE% (
        call :RestartAccount "lua_state_missing_after_startup_grace"
    )
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)

call :GetStateAge
if !STATE_AGE! GTR %STALE_SECONDS% (
    call :RestartAccount "lua_heartbeat_stale"
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)

if /I "!STATE!"=="DISCONNECTED" (
    call :RestartAccount "lua_disconnected"
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)
if /I "!STATE!"=="NOT_LOGGED_IN" (
    call :RestartAccount "lua_not_logged_in"
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)
if /I "!STATE!"=="WRONG_ACCOUNT" (
    call :RestartAccount "lua_wrong_account"
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)
if /I "!STATE!"=="WRONG_SERVER" (
    if /I "!STATE_REASON!"=="server_mismatch" if defined STATE_SERVER (
        call :PinObservedServer
        timeout /t %CHECK_INTERVAL% /nobreak >nul
        goto :MainLoop
    )
    call :RestartAccount "lua_wrong_server"
    timeout /t %CHECK_INTERVAL% /nobreak >nul
    goto :MainLoop
)

if /I "!STATE!"=="ONLINE" (
    if "!CFG_SERVER!"=="" if defined STATE_SERVER call :PinObservedServer
    if /I not "!LAST_PRINTED_STATE!"=="ONLINE" (
        echo [ONLINE] !STATE_NICK! at !STATE_SERVER!:!STATE_PORT! PID=!OWNED_PID!
        call :Log "ONLINE nick=!STATE_NICK! server=!STATE_SERVER!:!STATE_PORT! pid=!OWNED_PID!"
        set "LAST_PRINTED_STATE=ONLINE"
    )
) else (
    if /I not "!LAST_PRINTED_STATE!"=="!STATE!" (
        echo [STATE] !STATE! reason=!STATE_REASON! gamestate=!STATE_GAMESTATE! spawned=!STATE_SPAWNED!
        set "LAST_PRINTED_STATE=!STATE!"
    )
)

timeout /t %CHECK_INTERVAL% /nobreak >nul
goto :MainLoop

:PrepareArizona
echo [1/3] Preparing Arizona launch environment...

if not exist "%ROOT%\MoonLoader.asi" (
    if exist "%ROOT%\MoonLoader.asi.disabled" ren "%ROOT%\MoonLoader.asi.disabled" "MoonLoader.asi"
)

if not exist "%ROOT%\MoonLoader.asi" (
    echo [ERROR] MoonLoader.asi not found in %ROOT%
    exit /b 1
)

echo [2/3] Multiprocess and MoonLoader are ready.
exit /b 0

:EnsureConfig
if exist "%CONFIG_FILE%" exit /b 0
> "%CONFIG_FILE%" (
    echo enabled=1
    echo nick=__NICK__
    echo server=
    echo port=__PORT__
    echo disconnect_timeout=15
    echo startup_grace=90
    echo unspawned_timeout=30
)
exit /b 0

:LoadConfig
set "CFG_ENABLED=1"
set "CFG_NICK=__NICK__"
set "CFG_SERVER="
set "CFG_PORT=__PORT__"
set "CFG_DISCONNECT_TIMEOUT=15"
set "CFG_STARTUP_GRACE=90"
set "CFG_UNSPAWNED_TIMEOUT=30"
if not exist "%CONFIG_FILE%" exit /b 0
for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
    if /I "%%A"=="enabled" set "CFG_ENABLED=%%B"
    if /I "%%A"=="nick" set "CFG_NICK=%%B"
    if /I "%%A"=="server" set "CFG_SERVER=%%B"
    if /I "%%A"=="port" set "CFG_PORT=%%B"
    if /I "%%A"=="disconnect_timeout" set "CFG_DISCONNECT_TIMEOUT=%%B"
    if /I "%%A"=="startup_grace" set "CFG_STARTUP_GRACE=%%B"
    if /I "%%A"=="unspawned_timeout" set "CFG_UNSPAWNED_TIMEOUT=%%B"
)
exit /b 0

:ReadState
set "STATE="
set "STATE_REASON="
set "STATE_PID="
set "STATE_NICK="
set "STATE_SERVER="
set "STATE_PORT="
set "STATE_GAMESTATE="
set "STATE_SPAWNED="
set "STATE_ENABLED="
if not exist "%STATE_FILE%" exit /b 0
for /f "usebackq tokens=1,* delims==" %%A in ("%STATE_FILE%") do (
    if /I "%%A"=="state" set "STATE=%%B"
    if /I "%%A"=="reason" set "STATE_REASON=%%B"
    if /I "%%A"=="pid" set "STATE_PID=%%B"
    if /I "%%A"=="nick" set "STATE_NICK=%%B"
    if /I "%%A"=="server" set "STATE_SERVER=%%B"
    if /I "%%A"=="port" set "STATE_PORT=%%B"
    if /I "%%A"=="gamestate" set "STATE_GAMESTATE=%%B"
    if /I "%%A"=="spawned" set "STATE_SPAWNED=%%B"
    if /I "%%A"=="enabled" set "STATE_ENABLED=%%B"
)
exit /b 0

:TryAdoptStatePid
if "%STATE_PID%"=="" exit /b 0
set "CHECK_PID=%STATE_PID%"
call :IsPidOurGta
if "!PID_IS_OURS!"=="1" (
    if not "!OWNED_PID!"=="!STATE_PID!" (
        set "OWNED_PID=!STATE_PID!"
        call :Log "Adopted Lua PID=!OWNED_PID!"
    )
)
exit /b 0

:IsOwnedProcessAlive
set "PROCESS_ALIVE=0"
if not defined OWNED_PID exit /b 0
set "CHECK_PID=%OWNED_PID%"
call :IsPidOurGta
if "!PID_IS_OURS!"=="1" set "PROCESS_ALIVE=1"
exit /b 0

:IsPidOurGta
set "PID_IS_OURS=0"
if "%CHECK_PID%"=="" exit /b 0
set "CHECK_GTA_EXE=%GTA_EXE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $p=Get-Process -Id ([int]$env:CHECK_PID); if($p.Path -and ([IO.Path]::GetFullPath($p.Path) -ieq [IO.Path]::GetFullPath($env:CHECK_GTA_EXE))){exit 0} } catch {}; exit 1" >nul 2>&1
if not errorlevel 1 set "PID_IS_OURS=1"
exit /b 0

:LaunchAccount
call :LoadConfig
if not "%CFG_ENABLED%"=="1" exit /b 0
if exist "%STATE_FILE%" del /q "%STATE_FILE%" >nul 2>&1
call :GetNowEpoch
set "LAUNCH_EPOCH=!NOW_EPOCH!"
set "LAST_PRINTED_STATE=STARTING"
set "OWNED_PID="

echo [3/3] Starting %CFG_NICK% with the proven Arizona launch arguments...
echo [START] %CFG_NICK% at %LAUNCH_SERVER%:%CFG_PORT%
call :Log "Launching account reason=%~1 nick=%CFG_NICK% launchServer=%LAUNCH_SERVER%:%CFG_PORT% expectedServer=%CFG_SERVER%"

for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$uid=''; if(-not [string]::IsNullOrWhiteSpace($env:USER_ID)){ $uid=' -userId ' + $env:USER_ID }; $a='-c -h ' + $env:LAUNCH_SERVER + ' -p ' + $env:CFG_PORT + ' -n ' + $env:CFG_NICK + $uid + ' ' + $env:EXTRA_ARGS; $p=Start-Process -FilePath $env:GTA_EXE -WorkingDirectory $env:ROOT -ArgumentList $a -PassThru; $p.Id"`) do set "OWNED_PID=%%P"

if not defined OWNED_PID (
    echo [ERROR] Failed to start gta_sa.exe.
    call :Log "Launch failed"
    timeout /t %RESTART_COOLDOWN% /nobreak >nul
    exit /b 1
)

call :Log "Started gta_sa.exe PID=!OWNED_PID!"
exit /b 0

:PinObservedServer
if not defined STATE_SERVER exit /b 1
set "PIN_SERVER=!STATE_SERVER!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:CONFIG_FILE; $ip=$env:PIN_SERVER; if([string]::IsNullOrWhiteSpace($ip)){exit 1}; $c=Get-Content -LiteralPath $p -Raw -Encoding UTF8 -ErrorAction Stop; if($c -match '(?im)^server='){ $c=[regex]::Replace($c,'(?im)^server=.*$','server=' + $ip,1) } else { $c += [Environment]::NewLine + 'server=' + $ip + [Environment]::NewLine }; [IO.File]::WriteAllText($p,$c,[Text.UTF8Encoding]::new($false))" >nul 2>&1
if errorlevel 1 (
    call :Log "Failed to pin observed server address !STATE_SERVER!"
    exit /b 1
)
set "CFG_SERVER=!STATE_SERVER!"
echo [WATCHDOG] Server address confirmed: !STATE_SERVER!:!STATE_PORT!
call :Log "Pinned observed server address !STATE_SERVER!:!STATE_PORT! for launch host %LAUNCH_SERVER%"
exit /b 0

:RestartAccount
set "RESTART_REASON=%~1"
echo [RESTART] !RESTART_REASON!
call :Log "Restart requested reason=!RESTART_REASON! state=!STATE! stateReason=!STATE_REASON! pid=!OWNED_PID!"

if defined OWNED_PID (
    set "CHECK_PID=!OWNED_PID!"
    call :IsPidOurGta
    if "!PID_IS_OURS!"=="1" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Stop-Process -Id ([int]$env:CHECK_PID) -Force -ErrorAction SilentlyContinue" >nul 2>&1
        call :Log "Killed owned gta_sa.exe PID=!OWNED_PID!"
    )
)

set "OWNED_PID="
if exist "%STATE_FILE%" del /q "%STATE_FILE%" >nul 2>&1
timeout /t %RESTART_COOLDOWN% /nobreak >nul
call :LaunchAccount "!RESTART_REASON!"
exit /b 0

:GetStateAge
set "STATE_AGE=999999"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:STATE_FILE; if(Test-Path -LiteralPath $p){[int][math]::Floor(((Get-Date)-(Get-Item -LiteralPath $p).LastWriteTime).TotalSeconds)}else{999999}"`) do set "STATE_AGE=%%A"
exit /b 0

:GetNowEpoch
set "NOW_EPOCH=0"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()"`) do set "NOW_EPOCH=%%A"
exit /b 0

:WriteBatHeartbeat
if not exist "%WATCHDOG_DIR%" mkdir "%WATCHDOG_DIR%" >nul 2>&1
> "%BAT_HEARTBEAT%.tmp" (
    echo status=RUNNING
    echo owned_pid=!OWNED_PID!
    echo expected_nick=!CFG_NICK!
    echo expected_server=!CFG_SERVER!
    echo expected_port=!CFG_PORT!
    echo updated=%date% %time%
)
move /y "%BAT_HEARTBEAT%.tmp" "%BAT_HEARTBEAT%" >nul 2>&1
exit /b 0

:Log
>> "%LOG_FILE%" echo [%date% %time%] %~1
exit /b 0
'@

$CfgAccountFields = @(
    'myServerToken','myServerId','premiumTokenAuth','lastUpdatePremiumToken',
    'realMoneyNow','myBalanceArz','authNickname','authUid',
    'authPremiumTokenAuth','authUserTempKey','authRealNameMode1','authRealNameMode2',
    'authSelfInfoId','authSelfInfoUsername','authSelfInfoExp','authSelfInfoOsTime','marketAuthKey'
)
$AnySectionAuthFields = @(
    'marketAuthKey','marketAuthToken','premiumToken','premiumAuthToken',
    'userToken','userAuthToken','serverToken','authKey'
)

$BridgeProtocol = 3
$PairRuntime = [pscustomobject]@{
    Session = ''
    ProfileKey = ''
    Active = $false
    Phase = 'IDLE'
    Main = $null
    Donor = $null
    Deadline = [datetime]::MinValue
    CandidateToken = ''
    CandidateSince = [datetime]::MinValue
    LastSignature = ''
}

function Add-LauncherLog([string]$Text) {
    $stamp = Get-Date -Format 'HH:mm:ss'
    $statusBox.AppendText("[$stamp] $Text`r`n")
    $statusBox.ScrollToEnd()
    Write-DevLog "USER: $Text"
}

function Write-Status([string]$Text) { Add-LauncherLog $Text }

function Safe-Field([string]$Value, [string]$Name, [bool]$AllowEmpty=$false) {
    $v = [string]$Value
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($v)) { throw "$Name не заполнено." }
    if ($v -match '[\r\n\"!%]') { throw "$Name содержит недопустимые символы: кавычки, !, % или перевод строки." }
    return $v.Trim()
}

function Get-AccountConfig($ui, [string]$Title) {
    $game = Safe-Field $ui.GameDir.Text "$Title - папка Arizona"
    $nick = Safe-Field $ui.Nick.Text "$Title - ник"
    $serverNumberText = Safe-Field $ui.ServerNumber.Text "$Title - номер сервера"
    $userId = [string]$ui.UserIdValue
    if ($null -eq $userId) { $userId = '' }
    $userId = $userId.Trim()

    if ($nick -notmatch '^[A-Za-z0-9_]{3,24}$') { throw "$Title - ник должен содержать только латинские буквы, цифры и _." }

    [int]$serverNumber = 0
    if (-not [int]::TryParse($serverNumberText, [ref]$serverNumber)) {
        throw "$Title - укажите номер сервера от 1 до 33."
    }
    $serverInfo = Get-ServerInfo $serverNumber

    if (-not [string]::IsNullOrWhiteSpace($userId) -and $userId -notmatch '^[A-Fa-f0-9]{16,128}$') {
        Write-DevLog "$Title - сохраненный legacy userId имеет неверный формат и будет пропущен."
        $userId = ''
    }

    if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw "$Title - папка Arizona не существует: $game" }
    $gta = Join-Path $game 'gta_sa.exe'
    if (-not (Test-Path -LiteralPath $gta -PathType Leaf)) { throw "$Title - не найден gta_sa.exe: $gta" }
    $moon = Join-Path $game 'moonloader'
    if (-not (Test-Path -LiteralPath $moon -PathType Container)) { throw "$Title - не найдена папка moonloader: $moon" }
    $ini = Join-Path $game 'moonloader\config\ArzMarket\ArzMarket.ini'
    # ArzMarket.ini may legitimately be absent before the first prepared launch.

    return [pscustomobject]@{
        GameDir = $game
        MainDir = ''
        Nick = $nick
        ServerNumber = $serverNumber
        ServerName = [string]$serverInfo.Name
        Server = [string]$serverInfo.Host
        Port = [int]$serverInfo.Port
        UserId = $userId
        ExtraArgs = $DefaultArizonaArgs
        SaveToken = $true
    }
}

function Validate-Pair {
    if ($mainA.IsChecked -eq $mainB.IsChecked) { throw 'Отметьте "Аккаунт забанен" ровно у одного аккаунта.' }

    $a = Get-AccountConfig $uiA 'Левый аккаунт'
    $b = Get-AccountConfig $uiB 'Правый аккаунт'
    $pathA = [IO.Path]::GetFullPath($a.GameDir).TrimEnd('\')
    $pathB = [IO.Path]::GetFullPath($b.GameDir).TrimEnd('\')
    if ($pathA -ieq $pathB) {
        throw 'Нельзя указать одну и ту же папку Arizona для двух аккаунтов. Сделайте копию папки игры и укажите для второго аккаунта другой путь.'
    }

    $a.MainDir = $b.GameDir
    $b.MainDir = $a.GameDir

    # Отмеченный как забаненный аккаунт является MAIN. Токен берется со второго, донорского аккаунта.
    if ($mainA.IsChecked) {
        return [pscustomobject]@{ Main=$a; Donor=$b; MainIndex='A'; TokenSourceIndex='B'; A=$a; B=$b }
    }
    return [pscustomobject]@{ Main=$b; Donor=$a; MainIndex='B'; TokenSourceIndex='A'; A=$a; B=$b }
}

function Save-Settings($pair) {
    $obj = [ordered]@{
        Version = 5
        BannedMainIndex = $pair.MainIndex
        MainIndex = $pair.MainIndex
        TokenSourceIndex = $pair.TokenSourceIndex
        AccountA = $pair.A
        AccountB = $pair.B
        Proxy = Get-ProxySettingsForStorage
    }
    $json = $obj | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($SettingsPath, $json, [Text.UTF8Encoding]::new($false))
}

function Enable-Multiprocess([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return }
    $p = Join-Path $Dir 'SAMPFUNCS\sampfuncs-settings.ini'
    if (-not (Test-Path -LiteralPath $p)) {
        Write-DevLog "SAMPFUNCS config not found: $p"
        return
    }
    try {
        $doc = Get-TextDocument $p
        $c = [string]$doc.Text
        if ($c -match '(?im)^multiprocess\s*=') {
            $c = $c -replace '(?im)^multiprocess\s*=\s*(true|false)\s*$', 'multiprocess=true'
        } elseif ($c -match '(?im)^\[general\]\s*$') {
            $c = $c -replace '(?im)^\[general\]\s*$', "[general]`r`nmultiprocess=true"
        } else {
            $c += "`r`nmultiprocess=true`r`n"
        }
        Write-TextDocument $doc $p $c
        Write-DevLog "multiprocess=true: $p"
    } catch {
        Write-DevLog "multiprocess update failed: $($_.Exception.ToString())"
    }
}

function Enable-MoonLoader([string]$GameDir) {
    $asi = Join-Path $GameDir 'MoonLoader.asi'
    $disabled = Join-Path $GameDir 'MoonLoader.asi.disabled'
    if (-not (Test-Path -LiteralPath $asi) -and (Test-Path -LiteralPath $disabled)) {
        Rename-Item -LiteralPath $disabled -NewName 'MoonLoader.asi'
    }
    if (-not (Test-Path -LiteralPath $asi)) { throw "MoonLoader.asi не найден в $GameDir" }
}

function Test-PairBridgeLua([string]$GameDir) {
    $moon = Join-Path $GameDir 'moonloader'
    try {
        foreach ($f in (Get-ChildItem -LiteralPath $moon -Filter '*.lua' -File -ErrorAction SilentlyContinue)) {
            if (Select-String -LiteralPath $f.FullName -SimpleMatch 'ARZ_ACCOUNT_BRIDGE_CONFIG_PATH' -Quiet -ErrorAction SilentlyContinue) { return $true }
        }
    } catch {}
    return $false
}

function Assert-GameNotRunning($cfg, [string]$Role) {
    $target = [IO.Path]::GetFullPath((Join-Path $cfg.GameDir 'gta_sa.exe'))
    foreach ($p in (Get-Process -Name 'gta_sa' -ErrorAction SilentlyContinue)) {
        try {
            if ($p.Path -and ([IO.Path]::GetFullPath($p.Path) -ieq $target)) {
                throw "$Role уже запущен из $($cfg.GameDir). Для чистого запуска связки сначала закройте это окно GTA."
            }
        } catch [System.Management.Automation.RuntimeException] { throw }
        catch {}
    }
}

function Get-AccountGameProcesses($cfg) {
    $result = @()
    if ($null -eq $cfg -or [string]::IsNullOrWhiteSpace([string]$cfg.GameDir)) { return $result }
    try {
        $target = [IO.Path]::GetFullPath((Join-Path $cfg.GameDir 'gta_sa.exe'))
    } catch {
        return $result
    }
    foreach ($p in (Get-Process -Name 'gta_sa' -ErrorAction SilentlyContinue)) {
        try {
            if ($p.Path -and ([IO.Path]::GetFullPath($p.Path) -ieq $target)) {
                $result += $p
            }
        } catch {}
    }
    return $result
}

function Get-AccountWatchdogProcessIds($cfg) {
    $found = @{}
    if ($null -eq $cfg -or [string]::IsNullOrWhiteSpace([string]$cfg.GameDir)) { return @() }
    try {
        $batPath = [IO.Path]::GetFullPath((Join-Path $cfg.GameDir 'Arizona_Account_Watchdog_GENERATED.bat'))
    } catch {
        return @()
    }

    try {
        foreach ($proc in (Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue)) {
            $cmd = [string]$proc.CommandLine
            if (-not [string]::IsNullOrWhiteSpace($cmd) -and $cmd.IndexOf($batPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $found[[int]$proc.ProcessId] = $true
            }
        }
    } catch {
        Write-DevLog "Watchdog CIM lookup failed for $batPath : $($_.Exception.Message)"
    }

    # Fallback for old watchdog windows: the generated BAT always sets this exact title.
    $expectedTitle = 'Arizona Account Watchdog - ' + [string]$cfg.Nick
    foreach ($proc in (Get-Process -Name 'cmd' -ErrorAction SilentlyContinue)) {
        try {
            if ([string]$proc.MainWindowTitle -ieq $expectedTitle) {
                $found[[int]$proc.Id] = $true
            }
        } catch {}
    }
    return @($found.Keys)
}

function Stop-AccountWatchdogProcess($cfg) {
    $stopped = 0
    foreach ($pidValue in @(Get-AccountWatchdogProcessIds $cfg)) {
        try {
            Stop-Process -Id $pidValue -Force -ErrorAction Stop
            $stopped++
            Write-DevLog "Stopped old watchdog cmd PID=$pidValue root=$($cfg.GameDir)"
        } catch {
            Write-DevLog "Failed to stop watchdog PID=$pidValue root=$($cfg.GameDir): $($_.Exception.Message)"
        }
    }
    return $stopped
}

function Stop-AccountGameProcesses($cfg, [string]$RoleLabel) {
    $stopped = 0
    foreach ($p in @(Get-AccountGameProcesses $cfg)) {
        try {
            $pidValue = [int]$p.Id
            Stop-Process -Id $pidValue -Force -ErrorAction Stop
            $stopped++
            Write-DevLog "Stopped old GTA role=$RoleLabel PID=$pidValue root=$($cfg.GameDir)"
        } catch {
            Write-DevLog "Failed to stop GTA role=$RoleLabel root=$($cfg.GameDir): $($_.Exception.Message)"
        }
    }

    if ($stopped -gt 0) {
        for ($i = 0; $i -lt 30; $i++) {
            if (@(Get-AccountGameProcesses $cfg).Count -eq 0) { break }
            Start-Sleep -Milliseconds 100
        }
    }
    return $stopped
}

function Clear-AccountWatchdogTransientFiles($cfg) {
    if ($null -eq $cfg) { return }
    $wdDir = Join-Path $cfg.GameDir 'moonloader\ArzMarket\watchdog'
    foreach ($name in @('state.ini', 'bat_heartbeat.ini')) {
        $path = Join-Path $wdDir $name
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Stop-ExistingPairBeforeRestart($pair) {
    $wasActive = $PairRuntime.Active
    $PairRuntime.Active = $false
    $PairRuntime.Phase = 'STOPPED'
    $mainGames = @(Get-AccountGameProcesses $pair.Main)
    $donorGames = @(Get-AccountGameProcesses $pair.Donor)
    $mainWatchdogs = @(Get-AccountWatchdogProcessIds $pair.Main)
    $donorWatchdogs = @(Get-AccountWatchdogProcessIds $pair.Donor)
    $hadOldRuntime = ($mainGames.Count + $donorGames.Count + $mainWatchdogs.Count + $donorWatchdogs.Count) -gt 0

    if ($hadOldRuntime -or $wasActive) {
        Write-Status 'Закрываю прошлый запуск...'
    }

    # First tell both watchdogs to stop, otherwise they could relaunch GTA while it is being closed.
    Stop-WatchdogAccount $pair.Main
    Stop-WatchdogAccount $pair.Donor
    Start-Sleep -Milliseconds 3500

    # Close any watchdog CMD window that did not exit after seeing stop.flag. generated for the two selected Arizona folders.
    $null = Stop-AccountWatchdogProcess $pair.Main
    $null = Stop-AccountWatchdogProcess $pair.Donor

    # Close only gta_sa.exe instances whose executable path matches the selected account folder.
    $mainStopped = Stop-AccountGameProcesses $pair.Main 'Основной'
    $donorStopped = Stop-AccountGameProcesses $pair.Donor 'Донор'

    Clear-AccountWatchdogTransientFiles $pair.Main
    Clear-AccountWatchdogTransientFiles $pair.Donor
    Remove-LauncherHeartbeat $pair.Main
    Remove-LauncherHeartbeat $pair.Donor

    if ($hadOldRuntime -or $wasActive -or $mainStopped -gt 0 -or $donorStopped -gt 0) {
        Write-Status 'Прошлый запуск закрыт.'
    }
}

function Ensure-ArzConfigDir($cfg) {
    $dir = Join-Path $cfg.GameDir 'moonloader\config\ArzMarket'
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    return $dir
}

function Write-LauncherHeartbeat($cfg, [bool]$Active) {
    if ($null -eq $cfg -or [string]::IsNullOrWhiteSpace([string]$cfg.GameDir)) { return }
    try {
        $dir = Ensure-ArzConfigDir $cfg
        $path = Join-Path $dir 'launcher_heartbeat.ini'
        $stamp = [int64][Math]::Floor(([DateTime]::UtcNow - [DateTime]'1970-01-01T00:00:00Z').TotalSeconds)
        $text = @(
            "protocol=$BridgeProtocol",
            ('active=' + $(if ($Active) { '1' } else { '0' })),
            "timestamp=$stamp",
            "pid=$PID",
            "session=$($PairRuntime.Session)"
        ) -join "`r`n"
        [IO.File]::WriteAllText($path, $text + "`r`n", [Text.UTF8Encoding]::new($false))
    } catch {
        Write-DevLog "Launcher heartbeat write error for $($cfg.GameDir): $($_.Exception.Message)"
    }
}

function Remove-LauncherHeartbeat($cfg) {
    if ($null -eq $cfg -or [string]::IsNullOrWhiteSpace([string]$cfg.GameDir)) { return }
    try {
        $path = Join-Path $cfg.GameDir 'moonloader\config\ArzMarket\launcher_heartbeat.ini'
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Set-RoleFiles($cfg, [string]$Role, [bool]$LockMain=$false) {
    $dir = Ensure-ArzConfigDir $cfg
    $bridge = Join-Path $dir 'account_bridge.ini'
    $roleText = $Role.ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($PairRuntime.Session)) { throw 'Нет активной session связки.' }
    $bridgeText = "protocol=$BridgeProtocol`r`nrole=$roleText`r`npaired=1`r`nsession=$($PairRuntime.Session)`r`n"
    [IO.File]::WriteAllText($bridge, $bridgeText, [Text.UTF8Encoding]::new($false))
    Write-BridgeStandaloneState $cfg $roleText
    [IO.File]::WriteAllText((Join-Path $dir 'account_role.flag'), $roleText, [Text.UTF8Encoding]::new($false))

    $lock = Join-Path $dir 'ini_write_locked.flag'

    if ($roleText -eq 'DONOR') {
        if (Test-Path -LiteralPath $lock) { Remove-Item -LiteralPath $lock -Force -ErrorAction Stop }
        Write-DevLog "DONOR role applied. Offline is controlled by Lua only while launcher heartbeat is active. nick=$($cfg.Nick) root=$($cfg.GameDir)"
    } else {
        if ($LockMain) {
            [IO.File]::WriteAllText($lock, '1', [Text.UTF8Encoding]::new($false))
        }
        Write-DevLog "MAIN role applied. Online is controlled by Lua while launcher heartbeat is active. lock=$LockMain nick=$($cfg.Nick) root=$($cfg.GameDir)"
    }
}

function Write-WatchdogConfig($cfg, [int]$Enabled) {
    $wdDir = Join-Path $cfg.GameDir 'moonloader\ArzMarket\watchdog'
    [IO.Directory]::CreateDirectory($wdDir) | Out-Null
    $configPath = Join-Path $wdDir 'watchdog_config.ini'
    $text = @(
        "enabled=$Enabled",
        "nick=$($cfg.Nick)",
        'server=',
        "port=$($cfg.Port)",
        'disconnect_timeout=15',
        'startup_grace=90',
        'unspawned_timeout=30'
    ) -join "`r`n"
    [IO.File]::WriteAllText($configPath, $text + "`r`n", [Text.UTF8Encoding]::new($false))
    return $configPath
}

function Create-WatchdogBat($cfg) {
    $template = [string]$WatchdogTemplate
    $generated = $template.Replace('__MAIN_DIR__', $cfg.MainDir)
    $generated = $generated.Replace('__ROOT__', $cfg.GameDir)
    $generated = $generated.Replace('__USER_ID__', $cfg.UserId)
    $generated = $generated.Replace('__NICK__', $cfg.Nick)
    $generated = $generated.Replace('__SERVER__', $cfg.Server)
    $generated = $generated.Replace('__PORT__', [string]$cfg.Port)
    $generated = $generated.Replace('__EXTRA_ARGS__', $cfg.ExtraArgs)
    $wdDevLog = Join-Path $LogsDir ('watchdog_{0}.log' -f $cfg.Nick)
    $generated = $generated.Replace('__DEV_LOG_FILE__', $wdDevLog)
    if ($generated -match '__[A-Z0-9_]+__') { throw 'Внутренняя ошибка шаблона watchdog: остались служебные параметры.' }

    # cmd.exe expects Windows CRLF line endings for reliable BAT parsing.
    # The launcher itself may be distributed with LF-only line endings, so
    # normalize the generated watchdog before writing it to disk.
    $generated = [regex]::Replace($generated, "\r\n|\r|\n", "`r`n")

    $out = Join-Path $cfg.GameDir 'Arizona_Account_Watchdog_GENERATED.bat'
    [IO.File]::WriteAllText($out, $generated, [Text.UTF8Encoding]::new($false))
    return $out
}

function Start-WatchdogAccount($cfg, [string]$Role) {
    Enable-Multiprocess $cfg.MainDir
    Enable-Multiprocess $cfg.GameDir
    Enable-MoonLoader $cfg.GameDir
    $configPath = Write-WatchdogConfig $cfg 1
    $stopFile = Join-Path (Split-Path -Parent $configPath) 'stop.flag'
    if (Test-Path -LiteralPath $stopFile) { Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue }
    $bat = Create-WatchdogBat $cfg
    Write-DevLog "Starting watchdog role=$Role nick=$($cfg.Nick) root=$($cfg.GameDir) launchServer=$($cfg.Server):$($cfg.Port); expected server IP will be pinned from SA-MP state"
    Start-Process -FilePath $bat -WorkingDirectory $cfg.GameDir -WindowStyle Minimized | Out-Null
}

function Stop-WatchdogAccount($cfg) {
    if ($null -eq $cfg) { return }
    try {
        $configPath = Write-WatchdogConfig $cfg 0
        $stopFile = Join-Path (Split-Path -Parent $configPath) 'stop.flag'
        [IO.File]::WriteAllText($stopFile, '1', [Text.UTF8Encoding]::new($false))
    } catch {}
}

function Get-TextDocument([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $offset = 0
    [byte[]]$preamble = @()
    $enc = $null

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $enc = New-Object System.Text.UTF8Encoding($true, $false)
        $offset = 3
        $preamble = [byte[]](0xEF,0xBB,0xBF)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $enc = New-Object System.Text.UnicodeEncoding($false, $true)
        $offset = 2
        $preamble = [byte[]](0xFF,0xFE)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $enc = New-Object System.Text.UnicodeEncoding($true, $true)
        $offset = 2
        $preamble = [byte[]](0xFE,0xFF)
    } else {
        try {
            $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
            $null = $strictUtf8.GetString($bytes)
            $enc = New-Object System.Text.UTF8Encoding($false, $false)
        } catch {
            $enc = [Text.Encoding]::GetEncoding(1251)
        }
    }

    $text = if ($bytes.Length -gt $offset) { $enc.GetString($bytes, $offset, $bytes.Length - $offset) } else { '' }
    return [pscustomobject]@{ Text=$text; Encoding=$enc; Preamble=$preamble }
}

function Write-TextDocument($doc, [string]$Path, [string]$Text) {
    [byte[]]$body = $doc.Encoding.GetBytes($Text)
    if ($doc.Preamble.Length -gt 0) {
        [byte[]]$all = New-Object byte[] ($doc.Preamble.Length + $body.Length)
        [Array]::Copy($doc.Preamble, 0, $all, 0, $doc.Preamble.Length)
        [Array]::Copy($body, 0, $all, $doc.Preamble.Length, $body.Length)
        [IO.File]::WriteAllBytes($Path, $all)
    } else {
        [IO.File]::WriteAllBytes($Path, $body)
    }
}

function Read-IniSections([string]$Path) {
    $doc = Get-TextDocument $Path
    $sections = @{}
    $current = ''
    foreach ($line in [regex]::Split($doc.Text, "\r?\n")) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $current = $matches[1].Trim()
            if (-not $sections.ContainsKey($current)) { $sections[$current] = @{} }
            continue
        }
        if ($current -ne '' -and $line -match '^\s*([^;#][^=]*?)\s*=\s*(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2]
            $sections[$current][$key] = $value
        }
    }
    return [pscustomobject]@{ Document=$doc; Sections=$sections }
}

function Get-DonorAuthPayload($donor) {
    $iniPath = Join-Path $donor.GameDir 'moonloader\config\ArzMarket\ArzMarket.ini'
    if (-not (Test-Path -LiteralPath $iniPath)) { return $null }
    $parsed = Read-IniSections $iniPath
    $out = [ordered]@{}

    foreach ($sectionName in $parsed.Sections.Keys) {
        $src = $parsed.Sections[$sectionName]
        $dst = [ordered]@{}
        if ($sectionName -ieq 'cfg') {
            foreach ($field in $CfgAccountFields) {
                if ($src.ContainsKey($field) -and -not [string]::IsNullOrWhiteSpace([string]$src[$field])) { $dst[$field] = [string]$src[$field] }
            }
        }
        foreach ($field in $AnySectionAuthFields) {
            if ($src.ContainsKey($field) -and -not [string]::IsNullOrWhiteSpace([string]$src[$field])) { $dst[$field] = [string]$src[$field] }
        }
        if ($dst.Count -gt 0) { $out[$sectionName] = $dst }
    }

    $token = ''
    if ($out.Contains('cfg') -and $out['cfg'].Contains('myServerToken')) { $token = [string]$out['cfg']['myServerToken'] }
    if ([string]::IsNullOrWhiteSpace($token)) { return $null }
    $sig = ($out | ConvertTo-Json -Depth 8 -Compress)
    return [pscustomobject]@{ Token=$token; Sections=$out; Signature=$sig }
}

function Update-MainIniFromPayload($main, $payload, $Missing = @{}) {
    $path = Join-Path $main.GameDir 'moonloader\config\ArzMarket\ArzMarket.ini'
    $doc = Get-TextDocument $path
    $newline = if ($doc.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $inputLines = [regex]::Split($doc.Text, "\r?\n")
    $output = New-Object 'System.Collections.Generic.List[string]'
    $seenSections = @{}
    $seenKeys = @{}
    $current = ''

    function Add-MissingKeysForSection([string]$SectionName) {
        if ([string]::IsNullOrWhiteSpace($SectionName)) { return }
        if (-not $payload.Sections.Contains($SectionName)) { return }
        $target = $payload.Sections[$SectionName]
        if (-not $seenKeys.ContainsKey($SectionName)) { $seenKeys[$SectionName] = @{} }
        foreach ($key in $target.Keys) {
            if (-not $seenKeys[$SectionName].ContainsKey($key)) {
                $output.Add("$key=$($target[$key])")
                $seenKeys[$SectionName][$key] = $true
            }
        }
    }

    foreach ($line in $inputLines) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            Add-MissingKeysForSection $current
            $current = $matches[1].Trim()
            $seenSections[$current] = $true
            if (-not $seenKeys.ContainsKey($current)) { $seenKeys[$current] = @{} }
            $output.Add($line)
            continue
        }

        if ($current -ne '' -and $line -match '^\s*([^;#][^=]*?)\s*=') {
            $key = $matches[1].Trim()
            if ($Missing.Contains($current) -and $Missing[$current].Contains($key)) { continue }
            if (-not $payload.Sections.Contains($current)) { $output.Add($line); continue }
            $target = $payload.Sections[$current]
            if ($target.Contains($key)) {
                $output.Add("$key=$($target[$key])")
                $seenKeys[$current][$key] = $true
                continue
            }
        }
        $output.Add($line)
    }
    Add-MissingKeysForSection $current

    foreach ($sectionName in $payload.Sections.Keys) {
        if (-not $seenSections.ContainsKey($sectionName)) {
            if ($output.Count -gt 0 -and $output[$output.Count-1] -ne '') { $output.Add('') }
            $output.Add("[$sectionName]")
            foreach ($key in $payload.Sections[$sectionName].Keys) { $output.Add("$key=$($payload.Sections[$sectionName][$key])") }
        }
    }

    $text = [string]::Join($newline, $output)
    Write-TextDocument $doc $path $text
}

function Test-BridgeAuthField([string]$Section, [string]$Field) {
    return ($Section.Length -gt 0 -and $Section -notmatch '[\r\n\[\]]' -and
        (($Section -ceq 'cfg' -and $CfgAccountFields -ccontains $Field) -or $AnySectionAuthFields -ccontains $Field))
}

function Write-BridgeJsonAtomic([string]$Path, $Value) {
    $tmp = $Path + '.tmp'
    try {
        $json = $Value | ConvertTo-Json -Depth 10 -Compress
        [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-MainAuthBackup($main, $payload, [string]$Session) {
    try {
    if ([string]::IsNullOrWhiteSpace($Session)) { throw 'Нет session для backup MAIN.' }
    $dir = Ensure-ArzConfigDir $main
    $path = Join-Path $dir 'main_auth_restore.json'
    $sections = [ordered]@{}
    $missing = [ordered]@{}
    $createdAt = [DateTime]::UtcNow.ToString('o')
    if (Test-Path -LiteralPath $path) {
        $old = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
        if ($old.protocol -ne $BridgeProtocol -or $old.session -cne $Session -or
            $old.sections -isnot [pscustomobject] -or $old.missing -isnot [pscustomobject]) { throw 'Invalid backup' }
        $createdAt = $old.createdAt
        foreach ($group in @('sections', 'missing')) {
            $target = if ($group -eq 'sections') { $sections } else { $missing }
            foreach ($section in $old.$group.PSObject.Properties) {
                foreach ($field in $section.Value.PSObject.Properties) {
                    if (Test-BridgeAuthField $section.Name $field.Name) {
                        if (-not $target.Contains($section.Name)) { $target[$section.Name] = [ordered]@{} }
                        $target[$section.Name][$field.Name] = $field.Value
                    }
                }
            }
        }
    }
    $parsed = Read-IniSections (Join-Path $dir 'ArzMarket.ini')
    $touched = [ordered]@{}
    foreach ($section in $payload.Sections.Keys) {
        $touched[$section] = @($payload.Sections[$section].Keys)
    }
    if (-not [string]::IsNullOrWhiteSpace($PairRuntime.ProfileKey)) {
        if (-not $touched.Contains('cfg')) { $touched['cfg'] = @() }
        $touched['cfg'] += @('authPremiumTokenAuth','authUserTempKey','premiumTokenAuth','lastUpdatePremiumToken')
    }
    $changed = -not (Test-Path -LiteralPath $path)
    foreach ($section in $touched.Keys) {
        foreach ($field in $touched[$section]) {
            if (-not (Test-BridgeAuthField $section $field)) { continue }
            if (($sections.Contains($section) -and $sections[$section].Contains($field)) -or
                ($missing.Contains($section) -and $missing[$section].Contains($field))) { continue }
            if ($parsed.Sections.ContainsKey($section) -and $parsed.Sections[$section].ContainsKey($field)) {
                if (-not $sections.Contains($section)) { $sections[$section] = [ordered]@{} }
                $sections[$section][$field] = [string]$parsed.Sections[$section][$field]
            } else {
                if (-not $missing.Contains($section)) { $missing[$section] = [ordered]@{} }
                $missing[$section][$field] = $true
            }
            $changed = $true
        }
    }
    if ($changed) {
        try {
            Write-BridgeJsonAtomic $path ([ordered]@{ protocol=$BridgeProtocol; session=$Session; createdAt=$createdAt; sections=$sections; missing=$missing })
        } catch { throw 'Не удалось сохранить backup MAIN; передача auth остановлена.' }
    }
    } catch { throw 'Не удалось сохранить backup MAIN; передача auth остановлена.' }
}

function Restore-MainAuthBackup($main) {
    if (@(Get-AccountGameProcesses $main).Count -gt 0 -or @(Get-AccountWatchdogProcessIds $main).Count -gt 0) {
        throw 'Восстановление MAIN невозможно: прошлый запуск ещё работает.'
    }
    $dir = Ensure-ArzConfigDir $main
    $path = Join-Path $dir 'main_auth_restore.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $backup = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
            $bridge = Join-Path $dir 'account_bridge.ini'
            $expectedSession = ''
            if (Test-Path -LiteralPath $bridge) {
                foreach ($line in [IO.File]::ReadAllLines($bridge)) {
                    if ($line -match '^session=(.+)$') { $expectedSession = $matches[1] }
                }
            }
            if ($backup.protocol -ne $BridgeProtocol -or [string]::IsNullOrWhiteSpace($expectedSession) -or
                $backup.session -cne $expectedSession -or $backup.sections -isnot [pscustomobject] -or
                $backup.missing -isnot [pscustomobject]) { throw 'Invalid backup' }
            $sections = [ordered]@{}
            $missing = [ordered]@{}
            foreach ($group in @('sections', 'missing')) {
                $target = if ($group -eq 'sections') { $sections } else { $missing }
                foreach ($section in $backup.$group.PSObject.Properties) {
                    foreach ($field in $section.Value.PSObject.Properties) {
                        if (-not (Test-BridgeAuthField $section.Name $field.Name)) { continue }
                        if ($group -eq 'missing' -and $field.Value -ne $true) { continue }
                        if ($group -eq 'sections' -and ([string]$field.Value -match '[\r\n]' -or
                            ($field.Value -isnot [string] -and $field.Value -isnot [ValueType]))) { throw 'Invalid auth value' }
                        if (-not $target.Contains($section.Name)) { $target[$section.Name] = [ordered]@{} }
                        $target[$section.Name][$field.Name] = $field.Value
                    }
                }
            }
            Update-MainIniFromPayload $main ([pscustomobject]@{ Sections=$sections }) $missing
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        } catch { throw 'Не удалось восстановить backup MAIN; новый запуск остановлен.' }
    }
    foreach ($name in @('launcher_profile_auth.json','launcher_profile_auth.json.tmp','donor_auth_sync.json')) {
        $stale = Join-Path $dir $name
        if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force -ErrorAction Stop }
    }
}

function Restore-BridgeStandaloneFlags($cfg) {
    $dir = Ensure-ArzConfigDir $cfg
    $statePath = Join-Path $dir 'bridge_restore_state.ini'
    if (-not (Test-Path -LiteralPath $statePath)) { return }
    $state = @{}
    foreach ($line in [IO.File]::ReadAllLines($statePath)) {
        if ($line -match '^([^=]+)=(.*)$') { $state[$matches[1]] = $matches[2] }
    }
    if ($state.captured -ne '1' -or [string]::IsNullOrWhiteSpace($state.session)) { throw 'Некорректное исходное состояние bridge.' }
    $expectedSession = ''
    $bridgePath = Join-Path $dir 'account_bridge.ini'
    if (Test-Path -LiteralPath $bridgePath) {
        foreach ($line in [IO.File]::ReadAllLines($bridgePath)) {
            if ($line -match '^session=(.+)$') { $expectedSession = $matches[1] }
        }
    }
    if ($state.session -cne $expectedSession) { throw 'Исходное состояние bridge принадлежит другой session.' }
    foreach ($entry in @(@('offline_mode.flag','offline_before'), @('ini_write_locked.flag','lock_before'))) {
        $path = Join-Path $dir $entry[0]
        if ($state[$entry[1]] -eq '1') {
            [IO.File]::WriteAllText($path, '1', [Text.UTF8Encoding]::new($false))
        } elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
    }
    Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop
}

function Write-BridgeStandaloneState($cfg, [string]$Role) {
    $dir = Ensure-ArzConfigDir $cfg
    $path = Join-Path $dir 'bridge_restore_state.ini'
    if (Test-Path -LiteralPath $path) {
        $state = @{}
        foreach ($line in [IO.File]::ReadAllLines($path)) {
            if ($line -match '^([^=]+)=(.*)$') { $state[$matches[1]] = $matches[2] }
        }
        if ($state.captured -eq '1' -and $state.session -ceq $PairRuntime.Session) { return }
        throw 'Исходное состояние bridge принадлежит другой session.'
    }
    $offline = if (Test-Path -LiteralPath (Join-Path $dir 'offline_mode.flag')) { '1' } else { '0' }
    $locked = if (Test-Path -LiteralPath (Join-Path $dir 'ini_write_locked.flag')) { '1' } else { '0' }
    $tmp = $path + '.tmp'
    try {
        $text = "captured=1`r`nsession=$($PairRuntime.Session)`r`nrole=$Role`r`noffline_before=$offline`r`nlock_before=$locked`r`ncaptured_at=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())`r`n"
        [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $path -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-LauncherProfileAuth($main) {
    if ([string]::IsNullOrWhiteSpace($PairRuntime.ProfileKey)) { return }
    if (-not $PairRuntime.Active -or [string]::IsNullOrWhiteSpace($PairRuntime.Session)) { throw 'Нет активной session для ключа профиля.' }
    $path = Join-Path (Ensure-ArzConfigDir $main) 'launcher_profile_auth.json'
    try {
        Write-BridgeJsonAtomic $path ([ordered]@{
            protocol=$BridgeProtocol; session=$PairRuntime.Session
            createdAt=[int64][Math]::Floor(([DateTime]::UtcNow - [DateTime]'1970-01-01T00:00:00Z').TotalSeconds)
            key=$PairRuntime.ProfileKey
        })
    } catch { throw 'Не удалось передать ключ профиля в MAIN.' }
    finally { $PairRuntime.ProfileKey = ''; $profileKeyBox.Password = '' }
}

function Write-DonorSnapshot($main, $donor, $payload, [bool]$Initial) {
    $dir = Ensure-ArzConfigDir $main
    Write-MainAuthBackup $main $payload $PairRuntime.Session
    if ($Initial) { Update-MainIniFromPayload $main $payload }
    $syncPath = Join-Path $dir 'donor_auth_sync.json'
    $snapshot = [ordered]@{
        protocol = $BridgeProtocol
        session = $PairRuntime.Session
        version = [DateTime]::UtcNow.Ticks.ToString()
        generatedAt = (Get-Date).ToString('o')
        sourceNick = $donor.Nick
        targetNick = $main.Nick
        sections = $payload.Sections
    }
    $json = $snapshot | ConvertTo-Json -Depth 10 -Compress
    $tmp = $syncPath + '.tmp'
    try {
        [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $syncPath -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }

    if ($Initial) {
        Set-RoleFiles $main 'MAIN' $true
        Write-Status 'Передал данные в основной.'
    }
    return $syncPath
}

function Get-WatchdogState($cfg) {
    $path = Join-Path $cfg.GameDir 'moonloader\ArzMarket\watchdog\state.ini'
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{ State='NO_STATE'; Age=999999; Data=@{} } }
    $age = ((Get-Date) - (Get-Item -LiteralPath $path).LastWriteTime).TotalSeconds
    $kv = @{}
    foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^([^=]+)=(.*)$') { $kv[$matches[1].Trim()] = $matches[2].Trim() }
    }
    $state = if ($kv.ContainsKey('state')) { $kv['state'] } else { 'UNKNOWN' }
    return [pscustomobject]@{ State=$state; Age=$age; Data=$kv }
}

function Start-MainDonor {
    $pair = Validate-Pair
    $proxyCfg = Get-ProxyUiConfig
    Save-Settings $pair

    if (-not (Test-PairBridgeLua $pair.Main.GameDir)) { throw 'В папке основного аккаунта не найден нужный ArzMarket. Установите Lua из комплекта.' }
    if (-not (Test-PairBridgeLua $pair.Donor.GameDir)) { throw 'В папке донорского аккаунта не найден нужный ArzMarket. Установите Lua из комплекта.' }

    if ($proxyCfg.Enabled -eq $true) {
        if (-not (Test-PairProxyLua $pair.Main.GameDir)) { throw 'В папке основного аккаунта установлен ArzMarket без поддержки прокси. Установите подготовленную proxy-версию Lua.' }
        if (-not (Test-PairProxyLua $pair.Donor.GameDir)) { throw 'В папке донорского аккаунта установлен ArzMarket без поддержки прокси. Установите подготовленную proxy-версию Lua.' }

        if ($null -eq $script:PreparedProxyResult) { throw 'Прокси не был проверен на этапе подготовки.' }
        $proxyTest = $script:PreparedProxyResult
        Set-ProxyTestStatus ("Прокси готов. Обычный IP: {0} | ArzMarket IP: {1} | {2} ms" -f $proxyTest.DirectIp, $proxyTest.ProxyIp, $proxyTest.LatencyMs) ([Windows.Media.Brushes]::ForestGreen)
        Write-Status ("Прокси проверен. ArzMarket IP: {0}" -f $proxyTest.ProxyIp)
    }

    Stop-ExistingPairBeforeRestart $pair
    Restore-MainAuthBackup $pair.Main
    if (@(Get-AccountGameProcesses $pair.Donor).Count -gt 0 -or @(Get-AccountWatchdogProcessIds $pair.Donor).Count -gt 0) {
        throw 'Прошлый запуск донора ещё работает.'
    }
    Restore-BridgeStandaloneFlags $pair.Main
    Restore-BridgeStandaloneFlags $pair.Donor
    $PairRuntime.Session = [Guid]::NewGuid().ToString('N')
    $PairRuntime.ProfileKey = $profileKeyBox.Password.Trim()

    Write-ArzMarketProxyConfig $pair.Main $proxyCfg
    Write-ArzMarketProxyConfig $pair.Donor $proxyCfg

    $PairRuntime.Active = $true
    $PairRuntime.Phase = 'WAIT_DONOR'
    $PairRuntime.Main = $pair.Main
    $PairRuntime.Donor = $pair.Donor
    $PairRuntime.Deadline = (Get-Date).AddMinutes(3)
    $PairRuntime.CandidateToken = ''
    $PairRuntime.CandidateSince = [datetime]::MinValue
    $PairRuntime.LastSignature = ''

    Write-LauncherHeartbeat $pair.Donor $true
    Write-LauncherHeartbeat $pair.Main $true
    Set-RoleFiles $pair.Donor 'DONOR' $false
    Set-RoleFiles $pair.Main 'MAIN' $false
    $mainLock = Join-Path $pair.Main.GameDir 'moonloader\config\ArzMarket\ini_write_locked.flag'
    if (Test-Path -LiteralPath $mainLock) { Remove-Item -LiteralPath $mainLock -Force -ErrorAction SilentlyContinue }

    Write-DevLog "Pair start. MAIN=$($pair.Main.Nick) server#$($pair.Main.ServerNumber) $($pair.Main.Server); DONOR=$($pair.Donor.Nick) server#$($pair.Donor.ServerNumber) $($pair.Donor.Server)"
    Write-Status "Вхожу в донор: $($pair.Donor.Nick)..."
    Start-WatchdogAccount $pair.Donor 'DONOR'
}

function Start-PairWorkflow { Start-MainDonor }

function Sync-Now {
    if (-not $PairRuntime.Active -or [string]::IsNullOrWhiteSpace($PairRuntime.Session)) { throw 'Сначала запустите связку.' }
    $pair = [pscustomobject]@{ Main=$PairRuntime.Main; Donor=$PairRuntime.Donor }
    $payload = Get-DonorAuthPayload $pair.Donor
    if ($null -eq $payload) { throw 'Донорский аккаунт пока не получил токен. Подождите его полного входа в игру.' }
    Set-RoleFiles $pair.Donor 'DONOR' $false
    Write-DonorSnapshot $pair.Main $pair.Donor $payload ($PairRuntime.Phase -eq 'WAIT_DONOR') | Out-Null
    $PairRuntime.LastSignature = $payload.Signature
    Write-Status 'Передал данные в основной.'
}

function Stop-PairWorkflow {
    try {
        $pair = Validate-Pair
        Stop-WatchdogAccount $pair.Main
        Stop-WatchdogAccount $pair.Donor
        Write-LauncherHeartbeat $pair.Main $false
        Write-LauncherHeartbeat $pair.Donor $false
        $PairRuntime.Active = $false
        $PairRuntime.Phase = 'STOPPED'
        $PairRuntime.ProfileKey = ''
        $profileKeyBox.Password = ''
        Write-Status 'Остановил автовосстановление.'
    } catch {
        Write-DevLog "Stop error: $($_.Exception.ToString())"
        Write-Status 'Не смог остановить автовосстановление.'
    }
}

function Set-UiFromAccount($ui, $cfg) {
    if ($null -eq $cfg) { return }
    if ($cfg.GameDir) { $ui.GameDir.Text = [string]$cfg.GameDir }
    if ($cfg.Nick) { $ui.Nick.Text = [string]$cfg.Nick }
    $serverNumber = 0
    if ($cfg.ServerNumber) {
        [int]::TryParse([string]$cfg.ServerNumber, [ref]$serverNumber) | Out-Null
    } elseif ($cfg.Server) {
        $serverNumber = Get-ServerNumberFromHost ([string]$cfg.Server)
    }
    if ($serverNumber -ge 1 -and $serverNumber -le 33) { $ui.ServerNumber.Text = [string]$serverNumber }
    if ($cfg.UserId) { $ui.UserIdValue = [string]$cfg.UserId }
    Update-ServerNameLabel $ui
}

function Save-UiSettings {
    if ($null -eq $uiA -or $null -eq $uiB -or $null -eq $mainA -or $null -eq $mainB) { return }
    try {
        $obj = [ordered]@{
            Version = 5
            BannedMainIndex = $(if ($mainB.IsChecked) { 'B' } else { 'A' })
            MainIndex = $(if ($mainB.IsChecked) { 'B' } else { 'A' })
            TokenSourceIndex = $(if ($mainB.IsChecked) { 'A' } else { 'B' })
            AccountA = [ordered]@{
                GameDir = [string]$uiA.GameDir.Text
                Nick = [string]$uiA.Nick.Text
                ServerNumber = [string]$uiA.ServerNumber.Text
            }
            AccountB = [ordered]@{
                GameDir = [string]$uiB.GameDir.Text
                Nick = [string]$uiB.Nick.Text
                ServerNumber = [string]$uiB.ServerNumber.Text
            }
            Proxy = Get-ProxySettingsForStorage
        }
        $json = $obj | ConvertTo-Json -Depth 6
        [IO.File]::WriteAllText($SettingsPath, $json, [Text.UTF8Encoding]::new($false))
    } catch {
        Write-DevLog "Settings autosave error: $($_.Exception.ToString())"
    }
}

function Stop-MainDonor { Stop-PairWorkflow }

function Write-JsonAtomic([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $json = $Value | ConvertTo-Json -Depth 12
        [IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temp, $Path, $null, $true)
        } else {
            [IO.File]::Move($temp, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-PreparationProgress([string]$Text, [string]$Kind = 'info') {
    if ([string]::IsNullOrWhiteSpace($PreparationProgressPath)) { return }
    $entry = [ordered]@{ time=(Get-Date).ToString('o'); kind=$Kind; text=$Text }
    $line = ($entry | ConvertTo-Json -Compress) + [Environment]::NewLine
    [IO.File]::AppendAllText($PreparationProgressPath, $line, [Text.UTF8Encoding]::new($false))
}

function Invoke-GitHubRequest([string]$Uri, [string]$OutFile = '') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent'='Arizona-Main-Donor-Launcher'; 'Accept'='application/vnd.github+json' }
    $lastError = $null
    for ($attempt = 1; $attempt -le $GitHubRequestAttempts; $attempt++) {
        try {
            if ([string]::IsNullOrWhiteSpace($OutFile)) {
                return Invoke-WebRequest -UseBasicParsing -Uri $Uri -Headers $headers -TimeoutSec $GitHubRequestTimeoutSeconds -ErrorAction Stop
            }
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -Headers $headers -TimeoutSec $GitHubRequestTimeoutSeconds -OutFile $OutFile -ErrorAction Stop | Out-Null
            return Get-Item -LiteralPath $OutFile -ErrorAction Stop
        } catch {
            $lastError = $_.Exception
            $status = 0
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}
            $transient = ($status -eq 0 -or $status -eq 408 -or $status -eq 429 -or $status -ge 500)
            if ($attempt -ge $GitHubRequestAttempts -or -not $transient) {
                $hint = if ($status -eq 403) { ' GitHub отклонил запрос: проверьте rate limit.' } elseif ($status -eq 404) { ' Файл или репозиторий не найден (404).' } else { '' }
                throw "GitHub недоступен: $($lastError.Message).$hint"
            }
            Start-Sleep -Seconds $attempt
        }
    }
    throw "GitHub недоступен: $($lastError.Message)"
}

function ConvertTo-SafeRelativePath([string]$Path) {
    $relative = ([string]$Path).Trim().Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)' -or $relative.Contains(':')) {
        throw "GitHub вернул небезопасный путь: $Path"
    }
    return $relative.TrimStart('\')
}

function Resolve-SafePayloadPath([string]$GameRoot, [string]$RelativePath) {
    $root = [IO.Path]::GetFullPath($GameRoot).TrimEnd('\') + '\'
    $relative = ConvertTo-SafeRelativePath $RelativePath
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Путь выходит за пределы папки Arizona: $RelativePath"
    }
    return $full
}

function Test-ProtectedPayloadPath([string]$RelativePath) {
    $p = (ConvertTo-SafeRelativePath $RelativePath).Replace('\','/').ToLowerInvariant()
    if ($p.StartsWith('moonloader/config/arzmarket/')) { return $true }
    if ($p -match '^moonloader/arzmarket/(usersinfo|cache|watchdog)/') { return $true }
    $protectedNames = @(
        'donor_auth_sync.json','launcher_heartbeat.ini','account_bridge.ini','account_role.flag',
        'network_proxy.ini','proxy_required.flag','launcher_profile_auth.json','main_auth_restore.json',
        'arzmarket.ini','ini_write_locked.flag','buy.json','sell.json','trade_filters.json',
        'manual_purchased.json','log.json','vrprofile.json','release_notes_state.json',
        'html_window_state.json','html_draft_sell.json','component_state.json','baron_assistant.json',
        'theme.json','menu_theme.json'
    )
    return $protectedNames -contains [IO.Path]::GetFileName($p)
}

function Get-GitBlobSha([string]$Path) {
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $sha1 = [Security.Cryptography.SHA1]::Create()
    $memory = New-Object System.IO.MemoryStream
    $stream = $null
    try {
        [byte[]]$header = [Text.Encoding]::UTF8.GetBytes(('blob {0}' -f [long]$file.Length) + [char]0)
        $memory.Write($header, 0, [int]$header.Length)
        $stream = [IO.File]::OpenRead($file.FullName)
        $stream.CopyTo($memory)
        $memory.Position = 0
        [byte[]]$hash = $sha1.ComputeHash($memory)
        return ([BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant()
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        $memory.Dispose()
        $sha1.Dispose()
    }
}

function Get-GitHubRawUrl([string]$Owner, [string]$Repo, [string]$Branch, [string]$RemotePath) {
    foreach ($value in @($Owner,$Repo,$Branch)) {
        if ([string]::IsNullOrWhiteSpace($value) -or $value -notmatch '^[A-Za-z0-9._/-]+$') { throw 'Некорректные параметры GitHub.' }
    }
    $segments = @($RemotePath.Replace('\','/').Split('/') | Where-Object { $_ -ne '' } | ForEach-Object { [Uri]::EscapeDataString($_) })
    return 'https://raw.githubusercontent.com/{0}/{1}/{2}/{3}' -f $Owner,$Repo,$Branch,($segments -join '/')
}

function Get-GitHubTree([string]$Owner, [string]$Repo, [string]$Branch) {
    $uri = 'https://api.github.com/repos/{0}/{1}/git/trees/{2}?recursive=1' -f $Owner,$Repo,[Uri]::EscapeDataString($Branch)
    $response = Invoke-GitHubRequest $uri
    try { $data = $response.Content | ConvertFrom-Json -ErrorAction Stop } catch { throw 'GitHub вернул повреждённый JSON дерева файлов.' }
    if ($null -eq $data -or $data.truncated -eq $true -or $null -eq $data.tree) { throw 'GitHub вернул неполное дерево файлов.' }
    return @($data.tree)
}

function Get-RemotePayloadManifest($Config) {
    $tree = @(Get-GitHubTree ([string]$Config.PayloadOwner) ([string]$Config.PayloadRepo) ([string]$Config.PayloadBranch))
    $files = @()

    foreach ($entry in $tree) {
        if ($null -eq $entry -or [string]$entry.type -ne 'blob') { continue }
        $remote = ([string]$entry.path).Replace('\','/').TrimStart([char]'/')
        if ([string]::IsNullOrWhiteSpace($remote)) { continue }

        $isProjectFile = ($remote -like 'ArzMarket/*') -or ($remote -like 'modules/*') -or ($remote -match '^(?i:by_Quant_ArzMarket.*\.lua)$') -or ($remote -ieq 'ArzMarket_Loader_by_Quant.lua')
        if (-not $isProjectFile) { continue }

        $local = ConvertTo-SafeRelativePath ('moonloader/' + $remote)
        if (Test-ProtectedPayloadPath $local) { throw "Payload пытается перезаписать пользовательский файл: $local" }

        try { [long]$size = [Convert]::ToInt64($entry.size, [Globalization.CultureInfo]::InvariantCulture) }
        catch { throw "Некорректный размер GitHub-файла: $remote" }
        if ($size -lt 0) { throw "Некорректный размер GitHub-файла: $remote" }

        $sha = ([string]$entry.sha).Trim().ToLowerInvariant()
        if ($sha -notmatch '^[a-f0-9]{40}$') { throw "Некорректный SHA GitHub-файла: $remote" }

        $files += [pscustomobject]@{
            RemoteRelativePath = $remote
            LocalRelativePath = $local
            Sha = $sha
            Size = $size
        }
    }

    if ($files.Count -eq 0) {
        throw 'В GitHub не найдены файлы ArzMarket. Ожидались каталоги ArzMarket/, modules/ и основной Lua-файл.'
    }
    return @($files | Sort-Object -Property LocalRelativePath)
}

function Test-LocalPayload($Manifest, [string]$GameRoot) {
    $changed = @()
    foreach ($entry in @($Manifest)) {
        if ($null -eq $entry) { continue }
        $target = Resolve-SafePayloadPath $GameRoot ([string]$entry.LocalRelativePath)
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $changed += $entry
            continue
        }
        $local = Get-Item -LiteralPath $target -ErrorAction Stop
        $expectedSize = [Convert]::ToInt64($entry.Size, [Globalization.CultureInfo]::InvariantCulture)
        if ([long]$local.Length -ne $expectedSize) {
            $changed += $entry
            continue
        }
        $localSha = Get-GitBlobSha $target
        if ($localSha -ne ([string]$entry.Sha).ToLowerInvariant()) { $changed += $entry }
    }
    return @($changed)
}

function Test-GameWriteAccess([string]$GameRoot) {
    $probe = Join-Path $GameRoot ('.launcher_write_test_{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try { [IO.File]::WriteAllText($probe, 'ok', [Text.UTF8Encoding]::new($false)) }
    catch { throw "Нет прав записи в папку Arizona: $GameRoot" }
    finally { if (Test-Path -LiteralPath $probe -PathType Leaf) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue } }
}

function Install-StagedFilesTransactional($Entries, [string[]]$GameRoots, [string]$StageRoot) {
    $installed = @()
    try {
        foreach ($gameRoot in $GameRoots) {
            foreach ($entry in $Entries) {
                $target = Resolve-SafePayloadPath $gameRoot $entry.LocalRelativePath
                $stage = Join-Path $StageRoot ([string]$entry.Sha)
                $parent = Split-Path -Parent $target
                [IO.Directory]::CreateDirectory($parent) | Out-Null
                $newPath = Join-Path $parent ('.' + [IO.Path]::GetFileName($target) + '.' + [Guid]::NewGuid().ToString('N') + '.new')
                $backup = Join-Path $parent ('.' + [IO.Path]::GetFileName($target) + '.' + [Guid]::NewGuid().ToString('N') + '.bak')
                [IO.File]::Copy($stage, $newPath, $true)
                $hadOld = Test-Path -LiteralPath $target -PathType Leaf
                try {
                    if ($hadOld) { [IO.File]::Replace($newPath, $target, $backup, $true) }
                    else { [IO.File]::Move($newPath, $target) }
                } catch {
                    if (Test-Path -LiteralPath $newPath -PathType Leaf) { Remove-Item -LiteralPath $newPath -Force -ErrorAction SilentlyContinue }
                    throw "Не удалось атомарно заменить занятый файл: $target. $($_.Exception.Message)"
                }
                $installed += [pscustomobject]@{ Target=$target; Backup=$backup; HadOld=$hadOld }
            }
        }
    } catch {
        for ($i = $installed.Count - 1; $i -ge 0; $i--) {
            $item = $installed[$i]
            try {
                if ($item.HadOld -and (Test-Path -LiteralPath $item.Backup -PathType Leaf)) { [IO.File]::Copy($item.Backup, $item.Target, $true) }
                elseif (-not $item.HadOld -and (Test-Path -LiteralPath $item.Target -PathType Leaf)) { Remove-Item -LiteralPath $item.Target -Force }
            } catch {}
        }
        throw
    } finally {
        foreach ($item in $installed) {
            if (Test-Path -LiteralPath $item.Backup -PathType Leaf) { Remove-Item -LiteralPath $item.Backup -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Download-ManifestFiles($Entries, $Config, [string]$StageRoot) {
    [IO.Directory]::CreateDirectory($StageRoot) | Out-Null
    foreach ($entry in $Entries) {
        $stage = Join-Path $StageRoot ([string]$entry.Sha)
        if (Test-Path -LiteralPath $stage -PathType Leaf) { continue }
        Write-PreparationProgress ("Загрузка: {0}" -f $entry.LocalRelativePath)
        $url = Get-GitHubRawUrl $Config.PayloadOwner $Config.PayloadRepo $Config.PayloadBranch $entry.RemoteRelativePath
        Invoke-GitHubRequest $url $stage | Out-Null
        $downloaded = Get-Item -LiteralPath $stage
        if ($downloaded.Length -ne [long]$entry.Size -or (Get-GitBlobSha $stage) -ne [string]$entry.Sha) {
            Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue
            throw "Проверка загруженного файла не пройдена: $($entry.LocalRelativePath)"
        }
    }
}

function Download-MissingOrChangedFiles($Entries, $Config, [string]$StageRoot) {
    Download-ManifestFiles $Entries $Config $StageRoot
}

function Update-ArzMarketPayload($Manifest, [string[]]$GameRoots, $Config, [string]$StageRoot) {
    $bySha = @{}
    foreach ($root in @($GameRoots)) {
        $missing = @(Test-LocalPayload $Manifest ([string]$root))
        foreach ($entry in $missing) {
            if ($null -ne $entry) { $bySha[[string]$entry.Sha] = $entry }
        }
    }

    $changes = @()
    foreach ($value in $bySha.Values) { if ($null -ne $value) { $changes += $value } }
    if ($changes.Count -gt 0) {
        Download-MissingOrChangedFiles $changes $Config $StageRoot
        Install-StagedFilesTransactional $changes $GameRoots $StageRoot
    }
    foreach ($root in @($GameRoots)) {
        $remaining = @(Test-LocalPayload $Manifest ([string]$root))
        if ($remaining.Count -ne 0) { throw "Проверка ArzMarket после установки не пройдена: $root" }
    }
    return [int]$changes.Count
}

function Get-RemoteAntiAfkInfo($Config) {
    $prefix = ([string]$Config.AntiAfkRemotePath).Trim()
    if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = '#AntiAFK_' }

    $tree = @(Get-GitHubTree ([string]$Config.AntiAfkOwner) ([string]$Config.AntiAfkRepo) ([string]$Config.AntiAfkBranch))
    $files = @()

    foreach ($entry in $tree) {
        if ($null -eq $entry -or [string]$entry.type -ne 'blob') { continue }
        $remote = ([string]$entry.path).Replace('\','/').TrimStart([char]'/')
        if ($remote.Contains('/')) { continue }
        $name = [IO.Path]::GetFileName($remote)
        if ($name -notlike ($prefix + '*')) { continue }

        $extension = [IO.Path]::GetExtension($name).ToLowerInvariant()
        $local = if ($extension -eq '.cs') { ConvertTo-SafeRelativePath ('CLEO/' + $name) } else { ConvertTo-SafeRelativePath $name }

        try { [long]$size = [Convert]::ToInt64($entry.size, [Globalization.CultureInfo]::InvariantCulture) }
        catch { throw "Некорректный размер GitHub-файла Anti-AFK: $remote" }
        if ($size -lt 0) { throw "Некорректный размер GitHub-файла Anti-AFK: $remote" }
        $sha = ([string]$entry.sha).Trim().ToLowerInvariant()
        if ($sha -notmatch '^[a-f0-9]{40}$') { throw "Некорректный SHA GitHub-файла Anti-AFK: $remote" }

        $files += [pscustomobject]@{
            RemoteRelativePath = $remote
            LocalRelativePath = $local
            Sha = $sha
            Size = $size
            DownloadUrl = Get-GitHubRawUrl ([string]$Config.AntiAfkOwner) ([string]$Config.AntiAfkRepo) ([string]$Config.AntiAfkBranch) $remote
        }
    }

    if ($files.Count -eq 0) { throw "В GitHub не найден комплект Anti-AFK с префиксом $prefix" }
    return @($files | Sort-Object -Property LocalRelativePath)
}

function Update-AntiAfk($Info, [string[]]$GameRoots, [string]$StageRoot) {
    $items = @($Info)
    if ($items.Count -eq 0) { throw 'Комплект Anti-AFK пуст.' }

    $changed = @()
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $needsUpdate = $false
        foreach ($root in @($GameRoots)) {
            $target = Resolve-SafePayloadPath ([string]$root) ([string]$item.LocalRelativePath)
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { $needsUpdate = $true; break }
            $localFile = Get-Item -LiteralPath $target -ErrorAction Stop
            $expectedSize = [Convert]::ToInt64($item.Size, [Globalization.CultureInfo]::InvariantCulture)
            if ([long]$localFile.Length -ne $expectedSize -or (Get-GitBlobSha $target) -ne ([string]$item.Sha).ToLowerInvariant()) { $needsUpdate = $true; break }
        }
        if ($needsUpdate) { $changed += $item }
    }

    if ($changed.Count -eq 0) { return $false }

    foreach ($item in $changed) {
        $stage = Join-Path $StageRoot ([string]$item.Sha)
        if (-not (Test-Path -LiteralPath $stage -PathType Leaf)) {
            Write-PreparationProgress ("Загрузка: {0}" -f $item.LocalRelativePath)
            Invoke-GitHubRequest ([string]$item.DownloadUrl) $stage | Out-Null
        }
        if (-not (Test-Path -LiteralPath $stage -PathType Leaf)) { throw "Anti-AFK не скачан: $($item.RemoteRelativePath)" }
        $downloaded = Get-Item -LiteralPath $stage -ErrorAction Stop
        $expectedSize = [Convert]::ToInt64($item.Size, [Globalization.CultureInfo]::InvariantCulture)
        if ([long]$downloaded.Length -ne $expectedSize -or (Get-GitBlobSha $stage) -ne ([string]$item.Sha).ToLowerInvariant()) {
            throw "Проверка загруженного Anti-AFK не пройдена: $($item.RemoteRelativePath)"
        }
    }

    Install-StagedFilesTransactional $changed $GameRoots $StageRoot

    foreach ($root in @($GameRoots)) {
        foreach ($item in $items) {
            $target = Resolve-SafePayloadPath ([string]$root) ([string]$item.LocalRelativePath)
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Anti-AFK после установки отсутствует: $target" }
            $localFile = Get-Item -LiteralPath $target -ErrorAction Stop
            $expectedSize = [Convert]::ToInt64($item.Size, [Globalization.CultureInfo]::InvariantCulture)
            if ([long]$localFile.Length -ne $expectedSize -or (Get-GitBlobSha $target) -ne ([string]$item.Sha).ToLowerInvariant()) {
                throw "Проверка Anti-AFK после установки не пройдена: $target"
            }
        }
    }
    return $true
}

function Get-VersionFromInfoUrl([string]$Url, [string]$Title) {
    $response = Invoke-GitHubRequest $Url
    try { $info = $response.Content | ConvertFrom-Json -ErrorAction Stop } catch { throw "${Title}: повреждённый JSON версии." }
    $version = ([string]$info.latest).Trim()
    if ($version -notmatch '^\d+(?:[._-]\d+)*$') { throw "${Title}: неправильный формат версии '$version'." }
    return $version
}

function Get-OriginalArzMarketVersion($Config) { return Get-VersionFromInfoUrl $Config.OriginalArzMarketInfoUrl 'Оригинальный ArzMarket' }

function Get-CustomArzMarketVersion($Config) {
    try { return Get-VersionFromInfoUrl $Config.CustomArzMarketInfoUrl 'Ваш ArzMarket' }
    catch {
        $luaPath = [string]$Config.CustomLuaPath
        if (-not (Test-Path -LiteralPath $luaPath -PathType Leaf)) { throw }
        $text = (Get-TextDocument $luaPath).Text
        if ($text -match 'ARZ_UPDATE_VERSION\s*=\s*["'']([^"'']+)["'']') {
            $version = $matches[1].Trim()
            if ($version -match '^\d+(?:[._-]\d+)*$') { return $version }
        }
        throw
    }
}

function Compare-ArzMarketVersions([string]$Left, [string]$Right) {
    $leftParts = @($Left -split '[^0-9]+' | Where-Object { $_ -ne '' } | ForEach-Object { [long]$_ })
    $rightParts = @($Right -split '[^0-9]+' | Where-Object { $_ -ne '' } | ForEach-Object { [long]$_ })
    if ($leftParts.Count -eq 0 -or $rightParts.Count -eq 0) { throw 'Невозможно сравнить версии ArzMarket.' }
    $count = [Math]::Max($leftParts.Count, $rightParts.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $l = if ($i -lt $leftParts.Count) { $leftParts[$i] } else { 0 }
        $r = if ($i -lt $rightParts.Count) { $rightParts[$i] } else { 0 }
        if ($l -gt $r) { return 1 }
        if ($l -lt $r) { return -1 }
    }
    return 0
}

function Invoke-PrepareLaunch($Config) {
    $roots = @([string]$Config.MainGamePath, [string]$Config.DonorGamePath)
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) { throw "Папка Arizona не существует: $root" }
        if (-not (Test-Path -LiteralPath (Join-Path $root 'moonloader') -PathType Container)) { throw "Не найдена папка moonloader: $root" }
        Test-GameWriteAccess $root
    }
    if ([IO.Path]::GetFullPath($roots[0]).TrimEnd('\') -ieq [IO.Path]::GetFullPath($roots[1]).TrimEnd('\')) { throw 'MAIN и DONOR не могут использовать одну папку Arizona.' }

    Write-PreparationProgress 'Проверка версии оригинального ArzMarket...'
    $original = Get-OriginalArzMarketVersion $Config
    $custom = Get-CustomArzMarketVersion $Config
    if ((Compare-ArzMarketVersions $original $custom) -gt 0) { throw "ORIGINAL_NEWER|$original|$custom" }

    $stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('ArizonaLauncherPrepare_' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stageRoot) | Out-Null
    try {
        Write-PreparationProgress 'Проверка файлов ArzMarket...'
        $manifest = Get-RemotePayloadManifest $Config
        $payloadCount = Update-ArzMarketPayload $manifest $roots $Config $stageRoot

        Write-PreparationProgress 'Проверка Anti-AFK...'
        $antiInfo = Get-RemoteAntiAfkInfo $Config
        $antiUpdated = Update-AntiAfk $antiInfo $roots $stageRoot

        $proxyResult = $null
        if ($null -ne $Config.Proxy -and $Config.Proxy.Enabled -eq $true) {
            Write-PreparationProgress 'Проверка прокси ArzMarket...'
            $Config.Proxy | Add-Member -NotePropertyName Password -NotePropertyValue (Unprotect-LauncherSecret ([string]$Config.Proxy.PasswordProtected)) -Force
            $proxyResult = Test-ArzMarketProxyConnection $Config.Proxy
        }
        Write-PreparationProgress 'Подготовка завершена.' 'success'
        return [ordered]@{ Success=$true; OriginalVersion=$original; CustomVersion=$custom; PayloadUpdated=$payloadCount; AntiAfkUpdated=$antiUpdated; ProxyTest=$proxyResult }
    } finally {
        if (Test-Path -LiteralPath $stageRoot -PathType Container) { Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Prepare-Launch($Config) { return Invoke-PrepareLaunch $Config }

function Invoke-PreparationWorker {
    $result = $null
    try {
        if ([string]::IsNullOrWhiteSpace($PreparationConfigPath) -or -not (Test-Path -LiteralPath $PreparationConfigPath -PathType Leaf)) { throw 'Не найден файл параметров подготовки.' }
        $config = ((Get-TextDocument $PreparationConfigPath).Text) | ConvertFrom-Json -ErrorAction Stop
        $result = Prepare-Launch $config
    } catch {
        $message = [string]$_.Exception.Message
        $blocked = $message.StartsWith('ORIGINAL_NEWER|')
        $parts = $message.Split('|')
        $stack = [string]$_.ScriptStackTrace
        $fullError = [string]$_.Exception.ToString()
        $result = [ordered]@{ Success=$false; Error=$(if ($blocked) { 'Вышла новая версия оригинального ArzMarket' } else { $message }); OriginalNewer=$blocked; OriginalVersion=$(if ($blocked -and $parts.Count -gt 1) { $parts[1] } else { '' }); CustomVersion=$(if ($blocked -and $parts.Count -gt 2) { $parts[2] } else { '' }); DebugStack=$stack; DebugException=$fullError }
        Write-PreparationProgress ("Ошибка: {0}" -f $result.Error) 'error'
        if (-not [string]::IsNullOrWhiteSpace($stack)) { Write-DevLog ("Preparation worker stack: " + $stack) }
        Write-DevLog ("Preparation worker exception: " + $fullError)
    }
    try { Write-JsonAtomic $PreparationResultPath $result }
    catch { Write-DevLog "Preparation result write failed: $($_.Exception.ToString())" }
}

if ($PreparationWorker) {
    Invoke-PreparationWorker
    exit
}

if ($false) {
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Arizona - основной / донор'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(900, 816)
$form.MinimumSize = New-Object System.Drawing.Size(900, 760)
$form.MaximumSize = New-Object System.Drawing.Size(900, 760)
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

function Show-Help([bool]$Force = $false) {
    if (-not $Force -and (Test-Path -LiteralPath $HelpShownPath)) { return }

    $helpText = ''
    try {
        if (Test-Path -LiteralPath $HelpTextPath -PathType Leaf) {
            $helpText = (Get-TextDocument $HelpTextPath).Text
        } else {
            $helpText = "Файл help.txt не найден рядом с программой."
            Write-DevLog "Help file not found: $HelpTextPath"
        }
    } catch {
        $helpText = "Не удалось прочитать help.txt."
        Write-DevLog "Help read error: $($_.Exception.ToString())"
    }

    $manualHelp = $Force -eq $true
    $helpForm = New-Object System.Windows.Forms.Form
    $helpForm.Text = 'Помощь'
    $helpForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $helpForm.MaximizeBox = $false
    $helpForm.MinimizeBox = $false
    $helpForm.ControlBox = $false
    $helpForm.KeyPreview = $true
    $helpForm.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

    if ($manualHelp) {
        # Manual help from the ? button: compact, borderless and immediately closable.
        $helpForm.StartPosition = 'CenterParent'
        $helpForm.Size = New-Object System.Drawing.Size(760, 540)
        $helpForm.MinimumSize = New-Object System.Drawing.Size(620, 420)
        $helpForm.TopMost = $false
        $helpForm.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    } else {
        # First-run help: full screen and locked for 2 minutes.
        $helpForm.StartPosition = 'Manual'
        $helpForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $helpForm.Bounds = [System.Windows.Forms.Screen]::FromControl($form).Bounds
        $helpForm.TopMost = $true
        $helpForm.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    }

    $titlePanel = New-Object System.Windows.Forms.Panel
    $titlePanel.Dock = [System.Windows.Forms.DockStyle]::Top
    if ($manualHelp) {
        $titlePanel.Height = 50
        $titlePanel.Padding = New-Object System.Windows.Forms.Padding(18, 9, 8, 8)
    } else {
        $titlePanel.Height = 62
        $titlePanel.Padding = New-Object System.Windows.Forms.Padding(24, 14, 24, 8)
    }
    $titlePanel.BackColor = [System.Drawing.Color]::White
    $helpForm.Controls.Add($titlePanel)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $titleLabel.Text = 'Помощь'
    if ($manualHelp) {
        $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    } else {
        $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
    }
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $titlePanel.Controls.Add($titleLabel)

    $manualClose = $null
    if ($manualHelp) {
        $manualClose = New-Object System.Windows.Forms.Button
        $manualClose.Dock = [System.Windows.Forms.DockStyle]::Right
        $manualClose.Width = 44
        $manualClose.Text = '×'
        $manualClose.Font = New-Object System.Drawing.Font('Segoe UI', 18)
        $manualClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $manualClose.FlatAppearance.BorderSize = 0
        $manualClose.BackColor = [System.Drawing.Color]::White
        $manualClose.ForeColor = [System.Drawing.Color]::FromArgb(70,70,70)
        $manualClose.Cursor = [System.Windows.Forms.Cursors]::Hand
        $manualClose.TabStop = $false
        $manualClose.Add_Click({ $helpForm.Close() }.GetNewClosure())
        $titlePanel.Controls.Add($manualClose)
        $manualClose.BringToFront()

        $manualKeyHandler = {
            param($sender, $e)
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
                $helpForm.Close()
            }
        }.GetNewClosure()
        $helpForm.Add_KeyDown($manualKeyHandler)
    }

    $bottomPanel = $null
    $countdownLabel = $null
    $okHelp = $null
    $helpTimer = $null
    $helpState = $null

    if (-not $manualHelp) {
        $bottomPanel = New-Object System.Windows.Forms.Panel
        $bottomPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
        $bottomPanel.Height = 82
        $bottomPanel.Padding = New-Object System.Windows.Forms.Padding(24, 14, 24, 14)
        $bottomPanel.BackColor = [System.Drawing.Color]::White
        $helpForm.Controls.Add($bottomPanel)

        $countdownLabel = New-Object System.Windows.Forms.Label
        $countdownLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
        $countdownLabel.Text = 'Закрытие будет доступно через 02:00'
        $countdownLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11)
        $countdownLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $bottomPanel.Controls.Add($countdownLabel)

        $okHelp = New-Object System.Windows.Forms.Button
        $okHelp.Dock = [System.Windows.Forms.DockStyle]::Right
        $okHelp.Width = 220
        $okHelp.Text = 'Закрыть (02:00)'
        $okHelp.Enabled = $false
        $bottomPanel.Controls.Add($okHelp)
        $okHelp.BringToFront()
    }

    $helpBoxPanel = New-Object System.Windows.Forms.Panel
    $helpBoxPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    if ($manualHelp) {
        $helpBoxPanel.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 16)
    } else {
        $helpBoxPanel.Padding = New-Object System.Windows.Forms.Padding(24, 18, 24, 18)
    }
    $helpBoxPanel.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
    $helpForm.Controls.Add($helpBoxPanel)
    $helpBoxPanel.BringToFront()

    $helpBox = New-Object System.Windows.Forms.TextBox
    $helpBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $helpBox.Multiline = $true
    $helpBox.ReadOnly = $true
    $helpBox.ScrollBars = 'Vertical'
    $helpBox.BackColor = [System.Drawing.Color]::White
    $helpBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    if ($manualHelp) {
        $helpBox.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
    } else {
        $helpBox.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    }
    $helpBox.Text = [string]$helpText
    $helpBoxPanel.Controls.Add($helpBox)

    if (-not $manualHelp) {
        $helpState = @{
            Unlocked = $false
            Seconds = 120
        }

        $closeGuard = {
            param($sender, $e)
            if (-not $helpState.Unlocked) {
                $e.Cancel = $true
            }
        }.GetNewClosure()
        $helpForm.Add_FormClosing($closeGuard)

        $helpTimer = New-Object System.Windows.Forms.Timer
        $helpTimer.Interval = 1000
        $tick = {
            if ($helpState.Seconds -gt 0) {
                $helpState.Seconds--
            }

            if ($helpState.Seconds -le 0) {
                $helpState.Seconds = 0
                $helpState.Unlocked = $true
                $helpTimer.Stop()
                $countdownLabel.Text = 'Помощь прочитана. Окно можно закрыть.'
                $okHelp.Text = 'Закрыть помощь'
                $okHelp.Enabled = $true
                $helpForm.TopMost = $false
                return
            }

            $minutes = [math]::Floor($helpState.Seconds / 60)
            $seconds = $helpState.Seconds % 60
            $left = ('{0:00}:{1:00}' -f $minutes, $seconds)
            $countdownLabel.Text = "Закрытие будет доступно через $left"
            $okHelp.Text = "Закрыть ($left)"
        }.GetNewClosure()
        $helpTimer.Add_Tick($tick)

        $closeClick = {
            if ($helpState.Unlocked) {
                $helpForm.Close()
            }
        }.GetNewClosure()
        $okHelp.Add_Click($closeClick)
    }

    $shownHandler = {
        $helpForm.Activate()
        $helpBox.SelectionStart = 0
        $helpBox.SelectionLength = 0
        $helpBox.ScrollToCaret()
        if ($helpTimer -ne $null) { $helpTimer.Start() }
    }.GetNewClosure()
    $helpForm.Add_Shown($shownHandler)

    [void]$helpForm.ShowDialog($form)
    if ($helpTimer -ne $null) {
        $helpTimer.Stop()
        $helpTimer.Dispose()
    }

    if (-not $manualHelp) {
        try {
            [IO.File]::WriteAllText($HelpShownPath, (Get-Date).ToString('o'), [Text.UTF8Encoding]::new($false))
        } catch {
            Write-DevLog "Help shown flag write error: $($_.Exception.ToString())"
        }
    }
}
function New-AccountPanel([int]$X) {
    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = ''
    $group.Location = New-Object System.Drawing.Point($X, 10)
    $group.Size = New-Object System.Drawing.Size(425, 225)
    $form.Controls.Add($group)

    $mainFlag = New-Object System.Windows.Forms.CheckBox
    $mainFlag.Text = 'ЭТОТ АККАУНТ ЗАБАНЕН'
    $mainFlag.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $mainFlag.Location = New-Object System.Drawing.Point(14, 24)
    $mainFlag.AutoSize = $true
    $group.Controls.Add($mainFlag)

    $roleLabel = New-Object System.Windows.Forms.Label
    $roleLabel.Text = 'Донор'
    $roleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
    $roleLabel.Location = New-Object System.Drawing.Point(270, 24)
    $roleLabel.Size = New-Object System.Drawing.Size(100, 22)
    $roleLabel.TextAlign = 'MiddleRight'
    $roleLabel.Visible = $false
    $group.Controls.Add($roleLabel)

    function Add-PairField([string]$LabelText, [int]$Y, [string]$Default='', [bool]$Browse=$false) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $LabelText
        $label.Location = New-Object System.Drawing.Point(14, $Y)
        $label.Size = New-Object System.Drawing.Size(112, 22)
        $group.Controls.Add($label)

        $box = New-Object System.Windows.Forms.TextBox
        $box.Text = $Default
        $box.Location = New-Object System.Drawing.Point(126, ($Y - 2))
        $box.Size = New-Object System.Drawing.Size($(if($Browse){205}else{278}), 25)
        $group.Controls.Add($box)

        if ($Browse) {
            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = 'Обзор'
            $btn.Location = New-Object System.Drawing.Point(336, ($Y - 4))
            $btn.Size = New-Object System.Drawing.Size(68, 28)
            $btn.Add_Click({
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $dlg.Description = 'Выберите папку Arizona с gta_sa.exe'
                $currentPath = [string]$box.Text
                if (-not [string]::IsNullOrWhiteSpace($currentPath) -and (Test-Path -LiteralPath $currentPath -PathType Container -ErrorAction SilentlyContinue)) {
                    $dlg.SelectedPath = $currentPath
                }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $box.Text = $dlg.SelectedPath }
            }.GetNewClosure())
            $group.Controls.Add($btn)
        }
        return $box
    }

    $game = Add-PairField 'Папка Arizona:' 66 '' $true
    $nick = Add-PairField 'Ник:' 108 ''

    $serverLabel = New-Object System.Windows.Forms.Label
    $serverLabel.Text = 'Номер сервера:'
    $serverLabel.Location = New-Object System.Drawing.Point(14, 150)
    $serverLabel.Size = New-Object System.Drawing.Size(112, 22)
    $group.Controls.Add($serverLabel)

    $serverNumber = New-Object System.Windows.Forms.TextBox
    $serverNumber.Location = New-Object System.Drawing.Point(126, 148)
    $serverNumber.Size = New-Object System.Drawing.Size(58, 25)
    $serverNumber.MaxLength = 2
    $group.Controls.Add($serverNumber)

    $serverName = New-Object System.Windows.Forms.Label
    $serverName.Text = '1-33'
    $serverName.Location = New-Object System.Drawing.Point(194, 150)
    $serverName.Size = New-Object System.Drawing.Size(210, 22)
    $serverName.ForeColor = [System.Drawing.Color]::DimGray
    $group.Controls.Add($serverName)

    $pathWarning = New-Object System.Windows.Forms.Label
    $pathWarning.Text = ''
    $pathWarning.Location = New-Object System.Drawing.Point(14, 184)
    $pathWarning.Size = New-Object System.Drawing.Size(390, 30)
    $pathWarning.ForeColor = [System.Drawing.Color]::Firebrick
    $pathWarning.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    $pathWarning.Visible = $false
    $group.Controls.Add($pathWarning)

    $ui = @{
        Group=$group; MainFlag=$mainFlag; RoleLabel=$roleLabel;
        GameDir=$game; Nick=$nick; ServerNumber=$serverNumber; ServerNameLabel=$serverName; PathWarningLabel=$pathWarning; UserIdValue=''
    }

    $serverNumber.Add_TextChanged({ Update-ServerNameLabel $ui }.GetNewClosure())
    return $ui
}

function Update-ServerNameLabel($ui) {
    [int]$number = 0
    if ([int]::TryParse([string]$ui.ServerNumber.Text, [ref]$number) -and $ArizonaServers.ContainsKey($number)) {
        $info = $ArizonaServers[$number]
        $ui.ServerNameLabel.Text = [string]$info.Name
        $ui.ServerNameLabel.ForeColor = [System.Drawing.Color]::ForestGreen
    } else {
        $ui.ServerNameLabel.Text = 'Введите 1-33'
        $ui.ServerNameLabel.ForeColor = [System.Drawing.Color]::DimGray
    }
}

$uiA = New-AccountPanel 12
$uiB = New-AccountPanel 451

function Test-DuplicateGamePaths {
    $left = [string]$uiA.GameDir.Text
    $right = [string]$uiB.GameDir.Text
    if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) { return $false }
    try {
        $leftFull = [IO.Path]::GetFullPath($left.Trim()).TrimEnd('\')
        $rightFull = [IO.Path]::GetFullPath($right.Trim()).TrimEnd('\')
        return $leftFull -ieq $rightFull
    } catch {
        return $false
    }
}

function Update-DuplicateGamePathWarningUi {
    $same = Test-DuplicateGamePaths
    $text = 'Одинаковый путь. Сделайте копию игры и укажите другую папку.'
    foreach ($ui in @($uiA, $uiB)) {
        $ui.PathWarningLabel.Text = $(if ($same) { $text } else { '' })
        $ui.PathWarningLabel.Visible = $same
    }
}

$uiA.GameDir.Add_TextChanged({ Update-DuplicateGamePathWarningUi })
$uiB.GameDir.Add_TextChanged({ Update-DuplicateGamePathWarningUi })
Update-DuplicateGamePathWarningUi

$proxyGroup = New-Object System.Windows.Forms.GroupBox
$proxyGroup.Text = 'Другой IP только для ArzMarket'
$proxyGroup.Location = New-Object System.Drawing.Point(12, 244)
$proxyGroup.Size = New-Object System.Drawing.Size(864, 154)
$form.Controls.Add($proxyGroup)

$proxyEnabled = New-Object System.Windows.Forms.CheckBox
$proxyEnabled.Text = 'Использовать прокси для всех HTTP/HTTPS запросов ArzMarket'
$proxyEnabled.Location = New-Object System.Drawing.Point(14, 22)
$proxyEnabled.Size = New-Object System.Drawing.Size(430, 24)
$proxyGroup.Controls.Add($proxyEnabled)

$proxyTypeLabel = New-Object System.Windows.Forms.Label
$proxyTypeLabel.Text = 'Тип'
$proxyTypeLabel.Location = New-Object System.Drawing.Point(14, 51)
$proxyTypeLabel.Size = New-Object System.Drawing.Size(52, 20)
$proxyGroup.Controls.Add($proxyTypeLabel)

$proxyType = New-Object System.Windows.Forms.ComboBox
$proxyType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$proxyType.Location = New-Object System.Drawing.Point(14, 71)
$proxyType.Size = New-Object System.Drawing.Size(96, 25)
[void]$proxyType.Items.AddRange([object[]]$ProxyAllowedTypes)
$proxyType.SelectedItem = 'http'
$proxyGroup.Controls.Add($proxyType)

$proxyHostLabel = New-Object System.Windows.Forms.Label
$proxyHostLabel.Text = 'IP / Host или proxy URL'
$proxyHostLabel.Location = New-Object System.Drawing.Point(120, 51)
$proxyHostLabel.Size = New-Object System.Drawing.Size(190, 20)
$proxyGroup.Controls.Add($proxyHostLabel)

$proxyHost = New-Object System.Windows.Forms.TextBox
$proxyHost.Location = New-Object System.Drawing.Point(120, 71)
$proxyHost.Size = New-Object System.Drawing.Size(205, 25)
$proxyGroup.Controls.Add($proxyHost)

$proxyPortLabel = New-Object System.Windows.Forms.Label
$proxyPortLabel.Text = 'Порт'
$proxyPortLabel.Location = New-Object System.Drawing.Point(335, 51)
$proxyPortLabel.Size = New-Object System.Drawing.Size(60, 20)
$proxyGroup.Controls.Add($proxyPortLabel)

$proxyPort = New-Object System.Windows.Forms.TextBox
$proxyPort.Location = New-Object System.Drawing.Point(335, 71)
$proxyPort.Size = New-Object System.Drawing.Size(70, 25)
$proxyPort.MaxLength = 5
$proxyGroup.Controls.Add($proxyPort)

$proxyUsernameLabel = New-Object System.Windows.Forms.Label
$proxyUsernameLabel.Text = 'Логин'
$proxyUsernameLabel.Location = New-Object System.Drawing.Point(415, 51)
$proxyUsernameLabel.Size = New-Object System.Drawing.Size(70, 20)
$proxyGroup.Controls.Add($proxyUsernameLabel)

$proxyUsername = New-Object System.Windows.Forms.TextBox
$proxyUsername.Location = New-Object System.Drawing.Point(415, 71)
$proxyUsername.Size = New-Object System.Drawing.Size(180, 25)
$proxyGroup.Controls.Add($proxyUsername)

$proxyPasswordLabel = New-Object System.Windows.Forms.Label
$proxyPasswordLabel.Text = 'Пароль'
$proxyPasswordLabel.Location = New-Object System.Drawing.Point(605, 51)
$proxyPasswordLabel.Size = New-Object System.Drawing.Size(70, 20)
$proxyGroup.Controls.Add($proxyPasswordLabel)

$proxyPassword = New-Object System.Windows.Forms.TextBox
$proxyPassword.Location = New-Object System.Drawing.Point(605, 71)
$proxyPassword.Size = New-Object System.Drawing.Size(180, 25)
$proxyPassword.UseSystemPasswordChar = $true
$proxyGroup.Controls.Add($proxyPassword)

$proxyTestButton = New-Object System.Windows.Forms.Button
$proxyTestButton.Text = 'Проверить прокси'
$proxyTestButton.Location = New-Object System.Drawing.Point(14, 108)
$proxyTestButton.Size = New-Object System.Drawing.Size(150, 30)
$proxyGroup.Controls.Add($proxyTestButton)

$proxyDeleteButton = New-Object System.Windows.Forms.Button
$proxyDeleteButton.Text = 'Удалить proxy'
$proxyDeleteButton.Location = New-Object System.Drawing.Point(174, 108)
$proxyDeleteButton.Size = New-Object System.Drawing.Size(120, 30)
$proxyGroup.Controls.Add($proxyDeleteButton)

$proxyTestStatus = New-Object System.Windows.Forms.Label
$proxyTestStatus.Text = 'Не проверено'
$proxyTestStatus.Location = New-Object System.Drawing.Point(306, 113)
$proxyTestStatus.Size = New-Object System.Drawing.Size(530, 24)
$proxyTestStatus.ForeColor = [System.Drawing.Color]::DimGray
$proxyGroup.Controls.Add($proxyTestStatus)

function Set-ProxyTestStatus([string]$Text, $Color) {
    $proxyTestStatus.Text = $Text
    if ($null -ne $Color) { $proxyTestStatus.ForeColor = $Color }
}

function Update-ProxyUiEnabled {
    $enabled = $proxyEnabled.Checked -eq $true
    foreach ($control in @($proxyType, $proxyHost, $proxyPort, $proxyUsername, $proxyPassword, $proxyTestButton)) {
        $control.Enabled = $enabled
    }
    if (-not $enabled) {
        Set-ProxyTestStatus 'Прокси выключен. ArzMarket использует обычное соединение.' ([System.Drawing.Color]::DimGray)
    } elseif ($proxyTestStatus.Text -like 'Прокси выключен*') {
        Set-ProxyTestStatus 'Не проверено' ([System.Drawing.Color]::DimGray)
    }
}

function Reset-ProxyTestStatus {
    if ($proxyEnabled.Checked) {
        Set-ProxyTestStatus 'Не проверено' ([System.Drawing.Color]::DimGray)
    }
}

$proxyEnabled.Add_CheckedChanged({
    Update-ProxyUiEnabled
    Reset-ProxyTestStatus
    Save-UiSettings
})
$proxyType.Add_SelectedIndexChanged({ Reset-ProxyTestStatus; Save-UiSettings })
$proxyHost.Add_TextChanged({ Reset-ProxyTestStatus; Save-UiSettings })
$proxyPort.Add_TextChanged({ Reset-ProxyTestStatus; Save-UiSettings })
$proxyUsername.Add_TextChanged({ Reset-ProxyTestStatus; Save-UiSettings })
$proxyPassword.Add_TextChanged({ Reset-ProxyTestStatus; Save-UiSettings })

$proxyDeleteButton.Add_Click({
    $proxyEnabled.Checked = $false
    $proxyType.SelectedItem = 'http'
    $proxyHost.Clear()
    $proxyPort.Clear()
    $proxyUsername.Clear()
    $proxyPassword.Clear()
    Set-ProxyTestStatus 'Прокси удалён.' ([System.Drawing.Color]::DimGray)
    Save-UiSettings
})

$proxyTestButton.Add_Click({
    $proxyTestButton.Enabled = $false
    $oldCursor = $form.UseWaitCursor
    $form.UseWaitCursor = $true
    try {
        Set-ProxyTestStatus 'Проверяю обычный IP и IP прокси...' ([System.Drawing.Color]::DarkOrange)
        [System.Windows.Forms.Application]::DoEvents()
        $cfg = Get-ProxyUiConfig
        $result = Test-ArzMarketProxyConnection $cfg
        Set-ProxyTestStatus ("Готово. Обычный IP: {0} | ArzMarket IP: {1} | {2} ms" -f $result.DirectIp, $result.ProxyIp, $result.LatencyMs) ([System.Drawing.Color]::ForestGreen)
        Write-Status ("Прокси проверен. ArzMarket IP: {0}" -f $result.ProxyIp)
        Save-UiSettings
    } catch {
        Set-ProxyTestStatus ("Ошибка: {0}" -f $_.Exception.Message) ([System.Drawing.Color]::Firebrick)
        Write-DevLog "Proxy test failed: $($_.Exception.Message)"
        Write-Status ("Прокси не прошел проверку: {0}" -f $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Ошибка прокси', 'OK', 'Error') | Out-Null
    } finally {
        $form.UseWaitCursor = $oldCursor
        Update-ProxyUiEnabled
    }
})

Update-ProxyUiEnabled

$helpButton = New-Object System.Windows.Forms.Button
$helpButton.Text = '?'
$helpButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$helpButton.Location = New-Object System.Drawing.Point(838, 17)
$helpButton.Size = New-Object System.Drawing.Size(38, 38)
$helpButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$helpButton.FlatAppearance.BorderSize = 0
$helpButton.BackColor = [System.Drawing.Color]::White
$helpButton.ForeColor = [System.Drawing.Color]::FromArgb(45, 95, 180)
$helpButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$helpButton.TabStop = $false
$helpButton.Add_Click({ Show-Help $true })
$form.Controls.Add($helpButton)
$helpButton.BringToFront()

$helpTip = New-Object System.Windows.Forms.ToolTip
$helpTip.SetToolTip($helpButton, 'Открыть помощь')

$mainA = $uiA.MainFlag
$mainB = $uiB.MainFlag
$mainA.Checked = $true

$script:RoleGuard = $false
function Update-RoleUi {
    if ($mainA.Checked) {
        $uiA.Group.Text = 'Основной аккаунт'
        $uiA.RoleLabel.Text = 'Основной'
        $uiA.RoleLabel.ForeColor = [System.Drawing.Color]::ForestGreen
        $uiB.Group.Text = 'Донорский аккаунт'
        $uiB.RoleLabel.Text = 'Донор'
        $uiB.RoleLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    } else {
        $uiB.Group.Text = 'Основной аккаунт'
        $uiB.RoleLabel.Text = 'Основной'
        $uiB.RoleLabel.ForeColor = [System.Drawing.Color]::ForestGreen
        $uiA.Group.Text = 'Донорский аккаунт'
        $uiA.RoleLabel.Text = 'Донор'
        $uiA.RoleLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }
}
$mainA.Add_CheckedChanged({
    if ($script:RoleGuard) { return }
    $script:RoleGuard = $true
    if ($mainA.Checked) { $mainB.Checked = $false } elseif (-not $mainB.Checked) { $mainB.Checked = $true }
    $script:RoleGuard = $false
    Update-RoleUi
})
$mainB.Add_CheckedChanged({
    if ($script:RoleGuard) { return }
    $script:RoleGuard = $true
    if ($mainB.Checked) { $mainA.Checked = $false } elseif (-not $mainA.Checked) { $mainA.Checked = $true }
    $script:RoleGuard = $false
    Update-RoleUi
})
Update-RoleUi

# Save user-entered values immediately, not only after a successful launch.
$uiA.GameDir.Add_TextChanged({ Save-UiSettings })
$uiA.Nick.Add_TextChanged({ Save-UiSettings })
$uiA.ServerNumber.Add_TextChanged({ Save-UiSettings })
$uiB.GameDir.Add_TextChanged({ Save-UiSettings })
$uiB.Nick.Add_TextChanged({ Save-UiSettings })
$uiB.ServerNumber.Add_TextChanged({ Save-UiSettings })
$mainA.Add_CheckedChanged({ Save-UiSettings })
$mainB.Add_CheckedChanged({ Save-UiSettings })
$form.Add_FormClosing({
    Save-UiSettings
    $PairRuntime.ProfileKey = ''
    $profileKeyBox.Clear()
    try {
        if ($null -ne $PairRuntime.Main) { Write-LauncherHeartbeat $PairRuntime.Main $false }
        if ($null -ne $PairRuntime.Donor) { Write-LauncherHeartbeat $PairRuntime.Donor $false }
    } catch {}
})

$profileKeyLabel = New-Object System.Windows.Forms.Label
$profileKeyLabel.Text = 'Ключ профиля из Telegram (необязательно)'
$profileKeyLabel.Location = New-Object System.Drawing.Point(14, 410)
$profileKeyLabel.Size = New-Object System.Drawing.Size(420, 22)
$form.Controls.Add($profileKeyLabel)
$profileKeyBox = New-Object System.Windows.Forms.TextBox
$profileKeyBox.Location = New-Object System.Drawing.Point(12, 434)
$profileKeyBox.Size = New-Object System.Drawing.Size(864, 24)
$profileKeyBox.UseSystemPasswordChar = $true
$profileKeyBox.MaxLength = 255
$form.Controls.Add($profileKeyBox)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = 'ЗАПУСТИТЬ'
$launchButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
$launchButton.Location = New-Object System.Drawing.Point(12, 466)
$launchButton.Size = New-Object System.Drawing.Size(425, 42)
$launchButton.BackColor = [System.Drawing.Color]::FromArgb(33,150,83)
$launchButton.ForeColor = [System.Drawing.Color]::White
$launchButton.FlatStyle = 'Flat'
$form.Controls.Add($launchButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = 'Остановить'
$stopButton.Location = New-Object System.Drawing.Point(728, 466)
$stopButton.Size = New-Object System.Drawing.Size(148, 42)
$form.Controls.Add($stopButton)

$stateMain = New-Object System.Windows.Forms.Label
$stateMain.Text = 'Основной: нет данных'
$stateMain.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
$stateMain.Location = New-Object System.Drawing.Point(14, 520)
$stateMain.Size = New-Object System.Drawing.Size(410, 22)
$stateMain.Visible = $false
$form.Controls.Add($stateMain)

$stateDonor = New-Object System.Windows.Forms.Label
$stateDonor.Text = 'Донор: нет данных'
$stateDonor.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
$stateDonor.Location = New-Object System.Drawing.Point(451, 520)
$stateDonor.Size = New-Object System.Drawing.Size(410, 22)
$stateDonor.Visible = $false
$form.Controls.Add($stateDonor)

$phaseLabel = New-Object System.Windows.Forms.Label
$phaseLabel.Text = 'Связка: не запущена'
$phaseLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
$phaseLabel.Location = New-Object System.Drawing.Point(14, 548)
$phaseLabel.Size = New-Object System.Drawing.Size(847, 22)
$phaseLabel.Visible = $false
$form.Controls.Add($phaseLabel)

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Location = New-Object System.Drawing.Point(12, 582)
$statusBox.Size = New-Object System.Drawing.Size(864, 180)
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = 'Vertical'
$statusBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($statusBox)

$launchButton.Add_Click({
    try { Start-PairWorkflow }
    catch {
        Write-DevLog "Launch error: $($_.Exception.ToString())"
        Write-Status "Ошибка: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Ошибка запуска', 'OK', 'Error') | Out-Null
    }
})
$stopButton.Add_Click({ Stop-PairWorkflow })
}

[xml]$LauncherXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Arizona - Основной / Донор" Width="900" Height="720"
        MinWidth="900" MaxWidth="900" MinHeight="700" MaxHeight="900"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="NoResize"
        Background="#11161B" Foreground="#F2F5F7" FontFamily="Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="Surface" Color="#181E24"/>
    <SolidColorBrush x:Key="SurfaceHover" Color="#20272E"/>
    <SolidColorBrush x:Key="Border" Color="#2A323A"/>
    <SolidColorBrush x:Key="Secondary" Color="#8E99A5"/>
    <SolidColorBrush x:Key="Accent" Color="#35D07F"/>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#11161B"/><Setter Property="Foreground" Value="#F2F5F7"/>
      <Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="9,6"/><Setter Property="CaretBrush" Value="#35D07F"/>
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="Background" Value="#11161B"/><Setter Property="Foreground" Value="#F2F5F7"/>
      <Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="9,6"/><Setter Property="CaretBrush" Value="#35D07F"/>
    </Style>
    <Style x:Key="DarkComboBoxItem" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#F2F5F7"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Padding" Value="10,7"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem"><Border x:Name="ItemBorder" Background="{TemplateBinding Background}" CornerRadius="4" Margin="3,1"><ContentPresenter Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="#283139"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="#24543D"/><Setter Property="Foreground" Value="#F2FFF8"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="#59636D"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="DarkComboToggle" TargetType="ToggleButton">
      <Setter Property="Focusable" Value="False"/><Setter Property="ClickMode" Value="Press"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton"><Border x:Name="ToggleBorder" Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="5"><Grid><Path Width="8" Height="5" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0" Fill="#8E99A5" Data="M 0 0 L 4 4 L 8 0 Z"/></Grid></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ToggleBorder" Property="Background" Value="#20272E"/><Setter TargetName="ToggleBorder" Property="BorderBrush" Value="#3A454F"/></Trigger><Trigger Property="IsChecked" Value="True"><Setter TargetName="ToggleBorder" Property="BorderBrush" Value="#35D07F"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="#11161B"/><Setter Property="Foreground" Value="#F2F5F7"/>
      <Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="Padding" Value="9,5"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource DarkComboBoxItem}"/>
      <Setter Property="ScrollViewer.CanContentScroll" Value="True"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox"><Grid>
        <ToggleButton x:Name="DropDownToggle" Style="{StaticResource DarkComboToggle}" IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}"/>
        <ContentPresenter Margin="10,0,30,0" VerticalAlignment="Center" HorizontalAlignment="Left" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
        <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
          <Border Background="#181E24" BorderBrush="#3A454F" BorderThickness="1" CornerRadius="6" Margin="0,3,0,0" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
            <ScrollViewer MaxHeight="230" Padding="2" VerticalScrollBarVisibility="Auto"><ItemsPresenter/></ScrollViewer>
          </Border>
        </Popup>
      </Grid><ControlTemplate.Triggers><Trigger Property="HasItems" Value="False"><Setter TargetName="PART_Popup" Property="MinHeight" Value="28"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="#59636D"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#F2F5F7"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Border x:Name="CheckBorder" Width="16" Height="16" Background="#11161B" BorderBrush="#46515B" BorderThickness="1" CornerRadius="4" VerticalAlignment="Center">
            <Path x:Name="CheckMark" Data="M 3 8 L 7 12 L 14 3" Stroke="#07140D" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Collapsed"/>
          </Border>
          <ContentPresenter Grid.Column="1" Margin="8,0,0,0" VerticalAlignment="Center" RecognizesAccessKey="True"/>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="CheckBorder" Property="Background" Value="#35D07F"/><Setter TargetName="CheckBorder" Property="BorderBrush" Value="#35D07F"/><Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="CheckBorder" Property="BorderBrush" Value="#8E99A5"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="DarkButton" TargetType="Button">
      <Setter Property="Background" Value="#20272E"/><Setter Property="Foreground" Value="#F2F5F7"/>
      <Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,8"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#283139"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource DarkButton}"><Setter Property="Background" Value="#35D07F"/><Setter Property="Foreground" Value="#07140D"/><Setter Property="BorderBrush" Value="#35D07F"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="#181E24"/><Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="10"/><Setter Property="Padding" Value="16"/></Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="52"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <Border x:Name="TitleBar" Grid.Row="0" Background="#11161B" BorderBrush="#2A323A" BorderThickness="0,0,0,1">
      <Grid Margin="18,0,10,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center"><TextBlock Text="Arizona" FontSize="17" FontWeight="SemiBold"/><TextBlock Text="Основной / Донор" FontSize="11" Foreground="#8E99A5"/></StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="HelpButton" Content="?" Width="42" Height="34" Style="{StaticResource DarkButton}" BorderThickness="0" FontWeight="SemiBold" ToolTip="Открыть обучение"/>
          <Button x:Name="MinimizeButton" Content="-" Width="42" Height="34" Margin="4,0,0,0" Style="{StaticResource DarkButton}" BorderThickness="0"/>
          <Button x:Name="CloseButton" Content="×" Width="42" Height="34" Margin="4,0,0,0" Style="{StaticResource DarkButton}" BorderThickness="0" FontSize="17"/>
        </StackPanel>
      </Grid>
    </Border>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <Grid x:Name="BodyGrid" Margin="18,12,18,14">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Grid x:Name="SettingsContent" Grid.Row="0" Grid.RowSpan="2">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <Border x:Name="MainBlock" Grid.Row="0" Style="{StaticResource Card}">
            <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
              <TextBlock Text="Основное" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,12"/>
              <Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/></Grid.ColumnDefinitions>
                <Border Grid.Column="0" Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="7" Padding="13"><StackPanel>
                  <TextBlock x:Name="HeadingA" Text="Основной" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,9"/>
                  <TextBlock Text="Папка Arizona" Foreground="#8E99A5" FontSize="11"/>
                  <Grid Margin="0,4,0,8"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="38"/></Grid.ColumnDefinitions><TextBox x:Name="GameDirA" Height="31"/><Button x:Name="BrowseA" Grid.Column="1" Content="…" Margin="6,0,0,0" Style="{StaticResource DarkButton}" Padding="0"/></Grid>
                  <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition Width="128"/></Grid.ColumnDefinitions>
                    <StackPanel><TextBlock Text="Ник" Foreground="#8E99A5" FontSize="11"/><TextBox x:Name="NickA" Height="31" Margin="0,4,0,0"/></StackPanel>
                    <StackPanel Grid.Column="2"><TextBlock Text="Сервер" Foreground="#8E99A5" FontSize="11"/><Grid Margin="0,4,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition/></Grid.ColumnDefinitions><TextBox x:Name="ServerA" Height="31" MaxLength="2" Padding="7,6"/><TextBlock x:Name="ServerNameA" Grid.Column="1" Text="1-33" Foreground="#8E99A5" VerticalAlignment="Center" Margin="8,0,0,0" TextTrimming="CharacterEllipsis"/></Grid></StackPanel>
                  </Grid>
                  <CheckBox x:Name="BannedA" Content="Аккаунт забанен" Margin="0,10,0,0"/>
                  <TextBlock x:Name="PathWarningA" Foreground="#FF6464" FontSize="11" Margin="0,7,0,0" Visibility="Collapsed" TextWrapping="Wrap"/>
                </StackPanel></Border>
                <Border Grid.Column="2" Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="7" Padding="13"><StackPanel>
                  <TextBlock x:Name="HeadingB" Text="Донор" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,9"/>
                  <TextBlock Text="Папка Arizona" Foreground="#8E99A5" FontSize="11"/>
                  <Grid Margin="0,4,0,8"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="38"/></Grid.ColumnDefinitions><TextBox x:Name="GameDirB" Height="31"/><Button x:Name="BrowseB" Grid.Column="1" Content="…" Margin="6,0,0,0" Style="{StaticResource DarkButton}" Padding="0"/></Grid>
                  <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition Width="128"/></Grid.ColumnDefinitions>
                    <StackPanel><TextBlock Text="Ник" Foreground="#8E99A5" FontSize="11"/><TextBox x:Name="NickB" Height="31" Margin="0,4,0,0"/></StackPanel>
                    <StackPanel Grid.Column="2"><TextBlock Text="Сервер" Foreground="#8E99A5" FontSize="11"/><Grid Margin="0,4,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="40"/><ColumnDefinition/></Grid.ColumnDefinitions><TextBox x:Name="ServerB" Height="31" MaxLength="2" Padding="7,6"/><TextBlock x:Name="ServerNameB" Grid.Column="1" Text="1-33" Foreground="#8E99A5" VerticalAlignment="Center" Margin="8,0,0,0" TextTrimming="CharacterEllipsis"/></Grid></StackPanel>
                  </Grid>
                  <CheckBox x:Name="BannedB" Content="Аккаунт забанен" Margin="0,10,0,0"/>
                  <TextBlock x:Name="PathWarningB" Foreground="#FF6464" FontSize="11" Margin="0,7,0,0" Visibility="Collapsed" TextWrapping="Wrap"/>
                </StackPanel></Border>
              </Grid>
              <Border Grid.Row="2" Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="7" Padding="12,9" Margin="0,10,0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal"><Ellipse x:Name="AntiDot" Width="8" Height="8" Fill="#8E99A5" Margin="0,0,8,0"/><TextBlock Text="Anti-AFK  "/><TextBlock x:Name="AntiStatus" Text="Не проверено" Foreground="#8E99A5"/></StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal"><Ellipse x:Name="PayloadDot" Width="8" Height="8" Fill="#8E99A5" Margin="0,0,8,0"/><TextBlock Text="ArzMarket  "/><TextBlock x:Name="PayloadStatus" Text="Не проверено" Foreground="#8E99A5"/></StackPanel>
                <StackPanel Grid.Column="2" Orientation="Horizontal"><Ellipse x:Name="OriginalDot" Width="8" Height="8" Fill="#8E99A5" Margin="0,0,8,0"/><TextBlock Text="Original  "/><TextBlock x:Name="OriginalStatus" Text="Не проверено" Foreground="#8E99A5"/></StackPanel>
              </Grid></Border>
              <Border Grid.Row="3" Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="7" Padding="12,10" Margin="0,10,0,0"><StackPanel>
                <CheckBox x:Name="ProxyEnabled" Content="Использовать прокси для ArzMarket"/>
                <Grid x:Name="ProxyDetails" Visibility="Collapsed" Margin="0,9,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="90"/><ColumnDefinition/><ColumnDefinition Width="78"/><ColumnDefinition Width="145"/><ColumnDefinition Width="145"/><ColumnDefinition Width="132"/></Grid.ColumnDefinitions>
                  <StackPanel><TextBlock Text="Тип" Foreground="#8E99A5" FontSize="11" Margin="1,0,0,4"/><ComboBox x:Name="ProxyType" Height="31"/></StackPanel>
                  <StackPanel Grid.Column="1" Margin="8,0,0,0"><TextBlock Text="Host/IP" Foreground="#8E99A5" FontSize="11" Margin="1,0,0,4"/><TextBox x:Name="ProxyHost" Height="31"/></StackPanel>
                  <StackPanel Grid.Column="2" Margin="8,0,0,0"><TextBlock Text="Порт" Foreground="#8E99A5" FontSize="11" Margin="1,0,0,4"/><TextBox x:Name="ProxyPort" Height="31" MaxLength="5"/></StackPanel>
                  <StackPanel Grid.Column="3" Margin="8,0,0,0"><TextBlock Text="Логин" Foreground="#8E99A5" FontSize="11" Margin="1,0,0,4"/><TextBox x:Name="ProxyUsername" Height="31"/></StackPanel>
                  <StackPanel Grid.Column="4" Margin="8,0,0,0"><TextBlock Text="Пароль" Foreground="#8E99A5" FontSize="11" Margin="1,0,0,4"/><PasswordBox x:Name="ProxyPassword" Height="31"/></StackPanel>
                  <Button x:Name="ProxyTestButton" Grid.Column="5" Content="Проверить прокси" Height="31" Margin="8,19,0,0" Style="{StaticResource DarkButton}" Padding="7,4"/>
                </Grid>
                <TextBlock x:Name="ProxyTestStatus" Text="Прокси выключен" Foreground="#8E99A5" FontSize="11" Margin="0,7,0,0"/>
              </StackPanel></Border>
              <Grid Grid.Row="4" Margin="0,10,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="120"/><ColumnDefinition/></Grid.ColumnDefinitions>
                <TextBlock Text="Ключ Telegram" Foreground="#8E99A5" VerticalAlignment="Center"/>
                <Grid Grid.Column="1"><PasswordBox x:Name="ProfileKey" Height="34"/><TextBlock x:Name="ProfilePlaceholder" Text="Необязательно" Foreground="#8E99A5" Margin="10,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/></Grid>
              </Grid>
            </Grid>
          </Border>
          <Grid Grid.Row="1" Margin="0,10,0,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition/></Grid.ColumnDefinitions>
            <Button x:Name="LaunchButton" Content="Запустить" Height="38" Style="{StaticResource AccentButton}"/>
            <Button x:Name="StopButton" Grid.Column="2" Content="Остановить" Height="38" Style="{StaticResource DarkButton}" IsEnabled="False"/>
            <Button x:Name="CheckFilesButton" Grid.Column="4" Content="Проверить файлы" Height="38" Style="{StaticResource DarkButton}"/>
          </Grid>
        </Grid>
        <Border x:Name="LogPanel" Grid.Row="2" Style="{StaticResource Card}" Margin="0,10,0,0" Padding="12">
          <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition x:Name="LogContentRow" Height="72"/></Grid.RowDefinitions>
            <Grid><TextBlock Text="Логи / События" FontWeight="SemiBold"/><Button x:Name="DetailsButton" Content="Подробнее" HorizontalAlignment="Right" Style="{StaticResource DarkButton}" Padding="10,3"/></Grid>
            <TextBox x:Name="StatusBox" Grid.Row="1" Margin="0,8,0,0" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" BorderThickness="0" Background="#11161B" FontFamily="Consolas" FontSize="11"/>
          </Grid>
        </Border>
        <StackPanel Grid.Row="3" Margin="2,8,0,0"><TextBlock x:Name="PhaseLabel" Text="Связка: не запущена" Foreground="#8E99A5" FontSize="11"/><TextBlock x:Name="StateMain" Visibility="Collapsed"/><TextBlock x:Name="StateDonor" Visibility="Collapsed"/></StackPanel>
        <Grid x:Name="LoadingOverlay" Grid.Row="0" Grid.RowSpan="2" Background="#F011161B" Visibility="Collapsed">
          <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
            <Ellipse Width="46" Height="46" Stroke="#35D07F" StrokeThickness="4" StrokeDashArray="2,3" RenderTransformOrigin="0.5,0.5"><Ellipse.RenderTransform><RotateTransform x:Name="SpinnerRotate"/></Ellipse.RenderTransform><Ellipse.Triggers><EventTrigger RoutedEvent="Loaded"><BeginStoryboard><Storyboard RepeatBehavior="Forever"><DoubleAnimation Storyboard.TargetName="SpinnerRotate" Storyboard.TargetProperty="Angle" From="0" To="360" Duration="0:0:0.8"/></Storyboard></BeginStoryboard></EventTrigger></Ellipse.Triggers></Ellipse>
            <TextBlock x:Name="LoadingTitle" Text="Подготовка запуска" FontSize="16" FontWeight="SemiBold" Margin="0,16,0,0" HorizontalAlignment="Center"/>
            <TextBlock x:Name="LoadingText" Text="Проверка файлов…" Foreground="#8E99A5" Margin="0,6,0,0" HorizontalAlignment="Center"/>
          </StackPanel>
        </Grid>
      </Grid>
    </ScrollViewer>
  </Grid>
</Window>
'@

$xamlReader = New-Object System.Xml.XmlNodeReader $LauncherXaml
$form = [Windows.Markup.XamlReader]::Load($xamlReader)
function Find-Control([string]$Name) { return $form.FindName($Name) }

$titleBar = Find-Control 'TitleBar'; $helpButton = Find-Control 'HelpButton'; $minimizeButton = Find-Control 'MinimizeButton'; $closeButton = Find-Control 'CloseButton'
$settingsContent = Find-Control 'SettingsContent'; $loadingOverlay = Find-Control 'LoadingOverlay'; $loadingTitle = Find-Control 'LoadingTitle'; $loadingText = Find-Control 'LoadingText'
$antiDot = Find-Control 'AntiDot'; $antiStatus = Find-Control 'AntiStatus'; $payloadDot = Find-Control 'PayloadDot'; $payloadStatus = Find-Control 'PayloadStatus'; $originalDot = Find-Control 'OriginalDot'; $originalStatus = Find-Control 'OriginalStatus'
$proxyEnabled = Find-Control 'ProxyEnabled'; $proxyDetails = Find-Control 'ProxyDetails'; $proxyType = Find-Control 'ProxyType'; $proxyHost = Find-Control 'ProxyHost'; $proxyPort = Find-Control 'ProxyPort'; $proxyUsername = Find-Control 'ProxyUsername'; $proxyPassword = Find-Control 'ProxyPassword'; $proxyTestButton = Find-Control 'ProxyTestButton'; $proxyTestStatus = Find-Control 'ProxyTestStatus'
$profileKeyBox = Find-Control 'ProfileKey'; $profilePlaceholder = Find-Control 'ProfilePlaceholder'; $launchButton = Find-Control 'LaunchButton'; $stopButton = Find-Control 'StopButton'; $checkFilesButton = Find-Control 'CheckFilesButton'; $detailsButton = Find-Control 'DetailsButton'; $logPanel = Find-Control 'LogPanel'; $logContentRow = Find-Control 'LogContentRow'; $statusBox = Find-Control 'StatusBox'; $phaseLabel = Find-Control 'PhaseLabel'; $stateMain = Find-Control 'StateMain'; $stateDonor = Find-Control 'StateDonor'
foreach ($type in $ProxyAllowedTypes) { [void]$proxyType.Items.Add($type) }; $proxyType.SelectedItem = 'http'

$uiA = @{ Group=(Find-Control 'HeadingA'); MainFlag=(Find-Control 'BannedA'); RoleLabel=(Find-Control 'HeadingA'); GameDir=(Find-Control 'GameDirA'); Nick=(Find-Control 'NickA'); ServerNumber=(Find-Control 'ServerA'); ServerNameLabel=(Find-Control 'ServerNameA'); PathWarningLabel=(Find-Control 'PathWarningA'); UserIdValue='' }
$uiB = @{ Group=(Find-Control 'HeadingB'); MainFlag=(Find-Control 'BannedB'); RoleLabel=(Find-Control 'HeadingB'); GameDir=(Find-Control 'GameDirB'); Nick=(Find-Control 'NickB'); ServerNumber=(Find-Control 'ServerB'); ServerNameLabel=(Find-Control 'ServerNameB'); PathWarningLabel=(Find-Control 'PathWarningB'); UserIdValue='' }
$mainA = $uiA.MainFlag; $mainB = $uiB.MainFlag; $mainA.IsChecked = $true

function Set-Indicator($Dot, $Label, [string]$Text, [string]$Color) { $Dot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString($Color); $Label.Text = $Text; $Label.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($Color) }
function ConvertTo-WpfBrush($Color) {
    if ($null -eq $Color) { return $null }
    if ($Color -is [Windows.Media.Brush]) { return $Color }
    if ($Color -is [System.Drawing.Color]) {
        $mediaColor = [Windows.Media.Color]::FromArgb([byte]$Color.A, [byte]$Color.R, [byte]$Color.G, [byte]$Color.B)
        return [Windows.Media.SolidColorBrush]::new($mediaColor)
    }
    if ($Color -is [string]) {
        return [Windows.Media.BrushConverter]::new().ConvertFromString([string]$Color)
    }
    throw "Неподдерживаемый тип цвета: $($Color.GetType().FullName)"
}
function Set-ProxyTestStatus([string]$Text, $Color) {
    $proxyTestStatus.Text = $Text
    if ($null -ne $Color) { $proxyTestStatus.Foreground = ConvertTo-WpfBrush $Color }
}
function Update-ProxyUiEnabled { $proxyDetails.Visibility = if ($proxyEnabled.IsChecked) { 'Visible' } else { 'Collapsed' }; if (-not $proxyEnabled.IsChecked) { Set-ProxyTestStatus 'Прокси выключен' ([Windows.Media.Brushes]::Gray) } }
function Reset-ProxyTestStatus { if ($proxyEnabled.IsChecked) { Set-ProxyTestStatus 'Будет проверен перед запуском' ([Windows.Media.Brushes]::Gray) } }
function Update-ServerNameLabel($ui) { [int]$number=0; if ([int]::TryParse([string]$ui.ServerNumber.Text,[ref]$number) -and $ArizonaServers.ContainsKey($number)) { $ui.ServerNameLabel.Text=[string]$ArizonaServers[$number].Name; $ui.ServerNameLabel.Foreground=[Windows.Media.Brushes]::LightGreen } else { $ui.ServerNameLabel.Text='1-33'; $ui.ServerNameLabel.Foreground=[Windows.Media.Brushes]::Gray } }
function Test-DuplicateGamePaths { $left=[string]$uiA.GameDir.Text; $right=[string]$uiB.GameDir.Text; if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) { return $false }; try { return [IO.Path]::GetFullPath($left).TrimEnd('\') -ieq [IO.Path]::GetFullPath($right).TrimEnd('\') } catch { return $false } }
function Update-DuplicateGamePathWarningUi { $same=Test-DuplicateGamePaths; foreach($ui in @($uiA,$uiB)) { $ui.PathWarningLabel.Text=if($same){'Одинаковый путь. Укажите вторую папку игры.'}else{''}; $ui.PathWarningLabel.Visibility=if($same){'Visible'}else{'Collapsed'} } }
function Update-RoleUi { if ($mainA.IsChecked) { $uiA.Group.Text='Основной'; $uiB.Group.Text='Донор' } else { $uiA.Group.Text='Донор'; $uiB.Group.Text='Основной' } }

function Select-GameFolder($Box) { $dlg=New-Object System.Windows.Forms.FolderBrowserDialog; $dlg.Description='Выберите папку Arizona с gta_sa.exe'; if (Test-Path -LiteralPath ([string]$Box.Text) -PathType Container -ErrorAction SilentlyContinue) { $dlg.SelectedPath=[string]$Box.Text }; if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $Box.Text=$dlg.SelectedPath } }
(Find-Control 'BrowseA').Add_Click({ Select-GameFolder $uiA.GameDir }); (Find-Control 'BrowseB').Add_Click({ Select-GameFolder $uiB.GameDir })
$uiA.ServerNumber.Add_TextChanged({ Update-ServerNameLabel $uiA }); $uiB.ServerNumber.Add_TextChanged({ Update-ServerNameLabel $uiB })
$uiA.GameDir.Add_TextChanged({ Update-DuplicateGamePathWarningUi; Save-UiSettings }); $uiB.GameDir.Add_TextChanged({ Update-DuplicateGamePathWarningUi; Save-UiSettings })
$uiA.Nick.Add_TextChanged({ Save-UiSettings }); $uiA.ServerNumber.Add_TextChanged({ Save-UiSettings }); $uiB.Nick.Add_TextChanged({ Save-UiSettings }); $uiB.ServerNumber.Add_TextChanged({ Save-UiSettings })
$script:RoleGuard=$false
$mainA.Add_Checked({ if($script:RoleGuard){return}; $script:RoleGuard=$true; $mainB.IsChecked=$false; $script:RoleGuard=$false; Update-RoleUi; Save-UiSettings })
$mainA.Add_Unchecked({ if($script:RoleGuard){return}; $script:RoleGuard=$true; $mainB.IsChecked=$true; $script:RoleGuard=$false; Update-RoleUi; Save-UiSettings })
$mainB.Add_Checked({ if($script:RoleGuard){return}; $script:RoleGuard=$true; $mainA.IsChecked=$false; $script:RoleGuard=$false; Update-RoleUi; Save-UiSettings })
$mainB.Add_Unchecked({ if($script:RoleGuard){return}; $script:RoleGuard=$true; $mainA.IsChecked=$true; $script:RoleGuard=$false; Update-RoleUi; Save-UiSettings })
$proxyEnabled.Add_Checked({ Update-ProxyUiEnabled; Reset-ProxyTestStatus; Save-UiSettings }); $proxyEnabled.Add_Unchecked({ Update-ProxyUiEnabled; Save-UiSettings })
$script:ProxyInputNormalizeGuard = $false
function Try-NormalizeProxyHostInput {
    if ($script:ProxyInputNormalizeGuard) { return $false }
    $raw = ([string]$proxyHost.Text).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $false }

    # Автозаполнение делаем только для полной curl-команды. Обычный host/IP пользователь может вводить вручную.
    if ($raw -notmatch '(?is)^\s*curl(?:\.exe)?\b') { return $false }

    try {
        $parsed = ConvertFrom-ProxyInputText $raw
        if ($null -eq $parsed) { return $false }

        $script:ProxyInputNormalizeGuard = $true
        try {
            $proxyType.SelectedItem = [string]$parsed.Type
            $proxyHost.Text = [string]$parsed.Host
            $proxyPort.Text = [string]$parsed.Port
            $proxyUsername.Text = [string]$parsed.Username
            $proxyPassword.Password = [string]$parsed.Password
            $proxyHost.CaretIndex = $proxyHost.Text.Length
            Set-ProxyTestStatus 'Прокси распознан. Нажмите «Проверить прокси» или запускайте подготовку.' ([Windows.Media.Brushes]::LightGreen)
        } finally {
            $script:ProxyInputNormalizeGuard = $false
        }
        Save-UiSettings
        return $true
    } catch {
        # Пока команда вставляется/редактируется, не показываем popup. Полная проверка будет при запуске.
        return $false
    }
}

$proxyType.Add_SelectionChanged({ Save-UiSettings })
$proxyHost.Add_TextChanged({
    if (-not $script:ProxyInputNormalizeGuard) { [void](Try-NormalizeProxyHostInput) }
    Save-UiSettings
})
$proxyPort.Add_TextChanged({ Save-UiSettings }); $proxyUsername.Add_TextChanged({ Save-UiSettings }); $proxyPassword.Add_PasswordChanged({ Save-UiSettings })
$profileKeyBox.Add_PasswordChanged({ $profilePlaceholder.Visibility=if([string]::IsNullOrEmpty($profileKeyBox.Password)){'Visible'}else{'Collapsed'} })
$proxyTestButton.Add_Click({ [Windows.MessageBox]::Show('Прокси проверяется автоматически во время подготовки запуска.','Прокси','OK','Information') | Out-Null })
Update-RoleUi; Update-ProxyUiEnabled; Update-DuplicateGamePathWarningUi

function Set-LoadingState([string]$Mode) { $settingsContent.IsEnabled=$false; $launchButton.IsEnabled=$false; $checkFilesButton.IsEnabled=$false; $stopButton.IsEnabled=$false; $loadingTitle.Text=if($Mode -eq 'CheckOnly'){'Проверка файлов'}else{'Подготовка запуска'}; $loadingOverlay.Visibility='Visible' }
function Set-NormalState { $settingsContent.IsEnabled=$true; $idle=-not [bool]$PairRuntime.Active; $launchButton.IsEnabled=$idle; $checkFilesButton.IsEnabled=$idle; $stopButton.IsEnabled=[bool]$PairRuntime.Active; $loadingOverlay.Visibility='Collapsed' }
function Complete-Preparation($Result) { Set-Indicator $originalDot $originalStatus ([string]$Result.OriginalVersion) '#35D07F'; Set-Indicator $payloadDot $payloadStatus 'Актуально' '#35D07F'; Set-Indicator $antiDot $antiStatus 'Готов' '#35D07F'; $script:PreparedProxyResult=$Result.ProxyTest }
function Fail-Preparation([string]$Message) { Set-Indicator $payloadDot $payloadStatus 'Ошибка' '#FF6464'; Set-Indicator $antiDot $antiStatus 'Ошибка' '#FF6464'; Set-NormalState; Write-Status "Ошибка: $Message"; Write-DevLog "Preparation failed: $Message"; [Windows.MessageBox]::Show($Message,'Ошибка подготовки','OK','Error') | Out-Null }

$script:PreparationProcess=$null; $script:PreparationPollTimer=$null; $script:PreparationProgressRead=0; $script:PreparationFiles=$null; $script:PreparationMode=''; $script:PreparedProxyResult=$null
function Remove-PreparationFiles { if($null -eq $script:PreparationFiles){return}; foreach($path in $script:PreparationFiles){ if(Test-Path -LiteralPath $path -PathType Leaf){ Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } }; $script:PreparationFiles=$null }
function Run-Preparation([ValidateSet('FullLaunch','CheckOnly')][string]$Mode) {
    if($null -ne $script:PreparationProcess -and -not $script:PreparationProcess.HasExited){ Write-Status 'Проверка уже выполняется.'; return }
    if($PairRuntime.Active){ [Windows.MessageBox]::Show('Связка уже запущена. Сначала нажмите «Остановить».','Проверка файлов','OK','Information')|Out-Null; return }
    try {
        $pair=Validate-Pair; Assert-GameNotRunning $pair.Main 'MAIN'; Assert-GameNotRunning $pair.Donor 'DONOR'; Save-Settings $pair
        $id=[Guid]::NewGuid().ToString('N'); $configPath=Join-Path $SettingsDir "prepare_$id.json"; $progressPath=Join-Path $SettingsDir "prepare_$id.progress"; $resultPath=Join-Path $SettingsDir "prepare_$id.result.json"
        $config=[ordered]@{ MainGamePath=$pair.Main.GameDir; DonorGamePath=$pair.Donor.GameDir; PayloadOwner=$PayloadOwner; PayloadRepo=$PayloadRepo; PayloadBranch=$PayloadBranch; PayloadRemotePath=$PayloadRemotePath; CustomArzMarketInfoUrl=$CustomArzMarketInfoUrl; OriginalArzMarketInfoUrl=$OriginalArzMarketInfoUrl; CustomLuaPath=(Join-Path $ScriptDir 'lua\by_Quant_ArzMarket[3_56].lua'); AntiAfkOwner=$AntiAfkOwner; AntiAfkRepo=$AntiAfkRepo; AntiAfkBranch=$AntiAfkBranch; AntiAfkRemotePath=$AntiAfkRemotePath; AntiAfkLocalRelativePath=$AntiAfkLocalRelativePath; Proxy=(Get-ProxySettingsForStorage) }
        Write-JsonAtomic $configPath $config; [IO.File]::WriteAllText($progressPath,'',[Text.UTF8Encoding]::new($false)); $script:PreparationFiles=@($configPath,$progressPath,$resultPath); $script:PreparationProgressRead=0; $script:PreparationMode=$Mode; $script:PreparedProxyResult=$null
        Set-Indicator $originalDot $originalStatus 'Проверка' '#8E99A5'; Set-Indicator $payloadDot $payloadStatus 'Ожидание' '#8E99A5'; Set-Indicator $antiDot $antiStatus 'Ожидание' '#8E99A5'; Set-LoadingState $Mode; Write-Status $(if($Mode -eq 'CheckOnly'){'Ручная проверка файлов...'}else{'Проверка версии оригинального ArzMarket...'})
        $args='-NoProfile -ExecutionPolicy Bypass -STA -File "{0}" -PreparationWorker -PreparationConfigPath "{1}" -PreparationProgressPath "{2}" -PreparationResultPath "{3}"' -f $PSCommandPath,$configPath,$progressPath,$resultPath
        $script:PreparationProcess=Start-Process -FilePath 'powershell.exe' -ArgumentList $args -PassThru -WindowStyle Hidden
        $script:PreparationPollTimer=New-Object Windows.Threading.DispatcherTimer; $script:PreparationPollTimer.Interval=[TimeSpan]::FromMilliseconds(250)
        $script:PreparationPollTimer.Add_Tick({
            try {
                $progressPath=$script:PreparationFiles[1]; $resultPath=$script:PreparationFiles[2]
                $lines=@(Get-Content -LiteralPath $progressPath -Encoding UTF8 -ErrorAction SilentlyContinue)
                while($script:PreparationProgressRead -lt $lines.Count){ $line=$lines[$script:PreparationProgressRead++]; try{$event=$line|ConvertFrom-Json -ErrorAction Stop; $loadingText.Text=[string]$event.text; Write-Status ([string]$event.text); if($event.text -like 'Проверка файлов*'){Set-Indicator $payloadDot $payloadStatus 'Проверка' '#8E99A5'}; if($event.text -like 'Проверка Anti*'){Set-Indicator $antiDot $antiStatus 'Проверка' '#8E99A5'}}catch{} }
                if($script:PreparationProcess.HasExited){
                    $script:PreparationPollTimer.Stop(); $result=if(Test-Path -LiteralPath $resultPath){((Get-TextDocument $resultPath).Text)|ConvertFrom-Json}else{$null}
                    $completedMode=$script:PreparationMode; Remove-PreparationFiles; $script:PreparationProcess=$null; $script:PreparationMode=''
                    if($null -eq $result){ Fail-Preparation 'Процесс подготовки завершился без результата.'; return }
                    if($result.Success -eq $true){ Complete-Preparation $result; if($completedMode -eq 'CheckOnly'){ Set-NormalState; Write-Status 'Проверка файлов завершена. Обновления установлены.' }else{ try{ Write-Status 'Запуск MAIN/DONOR...'; Start-MainDonor; Set-NormalState }catch{ Fail-Preparation $_.Exception.Message } } }
                    elseif($result.OriginalNewer -eq $true){ Set-Indicator $originalDot $originalStatus ([string]$result.OriginalVersion) '#FF6464'; Set-NormalState; $message="Вышла новая версия оригинального ArzMarket`n`nОригинальная версия: $($result.OriginalVersion)`nТекущая версия вашей сборки: $($result.CustomVersion)`n`nЗапуск двух окон временно недоступен. Сначала необходимо обновить ArzMarket."; Write-DevLog $message; Write-Status 'Запуск заблокирован: оригинальный ArzMarket новее.'; [Windows.MessageBox]::Show($message,'Обновление ArzMarket','OK','Warning')|Out-Null }
                    else{ Fail-Preparation ([string]$result.Error) }
                }
            } catch { if($null -ne $script:PreparationPollTimer){$script:PreparationPollTimer.Stop()}; Remove-PreparationFiles; $script:PreparationMode=''; Fail-Preparation $_.Exception.Message }
        }); $script:PreparationPollTimer.Start()
    } catch { $script:PreparationMode=''; Fail-Preparation $_.Exception.Message }
}


function Show-LauncherOnboarding([bool]$Force = $false) {
    if (-not $Force -and (Test-Path -LiteralPath $OnboardingCompletedPath -PathType Leaf)) { return }

    [xml]$OnboardingXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Arizona - обучение" Width="760" Height="590"
        MinWidth="760" MaxWidth="760" MinHeight="590" MaxHeight="590"
        WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize"
        Background="#11161B" Foreground="#F2F5F7" FontFamily="Segoe UI" ShowInTaskbar="False">
  <Window.Resources>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#11161B"/><Setter Property="Foreground" Value="#F2F5F7"/>
      <Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="9,6"/><Setter Property="CaretBrush" Value="#35D07F"/>
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="Background" Value="#11161B"/><Setter Property="Foreground" Value="#F2F5F7"/>
      <Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="9,6"/><Setter Property="CaretBrush" Value="#35D07F"/>
    </Style>
    <Style x:Key="TutorialButton" TargetType="Button">
      <Setter Property="Background" Value="#20272E"/><Setter Property="Foreground" Value="#F2F5F7"/>
      <Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,8"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#283139"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="TutorialAccentButton" TargetType="Button" BasedOn="{StaticResource TutorialButton}"><Setter Property="Background" Value="#35D07F"/><Setter Property="Foreground" Value="#07140D"/><Setter Property="BorderBrush" Value="#35D07F"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style x:Key="TutorialCard" TargetType="Border"><Setter Property="Background" Value="#181E24"/><Setter Property="BorderBrush" Value="#2A323A"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="10"/><Setter Property="Padding" Value="16"/></Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="52"/><RowDefinition Height="*"/><RowDefinition Height="64"/></Grid.RowDefinitions>
    <Border x:Name="TutorialTitleBar" Grid.Row="0" Background="#11161B" BorderBrush="#2A323A" BorderThickness="0,0,0,1">
      <Grid Margin="18,0,10,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center"><TextBlock Text="Первый запуск" FontSize="17" FontWeight="SemiBold"/><TextBlock x:Name="TutorialStepLabel" Text="Шаг 1 из 4" FontSize="11" Foreground="#8E99A5"/></StackPanel>
        <Button x:Name="TutorialCloseButton" Grid.Column="1" Content="×" Width="42" Height="34" Style="{StaticResource TutorialButton}" BorderThickness="0" FontSize="17"/>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="18,16,18,12">
      <Grid x:Name="TutorialWelcome">
        <Border Style="{StaticResource TutorialCard}"><StackPanel VerticalAlignment="Center" MaxWidth="610">
          <TextBlock Text="Настроим лаунчер" FontSize="24" FontWeight="SemiBold" HorizontalAlignment="Center"/>
          <TextBlock Text="Обучение покажет, какие данные нужны для основного и донорского аккаунтов, куда вставлять прокси и где получить код Telegram." Foreground="#B8C1CA" FontSize="14" TextWrapping="Wrap" TextAlignment="Center" Margin="0,14,0,0"/>
          <Border Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,22,0,0">
            <TextBlock Text="Ничего вручную искать в файлах программы не нужно. Все данные вводятся прямо в лаунчере." Foreground="#8E99A5" TextWrapping="Wrap" TextAlignment="Center"/>
          </Border>
        </StackPanel></Border>
      </Grid>

      <Grid x:Name="TutorialAccounts" Visibility="Collapsed">
        <Border Style="{StaticResource TutorialCard}"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
          <TextBlock Text="Аккаунты" FontSize="20" FontWeight="SemiBold"/>
          <TextBlock Text="Основной - аккаунт, с которого вы будете играть. Донор нужен для получения данных авторизации. Донорский аккаунт можно брать с любого сервера Arizona RP, он не обязан быть на том же сервере, что и основной." Foreground="#B8C1CA" TextWrapping="Wrap" Margin="0,8,0,14"/>
          <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/></Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="8" Padding="12"><StackPanel>
              <TextBlock Text="Основной аккаунт" FontWeight="SemiBold" FontSize="14"/>
              <TextBlock Text="Папка Arizona" Foreground="#8E99A5" Margin="0,10,0,4"/>
              <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="38"/></Grid.ColumnDefinitions><TextBox x:Name="OnboardingMainPath" Height="31"/><Button x:Name="OnboardingMainBrowse" Grid.Column="1" Content="..." Margin="6,0,0,0" Style="{StaticResource TutorialButton}" Padding="0"/></Grid>
              <TextBlock Text="Ник" Foreground="#8E99A5" Margin="0,9,0,4"/><TextBox x:Name="OnboardingMainNick" Height="31"/>
              <TextBlock Text="Номер сервера" Foreground="#8E99A5" Margin="0,9,0,4"/><TextBox x:Name="OnboardingMainServer" Height="31" MaxLength="2"/>
              <TextBlock Text="Этот аккаунт будет отмечен как забаненный MAIN." Foreground="#8E99A5" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,0"/>
            </StackPanel></Border>
            <Border Grid.Column="2" Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="8" Padding="12"><StackPanel>
              <TextBlock Text="Донорский аккаунт" FontWeight="SemiBold" FontSize="14"/>
              <TextBlock Text="Папка Arizona" Foreground="#8E99A5" Margin="0,10,0,4"/>
              <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="38"/></Grid.ColumnDefinitions><TextBox x:Name="OnboardingDonorPath" Height="31"/><Button x:Name="OnboardingDonorBrowse" Grid.Column="1" Content="..." Margin="6,0,0,0" Style="{StaticResource TutorialButton}" Padding="0"/></Grid>
              <TextBlock Text="Ник" Foreground="#8E99A5" Margin="0,9,0,4"/><TextBox x:Name="OnboardingDonorNick" Height="31"/>
              <TextBlock Text="Номер сервера" Foreground="#8E99A5" Margin="0,9,0,4"/><TextBox x:Name="OnboardingDonorServer" Height="31" MaxLength="2"/>
              <TextBlock Text="Можно использовать аккаунт с любого сервера 1-33." Foreground="#35D07F" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,0"/>
            </StackPanel></Border>
          </Grid>
          <TextBlock x:Name="OnboardingAccountsError" Visibility="Collapsed" Foreground="#FF6B6B" FontSize="11" TextWrapping="Wrap" Margin="0,10,0,0"/>
        </StackPanel></ScrollViewer></Border>
      </Grid>

      <Grid x:Name="TutorialProxy" Visibility="Collapsed">
        <Border Style="{StaticResource TutorialCard}"><StackPanel>
          <TextBlock Text="Прокси для ArzMarket" FontSize="20" FontWeight="SemiBold"/>
          <TextBlock TextWrapping="Wrap" Foreground="#B8C1CA" Margin="0,10,0,0">
            <Run Text="1. Зайдите на сайт "/>
            <Hyperlink x:Name="OnboardingWebshareLink" Foreground="#35D07F" TextDecorations="Underline" Cursor="Hand">Webshare</Hyperlink>
            <Run Text=" и авторизуйтесь через Google."/>
          </TextBlock>
          <TextBlock Text="2. Откройте список прокси. Справа у нужного прокси нажмите на 3 точки." Foreground="#B8C1CA" TextWrapping="Wrap" Margin="0,8,0,0"/>
          <TextBlock Text="3. Скопируйте готовую ссылку подключения." Foreground="#B8C1CA" TextWrapping="Wrap" Margin="0,6,0,0"/>
          <TextBlock Text="4. Вставьте скопированную ссылку в поле ниже." Foreground="#B8C1CA" TextWrapping="Wrap" Margin="0,6,0,0"/>
          <Border Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,14,0,0"><StackPanel>
            <TextBlock Text="Можно также вставить curl-команду целиком:" Foreground="#8E99A5"/>
            <TextBlock Text='curl --proxy &quot;http://login:password@host:port/&quot; https://ipv4.webshare.io/' FontFamily="Consolas" Foreground="#35D07F" TextWrapping="Wrap" Margin="0,6,0,0"/>
          </StackPanel></Border>
          <TextBlock Text="Лаунчер сам разберёт тип, host, порт, логин и пароль." Foreground="#8E99A5" Margin="0,14,0,5"/>
          <TextBox x:Name="OnboardingProxyInput" Height="76" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
          <TextBlock Text="Если прокси пока нет, поле можно оставить пустым и настроить его позже в основном окне." Foreground="#8E99A5" FontSize="11" TextWrapping="Wrap" Margin="0,8,0,0"/>
        </StackPanel></Border>
      </Grid>

      <Grid x:Name="TutorialTelegram" Visibility="Collapsed">
        <Border Style="{StaticResource TutorialCard}"><StackPanel VerticalAlignment="Center" MaxWidth="620">
          <TextBlock Text="Telegram" FontSize="20" FontWeight="SemiBold" HorizontalAlignment="Center"/>
          <TextBlock Text="Код для поля Telegram можно получить в боте @ArzMarketManager_bot. Откройте бота, получите код и вставьте его в поле ниже или позже в основном окне лаунчера." Foreground="#B8C1CA" FontSize="14" TextWrapping="Wrap" TextAlignment="Center" Margin="0,10,0,0"/>
          <Button x:Name="OnboardingTelegramOpen" Content="Открыть @ArzMarketManager_bot" Style="{StaticResource TutorialButton}" Height="38" Width="260" Margin="0,18,0,0"/>
          <TextBlock Text="Код Telegram" Foreground="#8E99A5" Margin="0,18,0,5"/>
          <PasswordBox x:Name="OnboardingTelegramKey" Height="34"/>
          <TextBlock Text="Поле можно оставить пустым и заполнить позже." Foreground="#8E99A5" FontSize="11" Margin="0,7,0,0"/>
          <Border Background="#11161B" BorderBrush="#2A323A" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,18,0,0"><TextBlock Text="После завершения обучения настройки аккаунтов и прокси останутся в лаунчере. Код Telegram сохраняться на диск не будет." Foreground="#8E99A5" TextWrapping="Wrap"/></Border>
        </StackPanel></Border>
      </Grid>
    </Grid>

    <Border Grid.Row="2" Background="#181E24" BorderBrush="#2A323A" BorderThickness="0,1,0,0">
      <Grid Margin="18,10"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="10"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="TutorialHint" Text="Шаг 1 из 4" Foreground="#8E99A5" VerticalAlignment="Center"/>
        <Button x:Name="TutorialBack" Grid.Column="1" Content="Назад" Width="110" Height="36" Style="{StaticResource TutorialButton}" Visibility="Collapsed"/>
        <Button x:Name="TutorialNext" Grid.Column="3" Content="Далее" Width="150" Height="36" Style="{StaticResource TutorialAccentButton}"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $OnboardingXaml
    $tutorial = [Windows.Markup.XamlReader]::Load($reader)
    $tutorial.Owner = $form

    $titleBarTutorial = $tutorial.FindName('TutorialTitleBar')
    $closeTutorial = $tutorial.FindName('TutorialCloseButton')
    $stepLabel = $tutorial.FindName('TutorialStepLabel')
    $hintLabel = $tutorial.FindName('TutorialHint')
    $backTutorial = $tutorial.FindName('TutorialBack')
    $nextTutorial = $tutorial.FindName('TutorialNext')
    $panels = @(
        $tutorial.FindName('TutorialWelcome'),
        $tutorial.FindName('TutorialAccounts'),
        $tutorial.FindName('TutorialProxy'),
        $tutorial.FindName('TutorialTelegram')
    )

    $mainPath = $tutorial.FindName('OnboardingMainPath')
    $mainNick = $tutorial.FindName('OnboardingMainNick')
    $mainServer = $tutorial.FindName('OnboardingMainServer')
    $mainBrowse = $tutorial.FindName('OnboardingMainBrowse')
    $donorPath = $tutorial.FindName('OnboardingDonorPath')
    $donorNick = $tutorial.FindName('OnboardingDonorNick')
    $donorServer = $tutorial.FindName('OnboardingDonorServer')
    $donorBrowse = $tutorial.FindName('OnboardingDonorBrowse')
    $proxyInput = $tutorial.FindName('OnboardingProxyInput')
    $webshareLink = $tutorial.FindName('OnboardingWebshareLink')
    $accountsError = $tutorial.FindName('OnboardingAccountsError')
    $telegramKey = $tutorial.FindName('OnboardingTelegramKey')
    $telegramOpen = $tutorial.FindName('OnboardingTelegramOpen')

    $mainPath.Text = [string]$uiA.GameDir.Text
    $mainNick.Text = [string]$uiA.Nick.Text
    $mainServer.Text = [string]$uiA.ServerNumber.Text
    $donorPath.Text = [string]$uiB.GameDir.Text
    $donorNick.Text = [string]$uiB.Nick.Text
    $donorServer.Text = [string]$uiB.ServerNumber.Text
    $telegramKey.Password = [string]$profileKeyBox.Password

    if ($proxyEnabled.IsChecked -and -not [string]::IsNullOrWhiteSpace([string]$proxyHost.Text)) {
        $proxyUriText = ''
        try {
            $tmpProxy = Get-ProxyUiConfig
            if ($tmpProxy.Enabled) {
                $proxyHostText = [string]$tmpProxy.Host
                $proxyUriText = ('{0}://{1}:{2}' -f [string]$tmpProxy.Type, $proxyHostText, [int]$tmpProxy.Port)
            }
        } catch {}
        $proxyInput.Text = $proxyUriText
    }

    # Shared mutable state is required here because GetNewClosure() creates separate dynamic modules.
    # A shared object keeps every handler on the same wizard page index.
    $onboardingState = [pscustomobject]@{ Step = 0; Completed = $false }
    $setStep = {
        param([int]$Index)
        if ($Index -lt 0) { $Index = 0 }
        if ($Index -gt 3) { $Index = 3 }
        $onboardingState.Step = $Index
        for ($i = 0; $i -lt $panels.Count; $i++) {
            $panels[$i].Visibility = if ($i -eq $Index) { 'Visible' } else { 'Collapsed' }
        }
        $display = $Index + 1
        $stepLabel.Text = "Шаг $display из 4"
        $hintLabel.Text = "Шаг $display из 4"
        $backTutorial.Visibility = if ($Index -gt 0) { 'Visible' } else { 'Collapsed' }
        $nextTutorial.Content = if ($Index -eq 3) { 'Завершить' } else { 'Далее' }
    }.GetNewClosure()

    $chooseFolder = {
        param($Box)
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Выберите папку Arizona с gta_sa.exe'
        $current = [string]$Box.Text
        if (-not [string]::IsNullOrWhiteSpace($current) -and (Test-Path -LiteralPath $current -PathType Container -ErrorAction SilentlyContinue)) {
            $dlg.SelectedPath = $current
        }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Box.Text = $dlg.SelectedPath
        }
        $dlg.Dispose()
    }.GetNewClosure()

    $mainBrowse.Add_Click({ & $chooseFolder $mainPath }.GetNewClosure())
    $donorBrowse.Add_Click({ & $chooseFolder $donorPath }.GetNewClosure())
    if ($null -ne $webshareLink) {
        $webshareLink.Add_Click({
            try { Start-Process 'https://www.webshare.io/' | Out-Null }
            catch { [Windows.MessageBox]::Show('Не удалось открыть Webshare. Откройте вручную: https://www.webshare.io/','Webshare','OK','Warning') | Out-Null }
        }.GetNewClosure())
    }
    $telegramOpen.Add_Click({
        try { Start-Process 'https://t.me/ArzMarketManager_bot' | Out-Null }
        catch { [Windows.MessageBox]::Show('Не удалось открыть Telegram. Найдите бота вручную: @ArzMarketManager_bot','Telegram','OK','Warning') | Out-Null }
    }.GetNewClosure())

    $titleBarTutorial.Add_MouseLeftButtonDown({
        if ($_.ChangedButton -eq [Windows.Input.MouseButton]::Left) { $tutorial.DragMove() }
    }.GetNewClosure())
    $closeTutorial.Add_Click({ $tutorial.Close() }.GetNewClosure())
    $backTutorial.Add_Click({ & $setStep ([int]$onboardingState.Step - 1) }.GetNewClosure())

    $nextTutorial.Add_Click({
        try {
            $currentStep = [int]$onboardingState.Step
            Write-DevLog "Onboarding next clicked. step=$currentStep"
            if ($currentStep -eq 1) {
                if ($null -ne $accountsError) {
                    $accountsError.Text = ''
                    $accountsError.Visibility = 'Collapsed'
                }

                $uiA.GameDir.Text = ([string]$mainPath.Text).Trim()
                $uiA.Nick.Text = ([string]$mainNick.Text).Trim()
                $uiA.ServerNumber.Text = ([string]$mainServer.Text).Trim()
                $uiB.GameDir.Text = ([string]$donorPath.Text).Trim()
                $uiB.Nick.Text = ([string]$donorNick.Text).Trim()
                $uiB.ServerNumber.Text = ([string]$donorServer.Text).Trim()
                $mainA.IsChecked = $true
                $mainB.IsChecked = $false
                Update-RoleUi

                try {
                    [void](Validate-Pair)
                } catch {
                    $validationMessage = [string]$_.Exception.Message
                    if ($null -ne $accountsError) {
                        $accountsError.Text = $validationMessage
                        $accountsError.Visibility = 'Visible'
                    }
                    try { [void][Windows.MessageBox]::Show($tutorial, $validationMessage, 'Проверьте данные аккаунтов', 'OK', 'Warning') } catch {}
                    return
                }

                Save-UiSettings
            }
            elseif ($currentStep -eq 2) {
                $rawProxy = ([string]$proxyInput.Text).Trim()
                if ([string]::IsNullOrWhiteSpace($rawProxy)) {
                    $proxyEnabled.IsChecked = $false
                    Update-ProxyUiEnabled
                    Save-UiSettings
                } else {
                    $parsedProxy = ConvertFrom-ProxyInputText $rawProxy
                    if ($null -eq $parsedProxy) { throw 'Не удалось распознать proxy URL или curl-команду.' }
                    $proxyEnabled.IsChecked = $true
                    $proxyType.SelectedItem = [string]$parsedProxy.Type
                    $proxyHost.Text = [string]$parsedProxy.Host
                    $proxyPort.Text = [string]$parsedProxy.Port
                    $proxyUsername.Text = [string]$parsedProxy.Username
                    $proxyPassword.Password = [string]$parsedProxy.Password
                    Update-ProxyUiEnabled
                    Set-ProxyTestStatus 'Прокси заполнен. Перед запуском он будет проверен.' ([Windows.Media.Brushes]::LightGreen)
                    Save-UiSettings
                }
            }
            elseif ($currentStep -eq 3) {
                $profileKeyBox.Password = [string]$telegramKey.Password
                $profilePlaceholder.Visibility = if ([string]::IsNullOrEmpty($profileKeyBox.Password)) { 'Visible' } else { 'Collapsed' }
                try {
                    [IO.File]::WriteAllText($OnboardingCompletedPath, (Get-Date).ToString('o'), [Text.UTF8Encoding]::new($false))
                } catch {
                    Write-DevLog "Onboarding completion flag write failed: $($_.Exception.Message)"
                }
                $onboardingState.Completed = $true
                Write-Status 'Обучение завершено. Проверьте данные и нажмите "Проверить файлы" или "Запустить".'
                $tutorial.Close()
                return
            }

            & $setStep ($currentStep + 1)
        } catch {
            $tutorialError = [string]$_.Exception.Message
            try { [void][Windows.MessageBox]::Show($tutorial, $tutorialError, 'Обучение', 'OK', 'Warning') }
            catch { [Windows.MessageBox]::Show($tutorialError,'Обучение','OK','Warning') | Out-Null }
        }
    }.GetNewClosure())

    & $setStep 0
    [void]$tutorial.ShowDialog()
}

function Start-Preparation { Run-Preparation 'FullLaunch' }
function Start-FileCheck { Run-Preparation 'CheckOnly' }

$launchButton.Add_Click({ Start-Preparation }); $checkFilesButton.Add_Click({ Start-FileCheck }); $stopButton.Add_Click({ Stop-MainDonor; Set-NormalState })
$helpButton.Add_Click({ Show-LauncherOnboarding $true })
$detailsButton.Add_Click({ if($logContentRow.Height.Value -lt 100){$logContentRow.Height=220; $form.Height=870; $detailsButton.Content='Свернуть'}else{$logContentRow.Height=72; $form.Height=720; $detailsButton.Content='Подробнее'} })
$titleBar.Add_MouseLeftButtonDown({ if($_.ChangedButton -eq [Windows.Input.MouseButton]::Left){$form.DragMove()} }); $minimizeButton.Add_Click({$form.WindowState='Minimized'}); $closeButton.Add_Click({$form.Close()})
$form.Add_Closing({ Save-UiSettings; if($null -ne $script:PreparationPollTimer){$script:PreparationPollTimer.Stop()}; if($null -ne $script:PreparationProcess -and -not $script:PreparationProcess.HasExited){try{$script:PreparationProcess.Kill()}catch{}}; Remove-PreparationFiles; $PairRuntime.ProfileKey=''; $profileKeyBox.Password=''; try{if($null-ne $PairRuntime.Main){Write-LauncherHeartbeat $PairRuntime.Main $false};if($null-ne $PairRuntime.Donor){Write-LauncherHeartbeat $PairRuntime.Donor $false}}catch{} })

$SettingsLoadPath = $SettingsPath
if (-not (Test-Path -LiteralPath $SettingsLoadPath) -and (Test-Path -LiteralPath $LegacySettingsPath)) {
    $SettingsLoadPath = $LegacySettingsPath
}

if (Test-Path -LiteralPath $SettingsLoadPath) {
    try {
        $s = ((Get-TextDocument $SettingsLoadPath).Text) | ConvertFrom-Json
        Set-UiFromAccount $uiA $s.AccountA
        Set-UiFromAccount $uiB $s.AccountB
        if ($s.PSObject.Properties.Name -contains 'Proxy') { Set-UiFromProxySettings $s.Proxy }
        if ($s.PSObject.Properties.Name -contains 'BannedMainIndex' -and -not [string]::IsNullOrWhiteSpace([string]$s.BannedMainIndex)) {
            if ([string]$s.BannedMainIndex -eq 'B') { $mainB.IsChecked = $true } else { $mainA.IsChecked = $true }
        } elseif ($s.PSObject.Properties.Name -contains 'TokenSourceIndex' -and -not [string]::IsNullOrWhiteSpace([string]$s.TokenSourceIndex)) {
            # В предыдущей версии эта же галочка ошибочно считалась DONOR. Сохраняем выбранную пользователем сторону, но теперь трактуем ее как MAIN.
            if ([string]$s.TokenSourceIndex -eq 'B') { $mainB.IsChecked = $true } else { $mainA.IsChecked = $true }
        } elseif ($s.PSObject.Properties.Name -contains 'MainIndex' -and -not [string]::IsNullOrWhiteSpace([string]$s.MainIndex)) {
            if ([string]$s.MainIndex -eq 'B') { $mainB.IsChecked = $true } else { $mainA.IsChecked = $true }
        }
        Update-RoleUi
        Save-UiSettings
        Write-Status 'Настройки загружены.'
        Write-DevLog "Settings loaded from $SettingsLoadPath; persistent path=$SettingsPath"
    } catch {
        Write-DevLog "Settings load error: $($_.Exception.ToString())"
        Write-Status 'Не смог загрузить настройки.'
    }
} else {
    Write-Status 'Введите данные двух аккаунтов.'
}
Write-DevLog "Launcher started. Developer log: $DeveloperLogPath"

$script:LastMainConnectionState = ''
$script:LastDonorConnectionState = ''

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    try {
        $pair = $null
        try { $pair = Validate-Pair } catch {}
        if ($null -ne $pair) {
            $ms = Get-WatchdogState $pair.Main
            $ds = Get-WatchdogState $pair.Donor
            $stateMain.Text = "Основной $($pair.Main.Nick): $(Get-RussianState $ms.State)"
            $stateDonor.Text = "Донор $($pair.Donor.Nick): $(Get-RussianState $ds.State)"
            $stateMain.Foreground = if ($ms.State -eq 'ONLINE' -and $ms.Age -le 12) { [Windows.Media.Brushes]::LightGreen } else { [Windows.Media.Brushes]::Orange }
            $stateDonor.Foreground = if ($ds.State -eq 'ONLINE' -and $ds.Age -le 12) { [Windows.Media.Brushes]::LightGreen } else { [Windows.Media.Brushes]::Orange }

            if ($script:LastMainConnectionState -ne $ms.State) {
                Write-DevLog "MAIN state changed: $($script:LastMainConnectionState) -> $($ms.State), age=$([int]$ms.Age)s"
                if ($ms.State -eq 'ONLINE') {
                    Write-Status 'Вошел в основной.'
                    if ($PairRuntime.Phase -eq 'RUNNING') { Write-Status 'Связка готова.' }
                } elseif ($script:LastMainConnectionState -eq 'ONLINE' -and $ms.State -ne 'NO_STATE') {
                    Write-Status 'Основной отключился. Восстанавливаю...'
                }
                $script:LastMainConnectionState = $ms.State
            }

            if ($script:LastDonorConnectionState -ne $ds.State) {
                Write-DevLog "DONOR state changed: $($script:LastDonorConnectionState) -> $($ds.State), age=$([int]$ds.Age)s"
                if ($ds.State -eq 'ONLINE') {
                    Write-Status 'Вошел в донор.'
                } elseif ($script:LastDonorConnectionState -eq 'ONLINE' -and $ds.State -ne 'NO_STATE') {
                    Write-Status 'Донор отключился. Восстанавливаю...'
                }
                $script:LastDonorConnectionState = $ds.State
            }
        }

        $phaseLabel.Text = "Связка: $(Get-RussianPhase $PairRuntime.Phase)"
        if ($PairRuntime.Active) {
            Write-LauncherHeartbeat $PairRuntime.Main $true
            Write-LauncherHeartbeat $PairRuntime.Donor $true
        }
        if (-not $PairRuntime.Active) { return }

        if ((Get-Date) -gt $PairRuntime.Deadline -and $PairRuntime.Phase -eq 'WAIT_DONOR') {
            Write-Status 'Не вошел в донор за 3 минуты.'
            Write-LauncherHeartbeat $PairRuntime.Main $false
            Write-LauncherHeartbeat $PairRuntime.Donor $false
            $PairRuntime.Active = $false
            $PairRuntime.Phase = 'TIMEOUT'
            $PairRuntime.ProfileKey = ''
            $profileKeyBox.Password = ''
            return
        }

        $donorState = Get-WatchdogState $PairRuntime.Donor
        if ($donorState.State -ne 'ONLINE' -or $donorState.Age -gt 12) {
            $PairRuntime.CandidateToken = ''
            $PairRuntime.CandidateSince = [datetime]::MinValue
            return
        }

        $payload = Get-DonorAuthPayload $PairRuntime.Donor
        if ($null -eq $payload) { return }

        if ($PairRuntime.CandidateToken -ne $payload.Token) {
            $PairRuntime.CandidateToken = $payload.Token
            $PairRuntime.CandidateSince = Get-Date
            Write-Status 'Получил данные донора. Проверяю...'
            return
        }
        if (((Get-Date) - $PairRuntime.CandidateSince).TotalSeconds -lt 6) { return }

        if ($PairRuntime.Phase -eq 'WAIT_DONOR') {
            Write-DonorSnapshot $PairRuntime.Main $PairRuntime.Donor $payload $true | Out-Null
            $PairRuntime.LastSignature = $payload.Signature
            Write-Status 'Данные готовы. Вхожу в основной...'
            Write-LauncherProfileAuth $PairRuntime.Main
            Start-WatchdogAccount $PairRuntime.Main 'MAIN'
            $PairRuntime.Phase = 'RUNNING'
            $PairRuntime.Deadline = [datetime]::MaxValue
            return
        }

        if ($PairRuntime.Phase -eq 'RUNNING' -and $payload.Signature -ne $PairRuntime.LastSignature) {
            Write-DonorSnapshot $PairRuntime.Main $PairRuntime.Donor $payload $false | Out-Null
            $PairRuntime.LastSignature = $payload.Signature
            Write-Status 'Обновил данные основного.'
        }
    } catch {
        Write-DevLog "Background error: $($_.Exception.ToString())"
        Write-Status 'Ошибка. Подробности в папке logs.'
    }
})
$timer.Start()
$script:OnboardingAutoShown = $false
$form.Add_ContentRendered({
    if (-not $script:OnboardingAutoShown) {
        $script:OnboardingAutoShown = $true
        if (-not (Test-Path -LiteralPath $OnboardingCompletedPath -PathType Leaf)) { Show-LauncherOnboarding $false }
    }
})
[void]$form.ShowDialog()
