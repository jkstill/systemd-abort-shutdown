
# Reboot Protection

What happens if you try to reboot a linux server when the /boot partition is full?

The server will not boot, as there is a need for some free space when Linux boots.

This can be quite a predicament if that server happens to be in a remote location.

Here's one way to deal with that; create a service that will abort a shutdown if certain conditions are not met.

In this case the conditions are:

- insuffcient space /boot 
- insufficient inodes in /boot

If /boot is full, a reboot will fail, as there must be some free space in /boot.

If /boot is near full, a reboot may fail.

The solution provided here will prevent the following commands from working at all, as long as the service described is running:

- reboot
- shutdown now
- shutdown +N

When the `reboot-abort.pl` script is installed and configured, the following are the only methods to reboot from the command line:

- via `reboot-abort.pl --command [reboot|halt|shutdown]` 
- disable protection via `reboot-abort.pl --allow`
- remove protection vai `reboot-abort.pl --erase`

This article is useful for RedHat Linux 7+ and variants, such as Oracle Linux.

Using the systemctl utility I created a service that prevents a reboot or shutdown if the /boot filesystem is using more then 15% of available space.
The 15% was chosen just to see the utility work, as /boot on this test box is 22% used.

The same applies to inodes; if more than 15% of inodes are used, a reboot is not possible until the protector service is disabled.

When this method is used, `reboot`,  `shutdown +0` and `shutdown` now will not work at all.

```text

[root@ora75-mule ~]# reboot
Failed to start reboot.target: Operation refused, unit reboot.target may be requested by dependency only (it is configured to refuse manual start/stop).
See system logs and 'systemctl status reboot.target' for details.

Broadcast message from root@ora75-mule.jks.com on pts/1 (Wed 2020-04-08 19:42:20 EDT):

The system is going down for reboot NOW!

[root@ora75-mule ~]#
[root@ora75-mule ~]# shutdown now
Failed to start poweroff.target: Operation refused, unit poweroff.target may be requested by dependency only (it is configured to refuse manual start/stop).
See system logs and 'systemctl status poweroff.target' for details.

Broadcast message from root@ora75-mule.jks.com on pts/1 (Wed 2020-04-08 19:42:24 EDT):

The system is going down for power-off NOW!

[root@ora75-mule ~]# tail -0f /var/log/messages

Broadcast message from root@ora75-mule.jks.com (Wed 2020-04-08 19:43:28 EDT):

system patching

Apr  8 19:43:28 ora75-mule systemd-shutdownd: Failed to start poweroff.target: Operation refused, unit poweroff.target may be requested by dependency only (it is configured to refuse manual start/stop).
Apr  8 19:43:28 ora75-mule systemd-shutdownd: See system logs and 'systemctl status poweroff.target' for details.


```

## Preventing Reboots

The following files can be used to prevent a reboot:

```text
[root@ora75-mule ~]# ls -l /run/systemd/system/*/reboot-abort.conf
-rw-r--r-- 1 root root 29 Apr  8 19:34 /run/systemd/system/halt.target.d/reboot-abort.conf
-rw-r--r-- 1 root root 29 Apr  8 19:34 /run/systemd/system/poweroff.target.d/reboot-abort.conf
-rw-r--r-- 1 root root 29 Apr  8 19:34 /run/systemd/system/reboot.target.d/reboot-abort.conf
```

The contents of each file:

```text
[Unit]
RefuseManualStart=yes
```

Commands used to reboot the sytem will fail when these file are present and the contents are `RefuseManualStart=yes`.

## How to Reboot

The `reboot-abort.pl` script can be used to reboot the server when needed.

The file `/root/.reboot-abort/checks.conf` contains commands that are used to qualify if a reboot will be performed.

These are the contents when initially installed:

```text
[root@ora75-mule ~]# cat ~/.reboot-abort/checks.conf
check:/bin/true
check:/bin/false
check:/root/bin/check-boot-space.sh
```

The premise is simple: each check is run and either fails or succeeds.

If any one of the check programs fails, the attemtp to reboot will be aborted.

As is, the checks file contains `/bin/false`, and so a reboot will never succeed.

Both the `false` and the `true` entries can be commented out:

```text
[root@ora75-mule ~]# cat ~/.reboot-abort/checks.conf
#check:/bin/true
#check:/bin/false
check:/root/bin/check-boot-space.sh
```

The `/root/bin/check-boot-space.sh` script by default fails if the space or inodes are GT 85% capacity in `/boot`.

For testing, these have been changed to 15%.

Now a reboot will be prevented:

```text
[root@ora75-mule ~]# reboot-abort.pl --command reboot
current check: /root/bin/check-boot-space.sh
Check returned negative result
cannot reboot

```

Here the value is set back to 85%, and the reboot succeeds:

```text
[root@ora75-mule ~]# reboot-abort.pl --command reboot
Connection to 192.168.1.220 closed by remote host.
Connection to 192.168.1.220 closed.

```

So that the reboot can take place, `reboot-abort.pl` disables the protection.

