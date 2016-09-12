
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$package,
    [Parameter(Mandatory=$True,Position=2)]
    [string]$url

)

Write-Verbose ( "Checking " + $url )

Import-Module Carbon -Verbose:$False

# ------------------------------------------------------------------

$username  = "USER" + (-join ((65..90) + (97..122) |
  Get-Random -Count 10 |
  % {[char]$_}))
$password  = (-join ((65..90) + (97..122) |
  Get-Random -Count 20 |
  % {[char]$_}))
$homedrive = "C:"
$homedir   = ( "\Users\" + $username )
$homefull  = ( $homedrive + $homedir )

# ------------------------------------------------------------------
Write-Verbose "Creating new user..."

$secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential `
  ($username, $secpasswd)

Install-User `
  -Credential $mycreds `
  -Description "Dummy user" `
  -FullName "Dummy user for Jenkins"

# ------------------------------------------------------------------
Write-Verbose "Creating home directory..."

mkdir $homefull | Out-Null

# --------------------------------------------------------------------
Write-Verbose ( "Downloading " + $url )

# $package = $url.Substring($url.LastIndexOf("/") + 1)
$pkgname  = $package.Substring(0, $package.IndexOf("_"))

Invoke-WebRequest -Uri $url -OutFile ( $homefull + "\" + $package )

# --------------------------------------------------------------------
Write-Verbose ( "Extracting " + $package )

Push-Location

cd $homefull

tar xzf $package

Pop-Location

# ------------------------------------------------------------------
Write-Verbose "Setting home directory permissions..."

$user = Get-User $username
$user.HomeDirectory = $homedir
$user.HomeDrive = $homedrive
$user.save()

cp slave.ps1 $homefull | Out-Null

$perms = ( $username + ":(OI)(CI)F" )
icacls $homefull /setowner $username /T /L | out-null
icacls $homefull /grant $perms /T | out-null

# ------------------------------------------------------------------
Write-Verbose "Starting sub-process as new user..."

$arguments = ( '-command .\slave.ps1' + ' ' + $package + ' ' + $pkgname )

$StartInfo = New-Object System.Diagnostics.ProcessStartInfo -Property @{
               Filename = 'powershell.exe'
	       Arguments = $arguments
	       UseShellExecute = $false
	       RedirectStandardOutput = $true
	       RedirectStandardError = $true
	       CreateNoWindow = $true
	       UserName = $username
	       Password = $secpasswd
	       WorkingDirectory = $homedir
}

# Create new process
$Process = New-Object System.Diagnostics.Process

# Assign previously created StartInfo properties
$Process.StartInfo = $StartInfo

# Register Object Events for stdin\stdout reading
$OutEvent = Register-ObjectEvent `
  -InputObject $Process `
  -EventName OutputDataReceived `
  -Action { Write-Host $Event.SourceEventArgs.Data }
$ErrEvent = Register-ObjectEvent `
  -InputObject $Process `
  -EventName ErrorDataReceived `
  -Action { Write-Host $Event.SourceEventArgs.Data }

# Start process
[void]$Process.Start()

# Begin reading stdin\stdout
$Process.BeginOutputReadLine()
$Process.BeginErrorReadLine()

$Process.WaitForExit()

# Unregister events
$OutEvent.Name, $ErrEvent.Name |
    ForEach-Object {Unregister-Event -SourceIdentifier $_}

# ------------------------------------------------------------------
Write-Verbose "Cleaning up, deleting files and user"

Uninstall-User $username | Out-Null
rmdir -Recurse $homedir | Out-Null
