#!/bin/bash
##############################################################################
#
# FILE NAME  : eap-install.sh
#
# DESCRIPTION: Application package installation script to be run on the HOST
#
# ----------------------------------------------------------------------------
# Copyright (C) 2009, Axis Communications AB, LUND, SWEDEN
##############################################################################

###############################################################################
help_and_exit() {
	local me
	me=${0##*/}
	echo "Use      $me to install a package on the target"
	echo
	echo "Usage:   $me <target_ip>  <username> <password> <action>"
	echo "Example: $me 192.168.0.90 username mypasswd [install|start|stop|remove]"
	echo "Example: $me 192.168.0.90 username mypasswd install"
	echo
	echo "Legacy format (user:root)"
	echo "Usage:   $me <target_ip>  <password> <action>"
	echo "Example: $me 192.168.0.90 mypasswd [install|start|stop|remove]"
	echo "Example: $me 192.168.0.90 mypasswd install"
	echo
	echo "The script remembers the target_ip and password after the first"
	echo "successful execution. After this you can simply write:"
	echo "Usage:   $me <action>"
	echo "Example: $me install"
	exit 100;
}

###############################################################################
getInput() {
	local default=$1
	read input
	if [ -z "$input" ]; then
		echo $default
		return 0
	fi

	echo $input
}

###############################################################################
# check action
do_check_action() {
	local action=$1
	case "$action" in
		install)
		;;
		start)
		;;
		stop)
		;;
		remove)
		;;
		*)
		help_and_exit
		;;
	esac
}
###############################################################################
# get syslog
do_get_syslog() {
	# Save the old var log messages, to be able to run a diff ;-)
	if [ -e .${axis_device_ip}-var_log_messages.txt ]; then
		\mv .${axis_device_ip}-var_log_messages.txt .${axis_device_ip}-var_log_messages.old 2>/dev/null || return 1
		[ -r .${axis_device_ip}-var_log_messages.old ] || \rm -rf .${axis_device_ip}-var_log_messages.old || return 1
	fi
	$CURL --anyauth -s -S -u $user:$password "http://${axis_device_ip}/axis-cgi/systemlog.cgi" >.${axis_device_ip}-var_log_messages.txt 2>&1
	curlres=$?
	if [ $curlres -eq 7 ] ; then
		echo "!!!!! Wait for target to restart !!!!!!"
		\rm -rf .${axis_device_ip}-var_log_messages.txt
		\touch .${axis_device_ip}-var_log_messages.txt || return 1
	fi
}

