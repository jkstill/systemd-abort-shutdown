#!/usr/bin/env bash


: << 'SHUTDOWN-STATUS'

As an alternative to checking for shutdown status file, look at 'Status' in systemd-shutdownd.service

Shutting Down:

   [root@ora75-mule ~]# shutdown -r +5
   Shutdown scheduled for Mon 2020-04-06 15:21:33 EDT, use 'shutdown -c' to cancel.
   [root@ora75-mule ~]#
   Broadcast message from root@ora75-mule.jks.com (Mon 2020-04-06 15:16:33 EDT):
   
   The system is going down for reboot at Mon 2020-04-06 15:21:33 EDT!
   
   [root@ora75-mule ~]# systemctl status systemd-shutdownd.service
    systemd-shutdownd.service - Delayed Shutdown Service
      Loaded: loaded (/usr/lib/systemd/system/systemd-shutdownd.service; static; vendor preset: disabled)
      Active: active (running) since Mon 2020-04-06 15:16:33 EDT; 3s ago
        Docs: man:systemd-shutdownd.service(8)
    Main PID: 13712 (systemd-shutdow)
      Status: "Shutting down at Mon 2020-04-06 15:21:33 EDT (reboot)..."
      CGroup: /system.slice/systemd-shutdownd.service
              └─13712 /usr/lib/systemd/systemd-shutdownd
   
   Apr 06 15:16:33 ora75-mule.jks.com systemd[1]: Started Delayed Shutdown Service.
   Apr 06 15:16:33 ora75-mule.jks.com systemd[1]: Starting Delayed Shutdown Service...
   Apr 06 15:16:33 ora75-mule.jks.com systemd-shutdownd[13712]: Shutting down at Mon 2020-04-06 15:21:33 EDT (reboot)...
   Apr 06 15:16:33 ora75-mule.jks.com systemd-shutdownd[13712]: Creating /run/nologin, blocking further logins...
   
When not shutting down

   [root@ora75-mule ~]# systemctl status systemd-shutdownd.service
    systemd-shutdownd.service - Delayed Shutdown Service
      Loaded: loaded (/usr/lib/systemd/system/systemd-shutdownd.service; static; vendor preset: disabled)
      Active: inactive (dead) since Mon 2020-04-06 15:16:46 EDT; 1min 18s ago
        Docs: man:systemd-shutdownd.service(8)
     Process: 13712 ExecStart=/usr/lib/systemd/systemd-shutdownd (code=exited, status=0/SUCCESS)
    Main PID: 13712 (code=exited, status=0/SUCCESS)
      Status: "Exiting..."
   
   Apr 06 15:16:33 ora75-mule.jks.com systemd[1]: Started Delayed Shutdown Service.
   Apr 06 15:16:33 ora75-mule.jks.com systemd[1]: Starting Delayed Shutdown Service...
   Apr 06 15:16:33 ora75-mule.jks.com systemd-shutdownd[13712]: Shutting down at Mon 2020-04-06 15:21:33 EDT (reboot)...
   Apr 06 15:16:33 ora75-mule.jks.com systemd-shutdownd[13712]: Creating /run/nologin, blocking further logins...


SHUTDOWN-STATUS

declare shutdownSchedulerFile=/run/systemd/shutdown/scheduled

declare shutdownCmd=/usr/sbin/shutdown
declare abortShutdownCmd="$shutdownCmd -c"

declare systemctlCmd=/bin/systemctl
declare serviceDisableCmd="$systemctlCmd disable "
declare serviceStopCmd="$systemctlCmd stop "
declare bootGuardService=bootpart-full-abort-shutdown.service

declare fsName='/boot'

declare maxAllowedPctSpaceUsed=85
declare maxAllowedPctInodesUsed=85

declare pctSpaceUsed
declare pctInodesUsed

declare logfile=/tmp/bootguard.log

while :
do

	if [[ -e $shutdownSchedulerFile ]]; then

		pctSpaceUsed=$(df --output=pcent $fsName| tail -n -1 | sed -r -e 's/[ %]//g')
		pctInodesUsed=$(df --output=ipcent $fsName| tail -n -1 | sed -r -e 's/[ %]//g')

		declare stopTheService='no'

		if [[ $pctSpaceUsed -gt $maxAllowedPctSpaceUsed ]]; then
			eval $abortShutdownCmd
			wall "Space of ${pctSpaceUsed}% in $fsName is insufficient for reboot"
			logger "Space of ${pctSpaceUsed}% in $fsName is insufficient for reboot"
		else
			declare stopTheService='yes'
		fi

		if [[ $pctInodesUsed -gt $maxAllowedPctInodesUsed ]]; then
			eval $abortShutdownCmd
			wall "Inodes of ${pctInodesUsed}% in $fsName is insufficient for reboot"
			logger "Inodes of ${pctInodesUsed}% in $fsName is insufficient for reboot"
		else
			declare stopTheService='yes'
		fi

		if [[ $stopTheService == 'yes' ]]; then
			# disable the boot guard so that reboot will succeeed
			eval $serviceStopCmd $bootGuardService
			# for some reason a slight pause is needed here when running as a service
			sleep 2
			eval $serviceDisableCmd $bootGuardService
			exit
		fi

	fi

	sleep 5

done


