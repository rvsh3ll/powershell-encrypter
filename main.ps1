#requires -Version 5.1

$Script:RootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:ProjectUrl = 'https://github.com/rvsh3ll/powershell-encrypter'
$versionPath = Join-Path $Script:RootPath 'VERSION'
if (Test-Path -LiteralPath $versionPath) {
    $Script:ProjectVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
}
else {
    $Script:ProjectVersion = 'v1.0.1'
}

function Get-RandomBytes {
    param([int]$Length)

    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    return $bytes
}

function Compress-Bytes {
    param([byte[]]$Data)

    Add-Type -AssemblyName System.IO.Compression
    $ms = New-Object System.IO.MemoryStream
    $gzip = New-Object System.IO.Compression.GZipStream(
        $ms,
        [System.IO.Compression.CompressionMode]::Compress
    )
    $gzip.Write($Data, 0, $Data.Length)
    $gzip.Close()
    return $ms.ToArray()
}

function Protect-AesBytes {
    param(
        [byte[]]$Plaintext,
        [byte[]]$Key,
        [byte[]]$IV
    )

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $Key
    $aes.IV = $IV
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $encryptor = $aes.CreateEncryptor()
    return $encryptor.TransformFinalBlock($Plaintext, 0, $Plaintext.Length)
}

function Protect-KeyMaterialWithPassword {
    param(
        [byte[]]$KeyMaterial,
        [string]$Password
    )

    $salt = Get-RandomBytes -Length 16
    $wrapIv = Get-RandomBytes -Length 16
    $passBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $passBytes,
        $salt,
        100000
    )
    $wrapKey = $derive.GetBytes(32)
    $derive.Dispose()

    $wrappedKey = Protect-AesBytes -Plaintext $KeyMaterial -Key $wrapKey -IV $wrapIv

    return @{
        WrappedKey = $wrappedKey
        Salt = $salt
        WrapIv = $wrapIv
    }
}