###############################################################################
# check_error_msg
do_check_error_msg() {
	local urldevtools="URL=/devtools.shtml."
	local grepped

	do_get_syslog || {
		echo "Info: Could not get syslog: No detailed info available"
		return 1
	}
	# The good case: Install and restart. Handle it first
	\grep "package_uploaded=yes" /tmp/.curlmsg$$ >/dev/null
	if [ $? -eq 0 ]; then
		\grep "Restarting the system, please be patient" .${axis_device_ip}-var_log_messages.txt >/dev/null
		if [ $? -eq 0 ]; then
			echo "System is restarting, please be patient"
		fi
		return 0
	fi
	# Check for squid errors
	\egrep -i "squid" .${axis_device_ip}-var_log_messages.txt >/dev/null
	if [ $? -eq 0 ]; then
		echo "=========== log from $axis_device_ip follows, read carefully =================="
		\tail .${axis_device_ip}-var_log_messages.txt
		echo "------------end of log, thanks for reading ---------------"
	elif [ -s .${axis_device_ip}-var_log_messages.old ] && [ -s .${axis_device_ip}-var_log_messages.txt ]; then
		# Compare the old /var/log/messages with the new one
		# Sometimes ( last CRITICAL message repeated 2 times) there is no diff
		# In this case, show the tail
		\cmp -s .${axis_device_ip}-var_log_messages.old .${axis_device_ip}-var_log_messages.txt
		# If there is a diff, show it
		if [ $? -ne 0 ]; then
			echo "------ diff of .${axis_device_ip}-var_log_messages.txt from ${axis_device_ip} follows -----"
			\diff .${axis_device_ip}-var_log_messages.old .${axis_device_ip}-var_log_messages.txt | \egrep "^>" | \sed -e 's/^> //'
			echo "------------end of syslog, thanks for reading ---------------"
		else
			echo "=========== log from ${axis_device_ip} follows, read carefully =================="
			\tail .${axis_device_ip}-var_log_messages.txt
			echo "------------end of log, thanks for reading ---------------"
		fi
	elif [ -s .${axis_device_ip}-var_log_messages.txt ]; then
		echo "=========== syslog from ${axis_device_ip} follows, read carefully =================="
		\tail .${axis_device_ip}-var_log_messages.txt
		echo "------------end of syslog, thanks for reading ---------------"
	fi

	grepped=$(\grep "${urldevtools}error=" /tmp/.curlmsg$$ | \sed -re 's/.*(error=[[:alnum:]]+).*/\1/' &2>/dev/null)
	if [ $? -eq 0 ]; then
		case "$grepped" in
			error=1)
				echo "Could not upload package file, the file is not a valid package"; return 1
				;;
			error=2)
				echo "For more info, see the syslog above"; return 2
				;;
			error=3)
				echo "Could not upload package file, the file is too large or disk full"; return 3
				;;
			error=4)
				echo "Package could not be found"; return 4
				;;
			error=5)
				echo "This application package is not compatible with this product, see syslog above"; return 5
			;;
			error=6)
				echo "This application is already running"; return 6
				;;
			error=7)
				echo "This application is not running"; return 7
				;;
			error=8)
				echo "Could not start application, file verification failed"; return 8
				;;
			error=9)
				echo "Another application is already running"; return 9
				;;
			error=10)
				echo "Error. Check logs for more information."; return 10
				;;
			*)
			;;
		esac
	fi
	if [ -s /tmp/.curlmsg$$ ]; then
		echo "=========== log from $CURL follows, read carefully =================="
		cat /tmp/.curlmsg$$
		echo "------------end of $CURL log, thanks for reading --------------------"
	fi

	echo $errmsg
	echo "--------------------------------------------------------------"
	echo "It looks as if something went wrong"
	echo "Please read carefully the messages above"
	if [ $pingres -ne 0 ]; then
		if [ $http_proxy ]; then
			echo "  Please check your hostname"
		else
			echo "  Please check your hostname, and check if you need to set http_proxy"
			echo "  e.g. export http_proxy=httpproxy.mycompany.com:8080"
		fi
	fi
	return 1
}

###############################################################################
# cleanup
do_cleanup() {
	\rm -rf /tmp/.curlmsg$$ >/dev/null || :
}


###############################################################################
# The script starts here:

CURL=$(which curl)
if [ $? -ne 0 ]; then
	echo "Error: curl not found."
	echo "please install the curl package"
	exit 100
fi

# source ./.eap-install.cfg, if it exist
if [ -r ./.eap-install.cfg ]; then
	. ./.eap-install.cfg
fi

# Check the command line parameters
if [ -z "$1" ]; then
	# Script called without arguments ask the user
	echo axis_device_ip=$axis_device_ip
	echo -n "Target IP address [$axis_device_ip]: "
	axis_device_ip=$(getInput $axis_device_ip)
	echo -n "Target user name [$user]: "
	user=$(getInput $user)
	echo -n "Target user password [$password]: "
	password=$(getInput $password)
	echo -n "Action [install],start,stop,remove: "
	# default action is install
	action=$(getInput "install")
elif [ "$1" ] && [ "$2" ] && [ "$3" ] && [ "$4" ]; then
	# Script called with 4 arguments, take them
	axis_device_ip=$1
	user=$2
	password=$3
	action=$4
elif [ "$1" ] && [ "$2" ] && [ "$3" ]; then
	# Script called with 3 arguments, take them
	echo "Legacy format (user:root)"
	user=root
	axis_device_ip=$1
	password=$2
	action=$3
	# and save them
