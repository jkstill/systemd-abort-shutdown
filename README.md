
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
- shutdown +0

As you will see, other forms of the shutdown command will succeed, provided the service (as you will soon see) allows it

This article is useful for RedHat Linux 7+ and variants, such as Oracle Linux.

Using the systemctl utility I created a servvices that prevents a reboot or shutdown if the /boot filesystem is using more then 15% of available space.
The 15% was chosen just to see the utility work, as /boot on this test box is 22% used.

The same applies to inodes; if more than 15% of inodes are used, a reboot is not possible until the protector service is disabled.

When this method is used, `reboot`,  `shutdown +0` and `shutdown` now will not work at all.

```text
[root@ora75-mule system]# reboot
Failed to start reboot.target: Transaction contains conflicting jobs 'start' and 'stop' for systemd-reboot.service. Probably contradicting requirement dependencies configured.
See system logs and 'systemctl status reboot.target' for details.

Broadcast message from root@ora75-mule.jks.com on pts/1 (Mon 2020-04-06 19:02:51 EDT):

The system is going down for reboot NOW!

[root@ora75-mule system]#
[root@ora75-mule system]# shutdown now
Failed to start poweroff.target: Transaction contains conflicting jobs 'stop' and 'start' for systemd-poweroff.service. Probably contradicting requirement dependencies configured.
See system logs and 'systemctl status poweroff.target' for details.

Broadcast message from root@ora75-mule.jks.com on pts/1 (Mon 2020-04-06 19:02:58 EDT):

The system is going down for power-off NOW!

[root@ora75-mule system]#
[root@ora75-mule system]# shutdown +0
Shutdown scheduled for Mon 2020-04-06 19:03:04 EDT, use 'shutdown -c' to cancel.
[root@ora75-mule system]#
Broadcast message from root@ora75-mule.jks.com (Mon 2020-04-06 19:03:04 EDT):

The system is going down for power-off NOW!
```

Actually, these commands do not do what I intended.  

The intent was to detect the space usage in `/boot`, and then deny the reboot if there is insuffient space in `/boot`.

This does force the use of the command `shutdown +N` and its variants.

When the shutdown is attempted this way, the service will prevent it if the space is too low:

```text
[root@ora75-mule system]# shutdown -r +1 "Rebooting for Test"
Shutdown scheduled for Mon 2020-04-06 19:07:26 EDT, use 'shutdown -c' to cancel.
[root@ora75-mule system]#
Broadcast message from root@ora75-mule.jks.com (Mon 2020-04-06 19:06:26 EDT):

Rebooting for Test
The system is going down for reboot at Mon 2020-04-06 19:07:26 EDT!


Broadcast message from root@ora75-mule.jks.com (Mon 2020-04-06 19:06:27 EDT):

The system shutdown has been cancelled at Mon 2020-04-06 19:07:27 EDT!


Broadcast message from root@ora75-mule.jks.com (Mon Apr  6 19:06:27 2020):

Space of 22% in /boot is insufficient for reboot
```

And so the reboot was cancelled.

The reboot can be forced by disabling the service:

```text
[root@ora75-mule system]# systemctl disable  bootpart-full-abort-shutdown.service
Removed symlink /etc/systemd/system/shutdown.target.requires/bootpart-full-abort-shutdown.service.
Removed symlink /etc/systemd/system/reboot.target.requires/bootpart-full-abort-shutdown.service.

[root@ora75-mule system]# reboot
PolicyKit daemon disconnected from the bus.
We are no longer a registered authentication agent.
Connection to 192.168.1.191 closed by remote host.
Connection to 192.168.1.191 closed.
```

When the system restarts, there is another service that will enable and start `bootpart-full-abort-shutdown.service`

Following the reboot I can see that the service is running, even though I disabled it to allow the reboot.

```text
[root@ora75-mule system]# systemctl status  bootpart-full-abort-shutdown.service
● bootpart-full-abort-shutdown.service - Cancel shutdowns and reboots when /boot has insufficient free space
   Loaded: loaded (/etc/systemd/system/bootpart-full-abort-shutdown.service; enabled; vendor preset: disabled)
   Active: active (running) since Mon 2020-04-06 19:07:52 EDT; 59s ago
 Main PID: 835 (bash)
   CGroup: /system.slice/bootpart-full-abort-shutdown.service
           ├─ 835 bash /usr/local/bin/check-boot-space.sh
           └─1797 sleep 5

Apr 06 19:07:53 ora75-mule.jks.com systemd[1]: Started Cancel shutdowns and reboots when /boot has insufficient free space.
Apr 06 19:07:53 ora75-mule.jks.com systemd[1]: Starting Cancel shutdowns and reboots when /boot has insufficient free space...

```