function Format-StartupMessageLiteral {
    param([string]$Message)

    if ([string]::IsNullOrEmpty($Message)) {
        return ''
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    return [Convert]::ToBase64String($bytes)
}

function Open-SavedFileFolder {
    param([string]$FilePath)

    if (Test-Path -LiteralPath $FilePath) {
        Start-Process explorer.exe -ArgumentList "/select,`"$FilePath`""
        return
    }

    $directory = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrEmpty($directory) -and (Test-Path -LiteralPath $directory)) {
        Start-Process explorer.exe -ArgumentList $directory
    }
}

function Invoke-ScriptEncryption {
    param([hashtable]$Settings)

    try {
        $data = [System.IO.File]::ReadAllBytes($Settings.InputPath)
        $package = ConvertTo-EncryptedPackage -Data $data -Password $Settings.Password
        $package.StartupMessage = $Settings.StartupMessage
        $package.MessageDisplayMode = $Settings.MessageDisplayMode
        $package.PasswordPromptMode = $Settings.PasswordPromptMode
        $package.UseBlankPassword = $Settings.UseBlankPassword
        Save-EncryptedPs1 -Path $Settings.OutputPath -Package $package

        return @{
            Success = $true
            OutputPath = $Settings.OutputPath
        }
    }
    catch [System.IO.IOException] {
        return @{
            Success = $false
            ErrorTitle = 'File error'
            ErrorMessage = $_.Exception.Message
        }
    }
    catch {
        return @{
            Success = $false
            ErrorTitle = 'Encryption failed'
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Show-EncryptionForm {
    param([string]$ScreenshotPath)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $padding = 16
    $browseWidth = 92
    $fieldWidth = 388
    $browseLeft = $padding + $fieldWidth + 8

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PowerShell Script Encryptor $Script:ProjectVersion"
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.ClientSize = New-Object System.Drawing.Size(524, 472)
    $form.FormBorderStyle = 'FixedDialog'
    $form.StartPosition = 'CenterScreen'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $inputLabel = New-Object System.Windows.Forms.Label
    $inputLabel.Text = 'Input file:'
    $inputLabel.AutoSize = $true
    $inputLabel.Left = $padding
    $inputLabel.Top = 14
    $form.Controls.Add($inputLabel)

    $inputBox = New-Object System.Windows.Forms.TextBox
    $inputBox.ReadOnly = $true
    $inputBox.Width = $fieldWidth
    $inputBox.Left = $padding
    $inputBox.Top = 34
    $form.Controls.Add($inputBox)

    $browseInput = New-Object System.Windows.Forms.Button
    $browseInput.Text = 'Browse...'
    $browseInput.Width = $browseWidth
    $browseInput.Left = $browseLeft
    $browseInput.Top = 33
    $browseInput.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select file to encrypt'
        $dialog.Filter = 'PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*'
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $inputBox.Text = $dialog.FileName
        }
    })
    $form.Controls.Add($browseInput)

    $outputLabel = New-Object System.Windows.Forms.Label
    $outputLabel.Text = 'Output file:'
    $outputLabel.AutoSize = $true
    $outputLabel.Left = $padding
    $outputLabel.Top = 66
    $form.Controls.Add($outputLabel)

    $outputBox = New-Object System.Windows.Forms.TextBox
    $outputBox.ReadOnly = $true
    $outputBox.Width = $fieldWidth
    $outputBox.Left = $padding
    $outputBox.Top = 86
    $form.Controls.Add($outputBox)

    $browseOutput = New-Object System.Windows.Forms.Button
    $browseOutput.Text = 'Browse...'
    $browseOutput.Width = $browseWidth
    $browseOutput.Left = $browseLeft
    $browseOutput.Top = 85
    $browseOutput.Add_Click({
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Title = 'Save encrypted file'
        $dialog.DefaultExt = 'enc.ps1'
        $dialog.Filter = 'Encrypted PowerShell (*.enc.ps1)|*.enc.ps1|PowerShell scripts (*.ps1)|*.ps1|All files (*.*)|*.*'
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $outputBox.Text = $dialog.FileName
        }
    })
    $form.Controls.Add($browseOutput)

    $startupLabel = New-Object System.Windows.Forms.Label
    $startupLabel.Text = 'Startup message (optional, multiple lines supported):'
    $startupLabel.AutoSize = $false
    $startupLabel.Width = 492
    $startupLabel.Height = 18
    $startupLabel.Left = $padding
    $startupLabel.Top = 118
    $form.Controls.Add($startupLabel)

    $startupBox = New-Object System.Windows.Forms.TextBox
    $startupBox.Multiline = $true
    $startupBox.AcceptsReturn = $true
    $startupBox.ScrollBars = 'Vertical'
    $startupBox.Width = 492
    $startupBox.Height = 88
    $startupBox.Left = $padding
    $startupBox.Top = 138
    $form.Controls.Add($startupBox)

    $messageGroup = New-Object System.Windows.Forms.GroupBox
    $messageGroup.Text = 'Show startup message via'
    $messageGroup.Width = 240
    $messageGroup.Height = 56
    $messageGroup.Left = $padding
    $messageGroup.Top = 238
    $form.Controls.Add($messageGroup)

    $messageBoxRadio = New-Object System.Windows.Forms.RadioButton
    $messageBoxRadio.Text = 'MessageBox'
    $messageBoxRadio.AutoSize = $true
    $messageBoxRadio.Left = 16
    $messageBoxRadio.Top = 22
    $messageGroup.Controls.Add($messageBoxRadio)

    $messageConsoleRadio = New-Object System.Windows.Forms.RadioButton
    $messageConsoleRadio.Text = 'Console'
    $messageConsoleRadio.AutoSize = $true
    $messageConsoleRadio.Left = 120
    $messageConsoleRadio.Top = 22
    $messageConsoleRadio.Checked = $true
    $messageGroup.Controls.Add($messageConsoleRadio)

    $passwordPromptGroup = New-Object System.Windows.Forms.GroupBox
    $passwordPromptGroup.Text = 'Ask for password via'
    $passwordPromptGroup.Width = 240
    $passwordPromptGroup.Height = 56
    $passwordPromptGroup.Left = 268
    $passwordPromptGroup.Top = 238
    $form.Controls.Add($passwordPromptGroup)

    $passwordWindowRadio = New-Object System.Windows.Forms.RadioButton
    $passwordWindowRadio.Text = 'Window'
    $passwordWindowRadio.AutoSize = $true
    $passwordWindowRadio.Left = 16
    $passwordWindowRadio.Top = 22
    $passwordPromptGroup.Controls.Add($passwordWindowRadio)

    $passwordConsoleRadio = New-Object System.Windows.Forms.RadioButton
    $passwordConsoleRadio.Text = 'Console'
    $passwordConsoleRadio.AutoSize = $true
    $passwordConsoleRadio.Left = 120
    $passwordConsoleRadio.Top = 22
    $passwordConsoleRadio.Checked = $true
    $passwordPromptGroup.Controls.Add($passwordConsoleRadio)

    $passwordLabel = New-Object System.Windows.Forms.Label
    $passwordLabel.Text = 'Password (leave blank for no password):'
    $passwordLabel.AutoSize = $true
    $passwordLabel.Left = $padding
    $passwordLabel.Top = 306
    $form.Controls.Add($passwordLabel)

    $passwordBox = New-Object System.Windows.Forms.TextBox
    $passwordBox.UseSystemPasswordChar = $true
    $passwordBox.Width = 492
    $passwordBox.Left = $padding
    $passwordBox.Top = 326
    $form.Controls.Add($passwordBox)

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = $Script:ProjectVersion
    $versionLabel.AutoSize = $true
    $versionLabel.Left = $padding
    $versionLabel.Top = 352
    $form.Controls.Add($versionLabel)

    $creditLabel = New-Object System.Windows.Forms.LinkLabel
    $creditLabel.Text = $Script:ProjectUrl
    $creditLabel.AutoSize = $true
    $creditLabel.Left = $padding + 56
    $creditLabel.Top = 352
    $projectUrl = $Script:ProjectUrl
    $creditLabel.Add_LinkClicked({
        Start-Process $projectUrl
    })
    $form.Controls.Add($creditLabel)

    $buttonPanelTop = 390
    $encryptButton = New-Object System.Windows.Forms.Button
    $encryptButton.Text = 'Encrypt'
    $encryptButton.Width = 100
    $encryptButton.Left = 304
    $encryptButton.Top = $buttonPanelTop
    $encryptButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($inputBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Please select an input file.',
                'Validation',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }
        if (-not (Test-Path -LiteralPath $inputBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                'The input file does not exist.',
                'Validation',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($outputBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                'Please select an output file.',
                'Validation',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        $useBlankPassword = [string]::IsNullOrEmpty($passwordBox.Text)
        $password = if ($useBlankPassword) { ' ' } else { $passwordBox.Text }
        $messageDisplayMode = if ($messageConsoleRadio.Checked) { 'console' } else { 'box' }
        $passwordPromptMode = if ($passwordConsoleRadio.Checked) { 'console' } else { 'box' }

        $settings = @{
            InputPath = $inputBox.Text
            OutputPath = $outputBox.Text
            StartupMessage = $startupBox.Text
            Password = $password
            UseBlankPassword = $useBlankPassword
            MessageDisplayMode = $messageDisplayMode
            PasswordPromptMode = $passwordPromptMode
        }

        $outcome = Invoke-ScriptEncryption -Settings $settings
        if ($outcome.Success) {
            [System.Windows.Forms.MessageBox]::Show(
                "Encrypted file saved to:`n$($outcome.OutputPath)`n`nTo run it:`npowershell -ExecutionPolicy Bypass -File `"$($outcome.OutputPath)`"",
                'Success',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            Open-SavedFileFolder -FilePath $outcome.OutputPath
            return
        }

        [System.Windows.Forms.MessageBox]::Show(
            $outcome.ErrorMessage,
            $outcome.ErrorTitle,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    })
    $form.Controls.Add($encryptButton)
    $form.AcceptButton = $encryptButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Cancel'
    $cancelButton.Width = 100
    $cancelButton.Left = 408
    $cancelButton.Top = $buttonPanelTop
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    if ($ScreenshotPath) {
        $form.Add_Shown({
            Start-Sleep -Milliseconds 300
            $bitmap = New-Object System.Drawing.Bitmap $form.ClientSize.Width, $form.ClientSize.Height
            $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle 0, 0, $form.ClientSize.Width, $form.ClientSize.Height))
            $bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose()
            $form.Close()
        })
    }

    $null = $form.ShowDialog()
    $form.Dispose()
}

