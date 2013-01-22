#!/bin/sh

# Part of passwordless cryptofs setup in Debian Etch.
# See: http://wejn.org/how-to-make-passwordless-cryptsetup.html
# Author: Wejn <wejn at box dot cz>
#
# Updated by Rodolfo Garcia (kix) <kix at kix dot com>
# For multiple partitions
# http://www.kix.es/
#
# Updated by TJ <linux@tjworld.net> 7 July 2008
# For use with Ubuntu Hardy, usplash, automatic detection of USB devices,
# detection and examination of *all* partitions on the device (not just partition #1),
# automatic detection of partition type, refactored, commented, debugging code.
#
# Updated by Hendrik van Antwerpen <hendrik at van-antwerpen dot net> 3 Sept 2008
# For encrypted key device support, also added stty support for not
# showing your password in console mode.
#
# Updated by Jan-Pascal van Best janpascal/at/vanbest/org 2009-12-07
# to support latest debian updates (vol_id missing, blkid used instead)
#
# Updated by Renaud Metrich renaud.metrich/at/laposte/net 2011-09-24
# to support Ubuntu 10.04 and onward.
# Explanation of the patch:
# The issue reported later against USB was due to the fact that devices in  
# /sys/block/*/device point to a relative path on Ubuntu instead of full  
# path name. The solution was to cd to that directory and issue a pwd.
# Also, I improved a bit the algorithm to speed up things, typically by  
# first checking whether the device (e.g. sdb) was a USB and removable  
# stuff, instead of doing the same test on every single partition of the  
# device (e.g. sdb1, sdb2, ...).
#
# 2012-03-29
# Updated by dgb for plymouth support in Ubuntu 10.04.3 LTS
#
# Updated 2013-01-20 by Kyle to swap USB keyfile for YubiKey Challenge Response

# define counter-intuitive shell logic values (based on /bin/true & /bin/false)
# NB. use FALSE only to *set* something to false, but don't test for
# equality, because a program might return any non-zero on error
TRUE=0
FALSE=1

# set DEBUG=$TRUE to display debug messages, DEBUG=$FALSE to be quiet
DEBUG=$TRUE

# is plymouth available? default false
PLYMOUTH=$FALSE
if [ -x /bin/plymouth ] && plymouth --ping; then
    PLYMOUTH=$TRUE
fi

# is usplash available? default false
USPLASH=$FALSE
# test for outfifo from Ubuntu Hardy cryptroot script, the second test
# alone proves not completely reliable.
if [ -p /dev/.initramfs/usplash_outfifo -a -x /sbin/usplash_write ]; then
    # use innocuous command to determine if usplash is running
    # usplash_write will return exit-code 1 if usplash isn't running
    # need to set a flag to tell usplash_write to report no usplash
    FAIL_NO_USPLASH=1
    # enable verbose messages (required to display messages if kernel boot option "quiet" is enabled
    /sbin/usplash_write "VERBOSE on"
    if [ $? -eq $TRUE ]; then
        # usplash is running
        USPLASH=$TRUE
        /sbin/usplash_write "CLEAR"
    fi
fi

# is stty available? default false
STTY=$FALSE
STTYCMD=false
# check for stty executable
if [ -x /bin/stty ]; then
    STTY=$TRUE
    STTYCMD=/bin/stty
elif [ `(busybox stty >/dev/null 2>&1; echo $?)` -eq $TRUE ]; then
    STTY=$TRUE
    STTYCMD="busybox stty"
fi

# print message to usplash or stderr
# usage: msg <command> "message" [switch]
# command: TEXT | STATUS | SUCCESS | FAILURE | CLEAR (see 'man usplash_write' for all commands)
# switch : switch used for echo to stderr (ignored for usplash)
# when using usplash the command will cause "message" to be
# printed according to the usplash <command> definition.
# using the switch -n will allow echo to write multiple messages
# to the same line
msg ()
{
    if [ $# -gt 0 ]; then
        # handle multi-line messages
        echo $2 | while read LINE; do
            if [ $PLYMOUTH -eq $TRUE ]; then
                # use plymouth
                plymouth message --text="$LINE"      
            elif [ $USPLASH -eq $TRUE ]; then
                # use usplash
                /sbin/usplash_write "$1 $LINE"      
            else
                # use stderr for all messages
                echo $3 "$2" >&2
            fi
        done
    fi
}

dbg ()
{
    if [ $DEBUG -eq $TRUE ]; then
        msg "$@"
    fi
}

# read password from console or with usplash
# usage: readpass "prompt"
readpass ()
{
    if [ $# -gt 0 ]; then
        if [ $PLYMOUTH -eq $TRUE ]; then
            PASS="$(plymouth ask-for-password --prompt "$1: ")"
        elif [ $USPLASH -eq $TRUE ]; then
            usplash_write "INPUTQUIET $1: "
            PASS="$(cat /dev/.initramfs/usplash_outfifo)"
        else
            [ $STTY -ne $TRUE ] && msg TEXT "WARNING stty not found, password will be visible"
            echo -n "$1" >&2
            $STTYCMD -echo
            read -r PASS #</dev/console >/dev/null
            [ $STTY -eq $TRUE ] && echo >&2
            $STTYCMD echo
        fi
    fi
    echo -n "$PASS"
}

dbg STATUS "Executing ykcrypto.sh ..."

# flag tracking key-file availability
OPENED=$FALSE


# If the file already exists use it.
# This is useful where an encrypted volume contains keyfile(s) for later
# volumes and is now mounted and accessible


dbg TEXT "Trying to get key..."
TRIES=3
DECRYPTED=$FALSE
while [ $TRIES -gt 0 -a $DECRYPTED -ne $TRUE ]; do
  TRIES=$(($TRIES-1))
	PASS="`readpass \"Enter YK password (or empty to skip): \"`"
	#read -s PASS
	if [ -z "$PASS" ]; then
		dbg TEXT "Device Skipped"
		break
	fi
	ykchalresp -2 "$PASS" > /etc/yk.key 2> /dev/null
	DECRYPTED=0$?

	YKKEYFILE=/etc/yk.key
	if [ -e $YKKEYFILE -a $DECRYPTED -eq $TRUE ]; then
		msg STATUS "YK Success"
		LABEL="YubiKey"
		OPENED=$TRUE
		cat $YKKEYFILE
		rm /etc/yk.key
	else
		OPENED=$FALSE
		msg STATUS "YK Fail - Try again..."
	fi
done


# clear existing usplash text and status messages
[ $USPLASH -eq $TRUE ] && msg STATUS "                               " && msg CLEAR ""

if [ $OPENED -ne $TRUE ]; then
    msg TEXT "Failed to find suitable USB key-file ..."
    readpass "Enter the LUKS password: "
else
    msg TEXT "Success loading key-file from ($LABEL)"
fi

#
[ $USPLASH -eq $TRUE ] && /sbin/usplash_write "VERBOSE default"


 
