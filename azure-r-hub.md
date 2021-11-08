
## Steps to create a new windows builder on Azure

### Creating the VM

1. Use the "Windows (Windows Server 2022 Datacenter Azure Edition)" image.
2. Use the `r-hub` resource group.
3. Add a user called `rhub`, with the appropriate password.
4. Create the VM.

### Manual configuration

This is needed unfortunately, I don't know why it is not captured in the image.

1. Set up networking, so RDP is only allowed for a single IP address.
1. Log in.
1. Install updates.
1. Turn off restarts after updates:
   > In the "Local Group Policy Editor", navigate to Computer 
   > Configuration > Administrative Templates > Windows Components > Windows
   > Update. Enable the "Configure Automatic Updates" policy and set it to
   > "2". Enable the "No auto-restart with logged on users for scheduled
   >  automatic updates installations" policy.
1. Install choco.
1. Use choco to install git and Google Chrome.
1. Download R and Rtools from https://www.r-project.org/nosvn/winutf8/ucrt3/
   and install them.
1. Create the rhub user's package library, to protect against installing
   packages into the system lib:
   ```
   dir.create(Sys.getenv("R_LIBS_USER"), recursive=TRUE)
   ```
1. Set the time zone. Originally it is set to UTC, and you can change it
   to anything you like.
1. Download the Jenkins client from
   https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/2.2/ and place it in the rhub user's home.
1. Install java, make sure it is on the path. (Probably needs a powershell
   restart.)
1. Get the wincheck scripts and put then in Documents:
   ```
   git clone https://github.com/r-hub/wincheck.git
   cp wincheck/*.ps1 Documents/
   ```
1. Install MikTex. Allow adding missing packages automatically.

### Connect to Jenkins

1. Allow the builder machine on the AWS firewall to connect to
   Jenkins, to ports 8080 and 50000.
1. Allow the machine to update the artifacts, in the Azure Firewall.
1. Create a jenkins.bat script for this:
   ```
   java "-Dfile.encoding=UTF8" -jar .\swarm-client-2.2-jar-with-dependencies.jar -master http://jenkins.r-hub.io:8080 -executors 4 -labels "swarm slave windows" -username admin -password <the-jenkins-password>
   ```
1. Run jenkins.bat to connect to Jenkins.
1. In Jenkins create a keepalive job that runs on this machine only. Copying an existing job
   is the easiest.

Voila, you have a new windows builder.