function Split-ByteArrayIntoChunks {
    param(
        [byte[]]$Data,
        [int]$MinChunk = 48,
        [int]$MaxChunk = 128
    )

    if ($null -eq $Data -or $Data.Length -eq 0) {
        return ,@(,@())
    }

    $chunks = New-Object System.Collections.Generic.List[byte[]]
    $index = 0
    while ($index -lt $Data.Length) {
        $remaining = $Data.Length - $index
        $maxLen = [Math]::Min($MaxChunk, $remaining)
        $minLen = [Math]::Min($MinChunk, $maxLen)
        if ($minLen -lt 1) {
            $minLen = 1
        }
        $length = if ($maxLen -eq $minLen) {
            $maxLen
        }
        else {
            Get-Random -Minimum $minLen -Maximum ($maxLen + 1)
        }

        $chunk = New-Object byte[] $length
        [Array]::Copy($Data, $index, $chunk, 0, $length)
        $chunks.Add($chunk)
        $index += $length
    }

    return ,$chunks.ToArray()
}

function New-DecoyByteChunks {
    param([int]$Count = 2)

    $decoys = New-Object System.Collections.Generic.List[byte[]]
    for ($i = 0; $i -lt $Count; $i++) {
        $decoys.Add((Get-RandomBytes -Length (Get-Random -Minimum 24 -Maximum 96)))
    }
    return ,$decoys.ToArray()
}

