
## Steps to create a new windows builder on Azure

### Creating the VM

1. Use the "Windows (Windows Server 2022 Datacenter Azure Edition)" image.
2. Use the `r-hub` resource group.
3. Add a user called `rhub`, with the appropriate password.
4. Turn off automatic updates.
4. Create the VM.

### Manual configuration

1. Set up networking, so RDP is only allowed for a single IP address.
1. Log in.
1. Install updates.
1. Install git.
1. Install Google Chrome.
1. Install pandoc.
1. Install rig.
1. With rig install R-oldrel, R-release, R-devel, Rtools40, Rtools42.
1. Set up R-next.bat and R-oldrel.bat aliases.
1. Install MikTex. Allow adding missing packages automatically.
1. Update all Rtools40 packages.
1. Install java, make sure it is on the path. (Probably needs a powershell
   restart.)
1. Set the time zone. Originally it is set to UTC, and you can change it
   to anything you like.
1. Install aspell and the en dictionary with Rtools42 pacman, from the
   msys2 repo. Put it on the PATH.
1. Set the `MIKTEX_ENV_EXCEPTION_PATH` system env var to point to
   `c:\temp`, make sure it is writeable for everyone.
   https://github.com/r-hub/rhub/issues/503
1. Download the Jenkins client from
   https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/2.2/ and place it in the rhub user's home.
1. Get the wincheck scripts and put then in Documents:
   ```
   git clone https://github.com/r-hub/wincheck.git
   cp wincheck/*.ps1 Documents/
   ```

### Connect to Jenkins

1. Allow the builder machine on the AWS firewall to connect to
   Jenkins, to ports 8080 and 50000.
1. Allow the machine to update the artifacts, in the Azure Firewall.
1. Create a jenkins.bat script for this:
   ```
   java "-Dfile.encoding=UTF8" -jar .\swarm-client-2.2-jar-with-dependencies.jar -master http://jenkins.r-hub.io:8080 -executors 4 -labels "swarm slave windows windows-ucrt rtools4" -username admin -password <the-jenkins-password>
   ```
1. Run jenkins.bat from an admin shell to connect to Jenkins.
1. In Jenkins create a keepalive job that runs on this machine only. Copying an existing job
   is the easiest.

Voila, you have a new windows builder.
