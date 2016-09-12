
## Steps to create a win-builder image on Azure

### Creating the VM

1. Create a classic virtual machine, the RM type is not supported by the Jenkins plugin that will start up the image.
1. Choose Windows Server 2008 R2 SP1 as OS, and Classic deployment model.
1. Name is `win-builder-x`, username is `rhub`, password is as desired. Resource group should be `r-hub` (or `rhub2`?), Location East US.
1. A `DS2_V2` image is fine. Basically any image with multiple cores would do.
1. Storage account should be `rhub2 (classic)`. Domain name `win-builder-x`. Virtual network `rhub2`. Subnet default. Private IP address can by dynamic, virtual IP address as well. Endpoints are fine as the default. No extensions. Monitoring can be enabled.
1. Wait until deployment finishes. The machine might be up, but not yet configured. E.g. if the user is still called `Administrator` when you are trying to log in, then wait a bit more.

### Configuring it

1. Log in to the virtual machine via RDP. If you cannot reach the machine, then you might need to clear your IP in the security group of the machine. If the user is called `Administrator`, then reset the password for the `rhub` user from the Portal.
1. Install Google Chrome from https://google.com/chrome. You'll need to whitelist a ridiculous number of sites in IE.
1. The Carbon PowerShell extension needs PowerShell 4.x at least, so we need to download and install PowerShell. It is part of the Windows Management Framework. More info here: http://social.technet.microsoft.com/wiki/contents/articles/21016.how-to-install-windows-powershell-4-0.aspx Download from here: https://www.microsoft.com/en-gb/download/details.aspx?id=40855 You'll need the 6.1 version for x64. Install it, restart the machine.
1. Set up PowerShell to look nicer. E.g. use a bigger TrueType font. It is also worth installing PSReadline and PSGet, see http://psget.net/ and https://bitbucket.org/kshah29/psreadline
1. Install Carbon from here: http://get-carbon.org/about_Carbon_Installation.html I used version 2.2.0.
```
curl -OutFile carbon-2.2.0.zip https://bitbucket.org/splatteredbits/carbon/downloads/Carbon-2.2.0.zip
```
Copy the `Carbon` directory into `C:\Users\rhub\Documents\WindowsPowerShell\Modules`
1. Allow running PowerShell scripts:
```
Set-ExecutionPolicy RemoteSigned
```
1. Start a new instance of PowerShell, and Carbon should be loaded.
1. Install the desired R and Rtools version(s). See the compatibility matrix here: https://cran.r-project.org/bin/windows/Rtools/
1. Install Java from Oracle, both the 32 bit and the 64 bit version.

### Capturing it as an image

The tutorial for this is here: https://azure.microsoft.com/en-gb/documentation/articles/virtual-machines-windows-classic-capture-image/