function Format-ByteChunkArraysLiteral {
    param([object[]]$Chunks)

    $formatted = foreach ($chunk in $Chunks) {
        '[byte[]]@(' + (Format-ByteArrayLiteral -Bytes ([byte[]]$chunk)) + ')'
    }
    return ($formatted -join ',')
}

function Build-ScatteredChunks {
    param(
        [byte[][]]$RealChunks,
        [int]$DecoyCount
    )

    $decoys = New-DecoyByteChunks -Count $DecoyCount
    $totalSlots = $RealChunks.Count + $decoys.Count
    $slots = @(0..($totalSlots - 1) | Sort-Object { Get-Random })

    $array = New-Object object[] $totalSlots
    $order = New-Object int[] $RealChunks.Count

    $realSlots = @($slots[0..($RealChunks.Count - 1)] | Sort-Object)
    for ($i = 0; $i -lt $RealChunks.Count; $i++) {
        $slot = $realSlots[$i]
        $array[$slot] = $RealChunks[$i]
        $order[$i] = $slot
    }

    $decoySlots = @($slots[$RealChunks.Count..($totalSlots - 1)])
    for ($j = 0; $j -lt $decoys.Count; $j++) {
        $array[$decoySlots[$j]] = $decoys[$j]
    }

    return @{
        Chunks = [object[]]$array
        Order = [int[]]$order
    }
}

function Format-ByteArrayLiteral {
    param([byte[]]$Bytes)

    return (($Bytes | ForEach-Object { '0x{0:X2}' -f $_ }) -join ',')
}