The `set-reboot-abort.service` is resonsible for resetting it when the server boots.

This can be checked following a reboot:

```text

[root@ora75-mule ~]# systemctl status set-reboot-abort.service
● set-reboot-abort.service - Start /boot partition full protection - cannot reboot if disk is full
   Loaded: loaded (/etc/systemd/system/set-reboot-abort.service; enabled; vendor preset: disabled)
   Active: inactive (dead) since Wed 2020-04-08 19:58:28 EDT; 16s ago
  Process: 716 ExecStart=/root/bin/reboot-abort.pl --reject (code=exited, status=0/SUCCESS)
 Main PID: 716 (code=exited, status=0/SUCCESS)

Apr 08 19:58:27 ora75-mule.jks.com systemd[1]: Started Start /boot partition full protection - cannot reboot if disk is full.
Apr 08 19:58:27 ora75-mule.jks.com systemd[1]: Starting Start /boot partition full protection - cannot reboot if disk is full...


[root@ora75-mule ~]# cat /run/systemd/system/*/reboot-abort.conf
[Unit]
RefuseManualStart=yes
[Unit]
RefuseManualStart=yes
[Unit]
RefuseManualStart=yes
```

## Installing reboot-abort.pl

- Login as root
- mkdir /root/bin
- copy reboot-abort.pl to /root/bin
- chmod 750 /root/bin/reboot-abort.pl
- reboot-abort.pl --install
- reboot-abort.pl --reject

Verify the installation

- ls -l /run/systemd/system/*/reboot-abort.conf
- cat /run/systemd/system/*/reboot-abort.conf
- systemctl status set-reboot-abort.service
- cat /root/.reboot-abort/checks.conf

If any files already exist, the installer will not overwrite them.

```text
[root@ora75-mule ~]# reboot-abort.pl --install
cowardly refusing to overwrite: /root/bin/check-boot-space.sh
cowardly refusing to overwrite: /root/.reboot-abort/checks.conf
cowardly refusing to overwrite: /etc/systemd/system/set-reboot-abort.service
```

## Disable reboot protection

Reboot protection can be disabled with the `--allow` option.

In the following example the reboot protection is disabled, and the server rebooted.

The protection was reinstated during the boot process.

```text

[root@ora75-mule ~]# cat /run/systemd/system/*/reboot-abort.conf
[Unit]
RefuseManualStart=yes
[Unit]
RefuseManualStart=yes
[Unit]
RefuseManualStart=yes

[root@ora75-mule ~]# reboot-abort.pl --allow

[root@ora75-mule ~]# cat /run/systemd/system/*/reboot-abort.conf
[Unit]
RefuseManualStart=no
[Unit]
RefuseManualStart=no
[Unit]
RefuseManualStart=no


[root@ora75-mule ~]# reboot
Connection to 192.168.1.220 closed by remote host.
Connection to 192.168.1.220 closed.
jkstill@poirot  ~/linux/systemd-abort-shutdown $
>

jkstill@poirot  ~/linux/systemd-abort-shutdown $
>  ssh root@192.168.1.220
Last login: Wed Apr  8 19:58:39 2020 from poirot.jks.com
[root@ora75-mule ~]#
[root@ora75-mule ~]#
[root@ora75-mule ~]# cat /run/systemd/system/*/reboot-abort.conf
[Unit]
RefuseManualStart=yes
[Unit]
RefuseManualStart=yes
[Unit]
RefuseManualStart=yes

```

The reboot, shutdown and halt commands will not be prevented in this state.

## Re-enable reboot protection

```
[root@ora75-mule ~]# cat /run/systemd/system/*/reboot-abort.conf
[Unit]
RefuseManualStart=no
[Unit]
RefuseManualStart=no
[Unit]
RefuseManualStart=no

[root@ora75-mule ~]# reboot-abort.pl --reject

[root@ora75-mule ~]# cat /run/systemd/system/*/reboot-abort.conf
[Unit]
RefuseManualStart=yes
[Unit]
RefuseManualStart=yes
[Unit]
RefuseManualStart=yes
```

## Files

### /root/bin/reboot-abort.pl

The script that drives the reboot protection.

!! Put help here


Create the following files, set the permissions as noted, and follow any other instructions shown.

### /root/bin/check-boot-space.sh

This file exists in the repo, but it is not necessary to copy it, as `reboot-abort.pl` will install it automatically.

### /root/.reboot-abort/checks.conf

The configuration file for checks that may disallow a reboot.


### /etc/systemd/system/set-reboot-abort.service

This file is created by `reboot-abort.pl --install`


```text
[Unit]
Description=Start /boot partition full protection - cannot reboot if disk is full

[Service]
ExecStart=/root/bin/reboot-abort.pl --reject

[Install]
WantedBy=multi-user.target
```

## References

[Managing Services with Systemd Unit Files](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/system_administrators_guide/sect-managing_services_with_systemd-unit_files)

[Managing Services with Sytemd Targets](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/system_administrators_guide/sect-Managing_Services_with_systemd-Targets)


