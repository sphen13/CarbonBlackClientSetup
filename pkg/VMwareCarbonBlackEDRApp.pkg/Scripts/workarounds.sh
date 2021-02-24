#!/bin/bash

source constants.sh

{
    echo "STARTING SENSOR WORKAROUNDS SCRIPT"
    date
    echo "OS Version: $(/usr/bin/sw_vers -productVersion) ($(/usr/bin/sw_vers -buildVersion))"
    echo ""
} >> $LOG

source common.sh

# helper function to ensure we always log our exit line
function exit {
    echo "EXITING SENSOR WORKAROUNDS SCRIPT" >> $LOG 2>&1
    command exit "$1"
}

if [[ "$restartRequired" == true ]]; then
    {
        echo "Previous installation encountered issues and is awaiting a reboot"
        echo ""
    } >> $LOG 2>&1
fi

# make sure we have anything to do
loadedProcmon=$(getLoadedKextVersion "$PROCMON_BUNDLE")
if [[ ! $loadedProcmon ]]; then
    echo "Kext $PROCMON_BUNDLE is not loaded, no workarounds necessary." >> $LOG
    exit 0
fi

declare -a badKextVersions=(
    "1610.03.52"  # 5.2p4
    "1610.05.60"
)

for badKext in "${badKextVersions[@]}"; do
    if [[ "$badKext" == "$loadedProcmon" ]]; then
        {
            echo "Version $badKext of $PROCMON_BUNDLE loaded, installation will require a reboot."
            requireRestart
            exit 1
        } >> $LOG 2>&1
    fi
done

echo "Version $loadedProcmon of $PROCMON_BUNDLE does not require any special workarounds, installation will proceed normally." >> $LOG

exit 0