function ConvertTo-EncryptedPackage {
    param(
        [byte[]]$Data,
        [string]$Password
    )

    Add-Type -AssemblyName System.Security
    Add-Type -AssemblyName System.IO.Compression

    $compressed = Compress-Bytes -Data $Data
    $key = Get-RandomBytes -Length 32
    $iv = Get-RandomBytes -Length 16

    $ciphertext = Protect-AesBytes -Plaintext $compressed -Key $key -IV $iv

    $keyMaterial = New-Object byte[] 48
    [Array]::Copy($key, 0, $keyMaterial, 0, 32)
    [Array]::Copy($iv, 0, $keyMaterial, 32, 16)

    $wrapped = Protect-KeyMaterialWithPassword -KeyMaterial $keyMaterial -Password $Password

    $cipherSplit = Build-ScatteredChunks -RealChunks (Split-ByteArrayIntoChunks -Data $ciphertext) -DecoyCount (Get-Random -Minimum 2 -Maximum 4)
    $keySplit = Build-ScatteredChunks -RealChunks (Split-ByteArrayIntoChunks -Data $wrapped.WrappedKey) -DecoyCount (Get-Random -Minimum 2 -Maximum 4)

    return @{
        CipherChunks = $cipherSplit.Chunks
        CipherOrder = $cipherSplit.Order
        KeyChunks = $keySplit.Chunks
        KeyOrder = $keySplit.Order
        Salt = $wrapped.Salt
        WrapIv = $wrapped.WrapIv
    }
}