elif [ "$1" ] && [ -z "$2" ]; then
	# 1 parameter, both axis_device_ip and password retrieved from config file
	action=$1
	do_check_action $action
	# if we come here, action is OK, ask for the rest
	if [ -z "$axis_device_ip" ] || [ -z "$user" ] || [ -z "$password" ] ; then
		echo -n "Target IP address [$axis_device_ip]: "
		axis_device_ip=$(getInput $axis_device_ip)
		echo -n "Target user name [$user]: "
		user=$(getInput $user)
		echo -n "Target user password [$password]: "
		password=$(getInput $password)
	fi
else
	help_and_exit
fi


###############################################################################
export old_http_proxy=

# ping target
\ping -q -c 1 $axis_device_ip >/dev/null 2>/dev/null
pingres=$?
if [ $pingres -ne 0 ]; then
	\ping6 -q -c 1 -$axis_device_ip >/dev/null 2>/dev/null
	pingres=$?
fi

if [ $pingres -eq 0 ]; then
	# target is reachable via ping, reset proxy
	export old_http_proxy=$http_proxy
	export http_proxy=
else
	if [ $http_proxy ]; then
		echo "Can not ping $axis_device_ip"
		echo "I will try to use the proxy $http_proxy"
	else
		echo "(If you can't ping the target, check if you need to set http_proxy"
		echo " e.g. export http_proxy=httpproxy.mycompany.com:8080)"
		echo "-----------------------------------------------------------------"
		echo "Error: Could not ping target with IP address: $axis_device_ip"
		echo "Please check that the target is up and running at this IP address"
		echo "-----------------------------------------------------------------"
		exit 100
	fi
fi

# Source package.conf particularly to retrieve $APPTYPE
[ ! -r ./package.conf ] || . ./package.conf

# If more than one packages are present we must know what the user
# has in mind as destination product.
# Only necessary for platform dependent apps (not lua apps).
if [ "$action" = install ]; then
	packages=0
	for myeap in *.eap ; do
		case $myeap in
		    *ARTPEC-3*)
			packages=$(($packages+1))
			;;
		    *ARTPEC-4*)
			packages=$(($packages+1))
			;;
		    *AMBARELLA-A5S*)
			packages=$(($packages+1))
			;;
		esac
	done
	if [ $packages -gt 1 ]; then
		# Find default choice from package.conf
		case $APPTYPE in
		    *ARTPEC-3*)
			default_choice="artpec-3"
			;;
		    *ARTPEC-4*)
			default_choice="artpec-4"
			;;
		    *AMBARELLA-A5S*)
			default_choice="ambarella-a5s"
			;;
		esac
		# Ask user, proposing the default choice
		echo "More than one package detected."
		echo -n "Target device [$default_choice]: "
		read device_type
		[ -n "$device_type" ] || device_type=$default_choice
	fi
fi

# Verify user input concerning device type and update APPTYPE
if [ -n "$device_type" ]; then
	if [ "$device_type" = artpec-3 ]; then
		# Good. Overwrite $APPTYPE from package.conf to be sure.
		APPTYPE="ARTPEC-3"
	elif [ "$device_type" = artpec-4 ]; then
		# Good. Overwrite $APPTYPE from package.conf to be sure.
		APPTYPE="ARTPEC-4"
	elif [ "$device_type" = "ambarella-a5s" ]; then
		# Good. Overwrite $APPTYPE from package.conf to be sure.
		APPTYPE="AMBARELLA-A5S"
	else
		echo "Device type not regocnized."
		echo
		exit 0
	fi
fi

