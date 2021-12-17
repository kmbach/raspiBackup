#!/bin/bash

# Just some code to get familiar with remote ssh command execution and rsync daemon

source ../../raspiBackup.sh --include

### Command execution
#
# See https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables how to capture stdout and stderr and rc into different variables
#
## - local command execution -
# 1) Test local result (stdout and stderr) returned correctly
# 2) Test local RCs are returned correctly
#
## - remote command execution via ssh -
# 1) Test remote result (stdout and stderr) received correctly locally
# 2) Test remote execution RCs are returned correctly

source ~/.ssh/rsyncServer.creds
#will define
#SSH_HOST=
#SSH_USER= # pi
#SSH_KEY_FILE= # public key of user

#DAEMON_HOST=
#DAEMON_MODULE="Rsync-Test" # uses DAEMON_MODULE_DIR
#DAEMON_MODULE_DIR="/srv/rsync"
#DAEMON_USER=
#DAEMON_PASSWORD=

TEST_DIR="Test-Backup"

declare -A localTarget
localTarget[$TARGET_TYPE]="$TARGET_TYPE_LOCAL"
localTarget[$TARGET_BASE]="."
localTarget[$TARGET_DIR]="./${TEST_DIR}_tgt"

declare -A sshTarget
sshTarget[$TARGET_TYPE]="$TARGET_TYPE_SSH"
sshTarget[$TARGET_HOST]="$SSH_HOST"
sshTarget[$TARGET_USER]="$SSH_USER"
sshTarget[$TARGET_KEY_FILE]="$SSH_KEY_FILE"
sshTarget[$TARGET_DIR]="$DAEMON_MODULE_DIR/$TEST_DIR"
sshTarget[$TARGET_BASE]="$DAEMON_MODULE_DIR"

declare -A rsyncTarget
rsyncTarget[$TARGET_TYPE]="$TARGET_TYPE_DAEMON"
rsyncTarget[$TARGET_HOST]="$SSH_HOST"
rsyncTarget[$TARGET_USER]="$SSH_USER"
rsyncTarget[$TARGET_KEY_FILE]="$SSH_KEY_FILE"
rsyncTarget[$TARGET_DAEMON_USER]="$DAEMON_USER"
rsyncTarget[$TARGET_DAEMON_PASSWORD]="$DAEMON_PASSWORD"
rsyncTarget[$TARGET_DIR]="$DAEMON_MODULE_DIR/$TEST_DIR"
rsyncTarget[$TARGET_BASE]="$DAEMON_MODULE"

RSYNC_OPTIONS="-aArv"

ECHO_REPLIES=0

if (( $UID != 0 )); then
	echo "Call me as root"
	exit -1
fi

function checkrc() {
	logEntry "$1"
	local rc="$1"
	if (( $rc != 0 )); then
		echo "Error $rc"
		echo $stderr
	else
		: echo "OK: $rc"
	fi

	logExit $rc
}

function createTestData() { # directory

	echo "@@@ Creating local test data in $1"

	if [[ ! -d $1 ]]; then
		mkdir $1
	fi

	rm -f $1/acl.txt
	rm -f $1/noacl.txt

	touch $1/acl.txt
	setfacl -m u:$USER:rwx $1/acl.txt

	touch $1/noacl.txt

	verifyTestData "$1"
}

function verifyTestData() { # directory

	./testRemote.sh "$1"

}

function getRemoteDirectory() { # target directory

	local -n target=$1

	case ${target[$TARGET_TYPE]} in

		$TARGET_TYPE_SSH | $TARGET_TYPE_DAEMON)
			echo "${target[$TARGET_DIR]}"
			;;

		*) echo "Unknown target ${target[$TARGET_TYPE]}"
			exit -1
			;;
	esac
}