## Files

Create the following files, set the permissions as noted, and follow any other instructions shown.

### /usr/local/bin/check-boot-space.sh


```text
chmod 760 /usr/local/bin/check-boot-space.sh
```


### /etc/systemd/system/bootpart-full-abort-shutdown.service

```text
[Unit]
Description=Cancel shutdowns and reboots when /boot has insufficient free space
Requires=multi-user.target
Before=shutdown.target reboot.target

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/usr/local/bin/check-boot-space.sh
TimeoutStartSec=10

[Install]
RequiredBy=shutdown.target reboot.target
```

```text
chmod 664 /etc/systemd/system/bootpart-full-abort-shutdown.service
```

systemctl enable bootpart-full-abort-shutdown.servic

### /etc/systemd/system/start-bootpart-full-abort-shutdown.service

```text
[Unit]
Description=Start /boot partition full protection - cannot reboot if disk is full

[Service]
ExecStart=/bin/sh -c '/bin/systemctl enable bootpart-full-abort-shutdown; /bin/systemctl start bootpart-full-abort-shutdown'

[Install]
WantedBy=multi-user.target
```

```text
chmod 664 /etc/systemd/system/start-bootpart-full-abort-shutdown.service
```


## Enable and Start the service

```text
[root@ora75-mule ~]# systemctl status bootpart-full-abort-shutdown.service
● bootpart-full-abort-shutdown.service - Cancel shutdowns and reboots when /boot has insufficient free space
   Loaded: loaded (/etc/systemd/system/bootpart-full-abort-shutdown.service; disabled; vendor preset: disabled)
	Active: inactive (dead)

[root@ora75-mule ~]# systemctl enable bootpart-full-abort-shutdown.service
Created symlink from /etc/systemd/system/poweroff.target.wants/bootpart-full-abort-shutdown.service to /etc/systemd/system/bootpart-full-abort-shutdown.service.
Created symlink from /etc/systemd/system/halt.target.wants/bootpart-full-abort-shutdown.service to /etc/systemd/system/bootpart-full-abort-shutdown.service.

[root@ora75-mule ~]# systemctl start  bootpart-full-abort-shutdown.service

[root@ora75-mule ~]# systemctl status  bootpart-full-abort-shutdown.service
● bootpart-full-abort-shutdown.service - Cancel shutdowns and reboots when /boot has insufficient free space
   Loaded: loaded (/etc/systemd/system/bootpart-full-abort-shutdown.service; enabled; vendor preset: disabled)
   Active: active (running) since Mon 2020-04-06 20:59:58 EDT; 2s ago
 Main PID: 4194 (bash)
   CGroup: /system.slice/bootpart-full-abort-shutdown.service
           ├─4194 bash /usr/local/bin/check-boot-space.sh
           └─4195 sleep 5

Apr 06 20:59:58 ora75-mule.jks.com systemd[1]: Started Cancel shutdowns and reboots when /boot has insufficient free space.
Apr 06 20:59:58 ora75-mule.jks.com systemd[1]: Starting Cancel shutdowns and reboots when /boot has insufficient free space...

```

## Show Dependencies

These dependencies will be removed when `check-boot-space.sh` allows a reboot.

When the server restarts, the dependencies will be put back in place by the `start-bootpart-full-abort-shutdown.service` service.

```text
[root@ora75-mule ~]# systemctl list-dependencies reboot.target
reboot.target
● ├─bootpart-full-abort-shutdown.service
● ├─plymouth-reboot.service
● ├─systemd-reboot.service
● └─systemd-update-utmp-runlevel.service


[root@ora75-mule ~]# systemctl list-dependencies shutdown.target
shutdown.target
● ├─bootpart-full-abort-shutdown.service
● └─dracut-shutdown.service
```

## Test the service

With the threshold values at 15%, the `check-boot-space.sh` script that is run by the `bootpart-full-abort-shutdown.service` service will prevent the reboot.

