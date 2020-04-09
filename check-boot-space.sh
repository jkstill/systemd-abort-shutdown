#!/usr/bin/env bash

declare fsName='/boot'

declare maxAllowedPctSpaceUsed=85
declare maxAllowedPctInodesUsed=85

declare pctSpaceUsed
declare pctInodesUsed


pctSpaceUsed=$(df --output=pcent $fsName| tail -n -1 | sed -r -e 's/[ %]//g')
pctInodesUsed=$(df --output=ipcent $fsName| tail -n -1 | sed -r -e 's/[ %]//g')

declare retval=1;

if [[ $pctSpaceUsed -gt $maxAllowedPctSpaceUsed ]]; then
	retval=1
else
	retval=0
fi

if [[ $pctInodesUsed -gt $maxAllowedPctInodesUsed ]]; then
	retval=1
fi

exit $retval




