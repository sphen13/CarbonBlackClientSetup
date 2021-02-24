#!/bin/bash

# This script is intended to be sourced to provide common functions
# for use by installer scripts

source constants.sh

if [ -z "${restartRequired+x}" ]; then
    if [[ -f "$RESTART_SENTINEL_FILE" ]]; then
        restartRequired=true
    else
        restartRequired=false
    fi
fi

function requireRestart {
    if [[ "${restartRequired:-x}" == true ]]; then
        return
    fi

    if ! touch $RESTART_SENTINEL_FILE; then
        echo "Failed to touch $RESTART_SENTINEL_FILE" >> $LOG 2>&1
    else
        echo "A restart will be required to fully complete installation." >> $LOG 2>&1
    fi

    restartRequired=true
}

function getMachoVersion {
    xcode-select -p >> /dev/null
    if [[ $? -eq 0 ]]; then
        GETVERSTOOL="otool -P"
    elif [[ -e "/Applications/"$APP_NAME".app/Contents/Resources/cbgetversion" ]]; then
        GETVERSTOOL="/Applications/"$APP_NAME".app/Contents/Resources/cbgetversion"
    else
        return 1
    fi

    if [[ -f $1 ]]; then
        VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /dev/stdin 2>/dev/null <<< "$($GETVERSTOOL "$1" | tail -n +3)")
        if [[ -z $? ]]; then
            return $?
        fi

        echo "$VERSION"
        return 0
    fi

    return 1
}

function doKextstat
{
    kextstat -l -b "$1" > /tmp/kextstat-out.txt &
    ks_pid=$!

    countdown=30

    while kill -0 $ks_pid &> /dev/null; do
        sleep 1
        let countdown-=1
        if [ $countdown -eq 0 ]; then
            kill -9 $ks_pid &> /dev/null
            requireRestart
            echo "kextstat failed to exit within 30 seconds." >> $LOG 2>&1
            echo ""
        fi
    done

    cat /tmp/kextstat-out.txt
    rm -f /tmp/kextstat-out.txt
}

function getLoadedKextVersion {
    doKextstat "$1" | tr -s ' ' | cut -d' ' -f8 | sed 's/[()]//g'
}

function isKextLoaded {
    # kextstat returns a 0 exit code even if the kext isn't loaded, so we have to just grep its output
    doKextstat "$1" | grep -q "$1"
    return $?
}

# A function that waits for a kext to unload. If the kext is not loaded,
# this function will return succesfully immediately.  If the kext does not
# unload in 5 minutes, the script will exit with an error status.
function waitForKext {
    startTime=$(date +%s)
    elapsed=0

    echo "Waiting for $1 to stop..."  >> $LOG 2>&1
    while isKextLoaded "$1"; do
        sleep 1
        elapsed=$(($(date +%s)-startTime))

        ## give up after 5 minutes
        if (test $elapsed -gt 300) ; then
            echo "Kext $1 still loaded after 5 minutes" >> $LOG 2>&1
            requireRestart
            return 1
        fi
    done;

    echo "Unloaded $1 kext after $elapsed secs" >> $LOG 2>&1
}

function unloadKext {
    if ! isKextLoaded "$1"; then
        echo "Kext $1 is not loaded"
        return 0
    fi

    # run kextunload in background in case it blocks forever, we'll
    # asynchronously poll to find out if/when it's finished
    kextunload -q -b "$1" &
    sleep 2s

    if ! isKextLoaded "$1"; then
        echo "Unloaded $1 kext" >> $LOG
    else
        waitForKext "$1"
    fi
}

function useSystemExtension {
    majorVer=$(uname -r | awk '{split($0,a,"."); print a[1]}')
    if [ "$majorVer" -ge "20" ]; then
        # true
        return 0
    fi
    
    # false
    return 1
}