```
[root@ora75-mule ~]# grep 'declare max' /usr/local/bin/check-boot-space.sh
declare maxAllowedPctSpaceUsed=15
declare maxAllowedPctInodesUsed=15


[root@ora75-mule ~]# shutdown -r +1 "Rebooting for Test"
Shutdown scheduled for Mon 2020-04-06 20:22:12 EDT, use 'shutdown -c' to cancel.

Broadcast message from root@ora75-mule.jks.com (Mon 2020-04-06 20:21:12 EDT):

Rebooting for Test
The system is going down for reboot at Mon 2020-04-06 20:22:12 EDT!

[root@ora75-mule ~]#
Broadcast message from root@ora75-mule.jks.com (Mon 2020-04-06 20:21:12 EDT):

The system shutdown has been cancelled at Mon 2020-04-06 20:22:12 EDT!


Broadcast message from root@ora75-mule.jks.com (Mon Apr  6 20:21:12 2020):

Space of 22% in /boot is insufficient for reboot

```

When changed back to 85, the reboot will proceed:

```text

[root@ora75-mule ~]# systemctl stop  bootpart-full-abort-shutdown.service

[root@ora75-mule ~]# systemctl disable  bootpart-full-abort-shutdown.service
Removed symlink /etc/systemd/system/shutdown.target.requires/bootpart-full-abort-shutdown.service.
Removed symlink /etc/systemd/system/reboot.target.requires/bootpart-full-abort-shutdown.service.

[root@ora75-mule ~]# systemctl daemon-reload

[root@ora75-mule ~]# systemctl start  bootpart-full-abort-shutdown.service

[root@ora75-mule ~]# grep 'declare max' /usr/local/bin/check-boot-space.sh
declare maxAllowedPctSpaceUsed=85
declare maxAllowedPctInodesUsed=85

ot@ora75-mule ~]# shutdown -r +1 "Rebooting for Test"
Shutdown scheduled for Mon 2020-04-06 20:25:43 EDT, use 'shutdown -c' to cancel.

Broadcast message from root@ora75-mule.jks.com (Mon 2020-04-06 20:24:43 EDT):

Rebooting for Test
The system is going down for reboot at Mon 2020-04-06 20:25:43 EDT!


[root@ora75-mule ~]# systemctl list-dependencies shutdown.target
shutdown.target
● └─dracut-shutdown.service


[root@ora75-mule ~]# Connection to 192.168.1.191 closed by remote host.
Connection to 192.168.1.191 closed.

```

The `systemctl list-dependencies shutdown.target` command shows that `bootpart-full-abort-shutdown.service` was removed as a dependency.

If not removed, the reboot will fail, and you will see a message like this in `/var/log/messages` :

```text
systemd: Requested transaction contains unmergeable jobs: Transaction contains conflicting jobs 'stop' and 'start' for systemd-poweroff.service. Probably contradicting requirement dependencies configured.
```

So far I have been unable to find how to resolve that error.

When I know how to resolve that error, there will be no need to disable the boot guard service. Until then however, this is how it works.

Log back on to the server and verify that the service restarted:

```text
[root@ora75-mule ~]# systemctl status  bootpart-full-abort-shutdown.service
● bootpart-full-abort-shutdown.service - Cancel shutdowns and reboots when /boot has insufficient free space
   Loaded: loaded (/etc/systemd/system/bootpart-full-abort-shutdown.service; enabled; vendor preset: disabled)
   Active: active (running) since Mon 2020-04-06 20:25:39 EDT; 3min 14s ago
 Main PID: 836 (bash)
   CGroup: /system.slice/bootpart-full-abort-shutdown.service
           ├─ 836 bash /usr/local/bin/check-boot-space.sh
           └─1966 sleep 5

Apr 06 20:25:39 ora75-mule.jks.com systemd[1]: Started Cancel shutdowns and reboots when /boot has insufficient free space.
Apr 06 20:25:39 ora75-mule.jks.com systemd[1]: Starting Cancel shutdowns and reboots when /boot has insufficient free space...


[root@ora75-mule ~]# systemctl list-dependencies shutdown.target
shutdown.target
● ├─bootpart-full-abort-shutdown.service
● └─dracut-shutdown.service
```


## References

[Managing Services with Systemd Unit Files](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/system_administrators_guide/sect-managing_services_with_systemd-unit_files)

[Managing Services with Sytemd Targets](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/system_administrators_guide/sect-Managing_Services_with_systemd-Targets)