function testRsync() {

	local reply

	declare t=(sshTarget rsyncTarget)
	#declare t=(sshTarget)
	#declare t=(rsyncTarget)

	for (( target=0; target<${#t[@]}; target++ )); do

		tt="${t[$target]}"
		local -n tgt=$tt

		echo
		echo "@@@ ---> Target: $tt TargetDir: ${tgt[$TARGET_DIR]}"

		echo "@@@ Creating test data in local dir"
		targetDir="$(getRemoteDirectory "${t[$target]}" $TARGET_DIR)"
		createTestData $TEST_DIR

		echo "@@@ Copy local data to remote"
		invokeRsync ${t[$target]} stdout stderr "$RSYNC_OPTIONS" $TARGET_DIRECTION_TO "$TEST_DIR/" "$TEST_DIR/"
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		echo "@@@ Verify remote data in ${tgt[$TARGET_DIR]}"
#		See https://unix.stackexchange.com/questions/87405/how-can-i-execute-local-script-on-remote-machine-and-include-arguments
		printf -v args '%q ' "${tgt[$TARGET_DIR]}"
		invokeCommand ${t[$target]} stdout stderr "bash -s -- $args"  < ./testRemote.sh
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		# cleanup local dir
		echo "@@@ Clear local data $TEST_DIR"
		rm ./$TEST_DIR/*

		echo "@@@ Copy remote data to local"
		invokeRsync ${t[$target]} stdout stderr "$RSYNC_OPTIONS" $TARGET_DIRECTION_FROM "$TEST_DIR/" "$TEST_DIR/"
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		echo "@@@ Verify local data in $TEST_DIR"
		verifyTestData "$TEST_DIR"

		# cleanup local dir
		echo "@@@ Clear local data $TEST_DIR"
		rm ./$TEST_DIR/*

		echo "@@@ List remote data"
		invokeCommand ${t[$target]} stdout stderr "ls -la "${tgt[$TARGET_DIR]}/*""
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		echo "@@@ Clear remote data"
		invokeCommand ${t[$target]} stdout stderr "rm "${tgt[$TARGET_DIR]}/*""
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

		echo "@@@ List cleared remote data"
		invokeCommand ${t[$target]} stdout stderr "ls -la "${tgt[$TARGET_DIR]}""
		checkrc $?
		(( ECHO_REPLIES )) && echo "$stdout"

	done

}

# test whether ssh configuration is OK and all required commands can be executed via ssh

function verifyRemoteSSHAccessOK() {
	logEntry

	local reply rc

	declare t=sshTarget

	# test remote access
	cmd="pwd"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "pwd"
	rc=$?
	checkrc $rc

	cmd="mkdir -p /root/raspiBackup/dummy"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

	cmd="rmdir /root/raspiBackup/dummy"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

}

# test whether daemon configuration is OK and all required commands can be executed via ssh

function verifyRemoteDaemonAccessOK() {
	logEntry

	local reply rc

	declare t=rsyncTarget

	# test remote access
	cmd="pwd"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "pwd"
	rc=$?
	checkrc $rc

	local moduleDir=${rsyncTarget[$TARGET_DIR]}
	cmd="mkdir -p $moduleDir/dummy"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

	cmd="touch $moduleDir/dummy/dummy.txt"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

	cmd="rm $moduleDir/dummy/dummy.txt"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

	cmd="rmdir $moduleDir/dummy"
	echo "Testing $cmd"
	invokeCommand ${t[$target]} stdout stderr "$cmd"
	rc=$?
	checkrc $rc

}

function testCommand() {

	logEntry

	local reply rc

	declare t=(localTarget sshTarget rsyncTarget)

	cmds=("ls -b" "ls -la /" "mkdir /dummy" "ls -la /dummy" "rmdir /dummy" "ls -la /forceError" "lsblk")

	for (( target=0; target<${#t[@]}; target++ )); do
		tt="${t[$target]}"
		echo "@@@ ---> Target: $tt"
		for cmd in "${cmds[@]}"; do
			echo "Command: $cmd "
			invokeCommand ${t[$target]} stdout stderr "$cmd"
			rc=$?
			checkrc $rc
			(( ECHO_REPLIES )) && echo "stdout: $stdout"
			(( ECHO_REPLIES )) && echo "stderr: $stderr"
		done
		echo
	done

	logExit $rc
}

reset
echo "##################### daemon access ok ##################"
verifyRemoteDaemonAccessOK
echo "##################### ssh access ok ##################"
verifyRemoteSSHAccessOK
echo "##################### rsync ##################"
testRsync
echo "##################### command ##################"
testCommand