function Get-Ps1Wrapper {
    param([hashtable]$Package)

    $cipherOrderLiteral = ($Package.CipherOrder -join ',')
    $keyOrderLiteral = ($Package.KeyOrder -join ',')
    $cipherChunksLiteral = Format-ByteChunkArraysLiteral -Chunks $Package.CipherChunks
    $keyChunksLiteral = Format-ByteChunkArraysLiteral -Chunks $Package.KeyChunks
    $saltLiteral = Format-ByteArrayLiteral -Bytes $Package.Salt
    $wrapIvLiteral = Format-ByteArrayLiteral -Bytes $Package.WrapIv
    $startupMessageLiteral = Format-StartupMessageLiteral -Message $Package.StartupMessage
    $messageDisplayMode = if ($Package.MessageDisplayMode -eq 'console') { 'console' } else { 'box' }
    $passwordPromptMode = if ($Package.PasswordPromptMode -eq 'console') { 'console' } else { 'box' }
    $useBlankPasswordFlag = if ($Package.UseBlankPassword) { '1' } else { '0' }

    (@(
        '#requires -Version 5.1'
        'param([string]$Password='''')'
        '$ErrorActionPreference=''Stop'''
        "`$a1=@($cipherOrderLiteral)"
        "`$a2=@($cipherChunksLiteral)"
        "`$a3=@($keyOrderLiteral)"
        "`$a4=@($keyChunksLiteral)"
        "`$a5=@($saltLiteral)"
        "`$a6=@($wrapIvLiteral)"
        "`$m0='$startupMessageLiteral'"
        "`$m1='$messageDisplayMode'"
        "`$m2='$passwordPromptMode'"
        "`$m3=$useBlankPasswordFlag"
        '$b1={param($o,$c)$len=0;0..($o.Length-1)|ForEach-Object{$len+=$c[$o[$_]].Length};$out=New-Object byte[] $len;$p=0;0..($o.Length-1)|ForEach-Object{$ch=[byte[]]$c[$o[$_]];[Array]::Copy($ch,0,$out,$p,$ch.Length);$p+=$ch.Length};$out}'
        '$b3=''System.Security'''
        '$b4=''System.IO.Compression'''
        '$b5=''System.Windows.Forms'''
        'Add-Type -AssemblyName $b3'
        'Add-Type -AssemblyName $b4'
        "`$b6='$($Script:ProjectUrl)'"
        "`$b7='$($Script:ProjectVersion)'"
        'Write-Output $b6'
        'Write-Output $b7'
        'if(-not [string]::IsNullOrEmpty($m0)){$msg=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m0));if($m1 -eq ''console''){Write-Output $msg}else{Add-Type -AssemblyName $b5;[System.Windows.Forms.MessageBox]::Show($msg,''Message'',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}}'
        '$p1=& $b1 $a1 $a2'
        '$w1=& $b1 $a3 $a4'
        'if($Password -eq '' ''){}elseif([string]::IsNullOrEmpty($Password)){if($m3 -eq 1){$Password='' ''}elseif($m2 -eq ''console''){$q=Read-Host -AsSecureString ''Password'';$z=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($q);try{$Password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($z)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($z)}}else{Add-Type -AssemblyName $b5;$f=New-Object System.Windows.Forms.Form;$f.Text=''Password'';$f.Width=380;$f.Height=150;$f.FormBorderStyle=''FixedDialog'';$f.StartPosition=''CenterScreen'';$f.MaximizeBox=$false;$f.MinimizeBox=$false;$f.TopMost=$true;$l=New-Object System.Windows.Forms.Label;$l.Text=''Enter password:'';$l.AutoSize=$true;$l.Left=12;$l.Top=18;$f.Controls.Add($l);$t=New-Object System.Windows.Forms.TextBox;$t.UseSystemPasswordChar=$true;$t.Width=330;$t.Left=12;$t.Top=42;$f.Controls.Add($t);$b=New-Object System.Windows.Forms.Button;$b.Text=''OK'';$b.Width=90;$b.Left=170;$b.Top=78;$b.DialogResult=[System.Windows.Forms.DialogResult]::OK;$f.Controls.Add($b);$f.AcceptButton=$b;$c=New-Object System.Windows.Forms.Button;$c.Text=''Cancel'';$c.Width=90;$c.Left=252;$c.Top=78;$c.DialogResult=[System.Windows.Forms.DialogResult]::Cancel;$f.Controls.Add($c);$f.CancelButton=$c;if($f.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK){return};$Password=$t.Text;$f.Dispose()}}'
        '$z1=[Text.Encoding]::UTF8.GetBytes($Password)'
        '$z2=New-Object Security.Cryptography.Rfc2898DeriveBytes($z1,$a5,100000)'
        '$z3=$z2.GetBytes(32)'
        '$z2.Dispose()'
        '$c0=[Security.Cryptography.Aes]::Create()'
        '$c0.Key=$z3'
        '$c0.IV=$a6'
        '$c0.Mode=[Security.Cryptography.CipherMode]::CBC'
        '$c0.Padding=[Security.Cryptography.PaddingMode]::PKCS7'
        '$k1=$c0.CreateDecryptor().TransformFinalBlock($w1,0,$w1.Length)'
        '$k2=New-Object byte[] 32'
        '$k3=New-Object byte[] 16'
        '[Array]::Copy($k1,0,$k2,0,32)'
        '[Array]::Copy($k1,32,$k3,0,16)'
        '$c1=[Security.Cryptography.Aes]::Create()'
        '$c1.Key=$k2'
        '$c1.IV=$k3'
        '$c1.Mode=[Security.Cryptography.CipherMode]::CBC'
        '$c1.Padding=[Security.Cryptography.PaddingMode]::PKCS7'
        '$p2=$c1.CreateDecryptor().TransformFinalBlock($p1,0,$p1.Length)'
        '$m1=New-Object IO.MemoryStream(,$p2)'
        '$m2=New-Object IO.Compression.GzipStream($m1,[IO.Compression.CompressionMode]::Decompress)'
        '$m3=New-Object IO.MemoryStream'
        '$m2.CopyTo($m3)'
        '$t1=[Text.Encoding]::UTF8.GetString($m3.ToArray())'
        '$r1=$PSScriptRoot'
        'if([string]::IsNullOrEmpty($r1)){$r1=Split-Path -Parent $MyInvocation.MyCommand.Path}'
        '$r2=$MyInvocation.MyCommand.Path'
        '$s1=[ScriptBlock]::Create("param([string]`$PSScriptRoot,[string]`$PSCommandPath)`n"+$t1)'
        '& $s1 -PSScriptRoot $r1 -PSCommandPath $r2'
    )) -join "`r`n"
}

function Save-EncryptedPs1 {
    param(
        [string]$Path,
        [hashtable]$Package
    )

    $content = Get-Ps1Wrapper -Package $Package
    $content = $content -replace "`r?`n", "`r`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Main {
    Write-Host "PowerShell Script Encryptor $Script:ProjectVersion"
    Write-Host $Script:ProjectUrl
    Show-EncryptionForm
}

if ($MyInvocation.InvocationName -ne '.') {
    Main
}
