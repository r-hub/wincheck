
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$package,
    [Parameter(Mandatory=$True,Position=2)]
    [string]$jobid,
    [Parameter(Mandatory=$True,Position=3)]
    [string]$url,
    [Parameter(Mandatory=$True,Position=4)]
    [string]$rversion,
    [Parameter(Position=5)]
    [string]$checkArgs,
    [Parameter(Position=6)]
    [string]$envVars
)

Write-Verbose ( "Checking " + $jobid )

Import-Module Carbon -Verbose:$False

Write-Host ">>>>>============== Creating new user"

# ------------------------------------------------------------------

$username  = "USER" + (-join ((65..90) + (97..122) |
  Get-Random -Count 10 |
  % {[char]$_}))
$password  = (-join ((65..90) + (97..122) |
  Get-Random -Count 20 |
  % {[char]$_}))
$password = ( $password + "xX1!" )
$homedrive = "C:"
$homedir   = ( "\Users\" + $username )
$homefull  = ( $homedrive + $homedir )

# ------------------------------------------------------------------
Write-Verbose "Copy local software..."

if ( -not ( test-path "D:\Compiler" ) ) {
  Copy-Item -Recurse -Force C:\Users\rhub\Documents\local_soft\Compiler d:\ | Out-Null
}
if ( -not ( test-path "D:\RCompile" ) ) {
  Copy-Item -Recurse -Force C:\Users\rhub\Documents\local_soft\RCompile d:\ | Out-Null
}

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
mkdir ( $homefull + "\TEMP" ) | Out-Null

Write-Host ">>>>>============== Downloading and unpacking package file"

# --------------------------------------------------------------------
Write-Verbose ( "Downloading " + $url )

# $package = $url.Substring($url.LastIndexOf("/") + 1)
$pkgname  = $package.Substring(0, $package.IndexOf("_"))

Invoke-WebRequest -Uri $url -OutFile ( $homefull + "\" + $package )

# --------------------------------------------------------------------
# We need to pass these in temporary files, becuase it is hard
# escape them, and if I pass them as environment variables, then
# PowerShell will not use the specified user (!!!)

$argsFile = ( $homefull + "\" + "rhub-args.txt" )
$envsFile = ( $homefull + "\" + "rhub-envs.txt" )
if (! $checkArgs -eq "") { $checkArgs | Out-File $argsFile }
echo '_R_CHECK_FORCE_SUGGESTS_=false' | Out-File $envsFile
if (! $envVars -eq "") { $envVars | Out-File -Append $envsFile }

# --------------------------------------------------------------------
Write-Verbose ( "Extracting " + $package )

Push-Location

cd $homefull

# Need this for tar and gzip
$oldpath = $env:PATH
$env:PATH = 'C:\rtools33\bin;' + $env:PATH
tar xzf $package
$env:PATH = $oldpath

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
Write-Verbose "Getting R version from symbolic name..."

If ($rversion -eq "r-devel") {
    $realrversion = "devel"
} ElseIf ($rversion -eq "r-release") {
    $realrversion = $(ConvertFrom-JSON $(Invoke-WebRequest `
      http://rversions.r-pkg.org/r-release-win).Content).version
} ElseIf ($rversion -eq "r-patched") {
    $realrversion = $(ConvertFrom-JSON $(Invoke-WebRequest `
      http://rversions.r-pkg.org/r-release-win).Content).version + "patched"
} ElseIf ($rversion -eq "r-oldrel") {
    $realrversion = $(ConvertFrom-JSON $(Invoke-WebRequest `
      http://rversions.r-pkg.org/r-oldrel).Content).version
} Else {
    $realrversion = $rversion
}

# ------------------------------------------------------------------
Write-Verbose "Starting sub-process as new user..."

$arguments = ( '-command .\slave.ps1' + ' ' +
	       $package + ' ' +
	       $pkgname + ' ' +
	       $realrversion
	     )

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

do {
   Start-Sleep 1
} while (!$Process.HasExited)

# Unregister events
$OutEvent.Name, $ErrEvent.Name |
    ForEach-Object {Unregister-Event -SourceIdentifier $_}

# ------------------------------------------------------------------
Write-Verbose "Saving artifacts"

mkdir $jobid | Out-Null
cp -Recurse ( $homefull + "\" + $pkgname + ".Rcheck" ) $jobid | Out-Null
cp ( $homefull + "\" + "*.zip" ) $jobid | Out-Null

# ------------------------------------------------------------------
Write-Verbose "Cleaning up, deleting files and user"

Write-Host ">>>>>============== Cleaning up files and user"

Uninstall-User $username | Out-Null
rmdir -Recurse -Force $homedir | Out-Null
