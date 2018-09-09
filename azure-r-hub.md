
## Steps to create a new windows builder on Azure

### Creating the VM

1. Use the latest image. Currently this is `win-builder-2016-10-03`.
2. Use the `r-hub` resource group.
3. Add a user called `rhub`, with the appropriate password.
4. Create the VM.

### Manual configuration

This is needed unfortunately, I don't know why it is not captured in the image.

1. Turn off automatic daily updates, because they can reboot the machine. Also turn off the "Any user can update" "feature". (Seriously MS?)

2. Set the time zone. Originally it is set to UTC, and you can change it to anything you like.

3. Allow the builder machine on the AWS firewall.

### Connect to Jenkins

Run this from a powershell command line, from the `Documents` folder of the `rhub` user:

```
java "-Dfile.encoding=UTF8" -jar .\swarm-client-2.2-jar-with-dependencies.jar -master http://jenkins.r-hub.io:8080 -executors 4 -labels "swarm slave windows" -username admin -password <the-jenkins-password>
```

Voila, you have a new windows builder.
