
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
    [string]$envVars,
    [Parameter(Position=7)]
    [string]$build,
    [Parameter(Position=8)]
    [string]$pkgname

)

if ($build -eq "") {
    $build = "false"
}

if ($pkgname -eq "") {
    $pkgname  = $package.Substring(0, $package.IndexOf("_"))
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Verbose ( "Checking " + $jobid )

Write-Host ">>>>>============== Creating new user"

# ------------------------------------------------------------------

$username  = "USER" + (-join ((65..90) + (97..122) |
  Get-Random -Count 10 |
  % {[char]$_}))
$password  = (-join ((65..90) + (97..122) |
  Get-Random -Count 10 |
  % {[char]$_}))
$password = ( $password + "xX1!" )

Function Cleanup {
    if ($username) { 
	taskkill /f /fi "USERNAME eq $username"
	& 'c:\program files\git\bin\bash' -c ( "rm -rf /c/users/" + $username )
	net user $username /delete
    }
}

Trap {
    Cleanup
    Exit
}

# ------------------------------------------------------------------
Write-Verbose "Creating new user..."

net user $username $password /add
$secpasswd = (ConvertTo-SecureString -String $password -AsPlainText -Force)
$credential = New-Object System.Management.Automation.PSCredential `
	-ArgumentList @($username, $secpasswd)

Start-Process cmd /c -WindowStyle Hidden -Wait -Credential $credential `
	-ErrorAction SilentlyContinue `
	-workingdirectory "c:\"
$user = Get-WmiObject -Class win32_useraccount -Filter "LocalAccount=True AND Name='$username'"
$userprofile = Get-WmiObject -Class win32_userprofile -Filter "SID='$($user.sid)'"
$homefull = $userprofile.localpath

fsutil quota modify c: 1000000000 1000000000 $username

cp slave.ps1 $homefull
mkdir "$homefull\.R"
if ($env:R_MAKEVARS_WIN) {
    cp "$env:R_MAKEVARS_WIN" $homefull\.R\Makevars.win
}
if ($env:R_MAKEVARS_WIN64) {
    cp "$env:R_MAKEVARS_WIN64" $homefull\.R\Makevars.win64
}

Write-Host ">>>>>============== Downloading and unpacking package file"

# --------------------------------------------------------------------
Write-Verbose ( "Downloading " + $url )

Invoke-WebRequest -Uri $url -OutFile ( $homefull + "\" + $package )

# --------------------------------------------------------------------
# R-devel CRAN binaries are x64 only, but the check is still multi-arch,
# so it will fail if there is a dependency with compiled code.
# Work around this by running it on x64 only
If ($rversion -eq "r-devel") {
    $checkArgs = $checkArgs + " --no-multiarch"
}

# --------------------------------------------------------------------
# We need to pass these in temporary files, becuase it is hard
# escape them, and if I pass them as environment variables, then
# PowerShell will not use the specified user (!!!)

$argsFile = ( $homefull + "\" + "rhub-args.txt" )
$envsFile = ( $homefull + "\" + "rhub-envs.txt" )
if (! $checkArgs -eq "") { $checkArgs | Out-File $argsFile }
echo '_R_CHECK_FORCE_SUGGESTS_=false' | Out-File $envsFile
echo 'R_COMPILE_AND_INSTALL_PACKAGES=never' | Out-File -Append $envsFile
echo 'R_REMOTES_STANDALONE=true' | Out-File -Append $envsFile
echo 'R_REMOTES_NO_ERRORS_FROM_WARNINGS=true' | Out-File -Append $envsFile
if (! $envVars -eq "") { $envVars | Out-File -Append $envsFile }

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
} ElseIf ($rversion -eq "r-testing") {
    $realrversion = "testing"
} Else {
    $realrversion = $rversion
}

# ------------------------------------------------------------------
Write-Verbose "Starting sub-process as new user..."

$arguments = ( '-executionpolicy bypass' + ' ' +
	       '-command .\slave.ps1' + ' ' +
	       $package + ' ' +
	       $pkgname + ' ' +
	       $realrversion + ' ' +
	       $build
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
	       LoadUserProfile = $true
	       WorkingDirectory = $homefull
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

Cleanup