# Loop over all eap files
for myeap in *.eap ; do
	if [ "$myeap" =  "*.eap" ]; then
		echo "Can not find any eap files in $PWD"
		echo "Please use create-package.sh"
		exit 101
	fi

	if [ "$APPTYPE" = lua ]; then
		mydir=${APPNAME%.*}
	else
		mydir=$APPNAME
	fi
	[ "$mydir" ] || mydir=${myeap%_[0-9]*_[0-9]*_*}
	if [ "$APPMAJORVERSION" -a "$APPMINORVERSION" ]; then
		if [ "$APPMICROVERSION" ]; then
			end="_${APPMICROVERSION}_$APPTYPE.eap"
		else
			end="_$APPTYPE.eap"
		fi
		name=${myeap%_[0-9]*_[0-9]*$end}
		version=$myeap
		version=${version#$name}
		version=${version#_}
		version=${version%$end}

		if [ "$version" != "${APPMAJORVERSION}_$APPMINORVERSION" ] && [ "$action" = install ]; then
			# Typically happens when the version is changed
			# and the eap file of the old version still is in
			# the directory.
			echo "$myeap doesn't match information in package.conf, skipping"
			continue
		fi
	fi
	do_get_syslog || :
	case "$action" in
		install)
			echo "${action}ing $myeap"
			$CURL --anyauth -s -S -F packfil=@${myeap} -u ${user}:${password} "http://${axis_device_ip}/axis-cgi/admin/applications/upload.cgi?reload_page=yes" 2>&1 >/tmp/.curlmsg$$
			\grep -q "package_uploaded=yes" /tmp/.curlmsg$$
			grepokmsg=$?
			if [ $grepokmsg -eq 0 ]; then
				echo "Installation succeded"
				echo "to start your application type"
				echo "  eap-install.sh start"

				# If possible, save IP adress for later use
				echo "axis_device_ip=$axis_device_ip" 2>/dev/null > ./.eap-install.cfg || :
				echo "user=$user" 2>/dev/null >> ./.eap-install.cfg || :
				echo "password=$password" 2>/dev/null >> ./.eap-install.cfg || :
				# In case of install: get the syslog, the target might want to restart
				do_get_syslog
				do_cleanup
				exit 0
			else
				do_check_error_msg || echo "Failed ${action}ing $myeap."
			fi
			;;
		start)
			echo "${action}ing $mydir"
			$CURL --anyauth -s -S -u ${user}:${password} "http://${axis_device_ip}/axis-cgi/applications/control.cgi?action=start&package=${mydir}&reload_page=yes" 2>&1 >/tmp/.curlmsg$$
			\grep -q "package_started=yes" /tmp/.curlmsg$$
			grepokmsg=$?
			if [ $grepokmsg -eq 0 ]; then
				echo "Package started"
				echo "to stop your application type"
				echo "  eap-install.sh stop"
				do_cleanup
				exit 0
			else
				do_check_error_msg
				startres=$?
				if [ $startres -ne 0 ]; then
					echo "Failed ${action}ing $mydir startres=$startres"
					exit $startres
				fi
			fi
			;;
		stop)
			echo "${action}ping $mydir"
			$CURL --anyauth -s -S -u ${user}:${password} "http://${axis_device_ip}/axis-cgi/applications/control.cgi?action=stop&package=${mydir}&reload_page=yes" 2>&1 >/tmp/.curlmsg$$
			\grep -q "package_stopped=yes" /tmp/.curlmsg$$
			grepokmsg=$?
			if [ $grepokmsg -eq 0 ]; then
				echo "Package stopped"
				do_cleanup
				exit 0
			else
				do_check_error_msg
				stopres=$?
				if [ $stopres -ne 0 ]; then
					echo "Failed ${action}ping $mydir stopres=$stopres"
					exit $stopres
				fi
			fi
			;;
		remove)
			echo "removing $mydir"
			$CURL --anyauth -s -S -u ${user}:${password} "http://${axis_device_ip}/axis-cgi/applications/control.cgi?action=remove&package=${mydir}&reload_page=yes" 2>&1 >/tmp/.curlmsg$$
			\grep -q "package_removed=yes" /tmp/.curlmsg$$
			grepokmsg=$?
			if [ $grepokmsg -eq 0 ]; then
				echo "Package stopped and removed"
				do_cleanup
				exit 0
			else
				do_check_error_msg || echo "Failed ${action}ing $mydir"
			fi
			;;
		*)
			help_and_exit
			;;
	esac
	do_cleanup
	exit 100
done


###############################################################################

