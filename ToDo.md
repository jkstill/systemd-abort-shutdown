
ToDo for reboot abort
======================

This script can be extended, or perhaps another script created, to better perform this task

These files can be used to control whether a reboot is allowed or not:


```text
[root@ora75-mule build]# ls -1 /run/systemd/system/*/bootg*

/run/systemd/system/halt.target.d/reboot-abort.conf
/run/systemd/system/poweroff.target.d/reboot-abort.conf
/run/systemd/system/reboot.target.d/reboot-abort.conf
```

All the files are the same:

## /run/systemd/system/reboot.target.d/reboot-abort.conf

```text
[Unit]
RefuseManualStart=yes
```

Change the contents to `RefuseManualStart=no`, and a reboot will be allowed.

By doing this, the check-boot-space.sh script would not need `RequiredBy=shutdown.target reboot.target`

The `bootpart-full-abort-shutdown.service` file would then be like this:

```text
[Unit]
Description=Cancel shutdowns and reboots when /boot has insufficient free space

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/usr/local/bin/check-boot-space.sh
TimeoutStartSec=10
# prevent the service from being killed by systemd
#SendSIGKILL=no

[Install]
WantedBy=multi-user.target
```

The `reboot`,`shutdown now` and `halt` commands simply will not work.

When a command of the form `shutdown -r +1 'Reboot for Patching'` is run, the `check-boot-space.sh` script will change `RefuseManualStart=yes` to `RefuseManualStart=no` in the reboot-abort.conf files.

The script will reset those values when the system starts.


## References

[Systemd Directives](https://www.freedesktop.org/software/systemd/man/systemd.directives.html)

[Systemd Units](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)

[Systemd Unit(5)](http://man7.org/linux/man-pages/man5/systemd.unit.5.html)

[Systemd Service(5)](http://man7.org/linux/man-pages/man5/systemd.service.5.html)





