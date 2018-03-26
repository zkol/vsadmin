#!/bin/sh
# /etc/init.d/vintagestory.sh
# version 1.5.1.4 2018-03-26 (YYYY-MM-DD)
#
### BEGIN INIT INFO
# Provides:   vintagestory
# Required-Start: $local_fs $remote_fs screen-cleanup
# Required-Stop:  $local_fs $remote_fs
# Should-Start:   $network
# Should-Stop:    $network
# Default-Start:  2 3 4 5
# Default-Stop:   0 1 6
# Short-Description:    vintagestory server
# Description:    Starts the vintagestory server
### END INIT INFO

# Initially inspired by http://minecraft.gamepedia.com/Tutorials/Server_startup_script
#
# Changelog:
# 2018-01-04 Download path of tar.gz changed
#            Status command checks for 2 processes with service signature (screen and mono)
#            Server stop command tries to quit screen as last option
#            Check for mono-xmltool and compiler version > 4.2
#            Can be run as user of group vintagestory (not only by vintagestory owner)
#            Can be run as vintagestory owner by SU even when the default shell permits a login
# 2018-01-05 Environment-Variable "NO_SUPPORT_MODE" to possibly ignore the version check
#			 Fixed update to consider versions as documented (shall not downgrade newer unstable versions)
#            Adjusted some operators & co for better script portability and better fault tolerance  (removing deprecated notation)
#			 Mixed coding practises slightly harmonized for better maintainability (less style mixing)
#            Check if downloaded archive is not HTML file (e.g. 404 page)
#            Check if downloaded archive is really a gzip file
#			 Switched download to HTTPS
#			 Fixed ownership of reinstalled/updated/archived files
#            Optional version parameter for reinstall in order to allow a downgrade
#            Adjusted install function truncating version number from 5 chars to 7 chars
#            Adjusted command handling (accessing the logged result)
# 2018-01-06 Using -v instead of monodis (eliminates one dependency and its check)
#            Adding command probe to the status check (as function vs_status)
#            Adding proper return values and error messages to the functions
#            Fixed command output
#            Adding a general installation check
#            Adding basic server environment setup
# 2018-01-13 Workaround to recognize running server process by user of group vintagestory (and vice versa)
#            Improved installation approach (create new folder) that should work even with major updates
#            Install new version in parallel to running server and switch/restart afterwards
#            Fix backup during install to archive the OLD version (and not the NEW version)
#            Support of changed data path in VintagestoryServer 1.4.9.2 
#            Improve backup to support a seperate data backup (on a different path)
#            Improved install to define and pass the data path parameter to VintagestoryServer 1.4.9.2
#            Define standard data path for server installation as /var/vintagestory/data
#            Function vs_version to work around implicit datapath creation silently done by VintagestoryServer -v 
#            Improved return value handling for independent processing steps
#            Use NO_SUPPORT_MODE as quick workaround to install/test unstable versions
# 2018-02-22 Script version 1.5.1
#			 Adjusted umask and datapath group rights, default paths according to http://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html
#            Functions vs_usage and vs_out with improved formatting (to console and syslog), e.g. for fatal errors like failed install checks
#            Refactor vs_status as vs_get_status to get unique service instance status independent from user
#            Streamlined version check, code backup, data backup, setup (eliminating redundant tasks)
#            Prompt to run ./server.sh setup instead of calling setup function directly
#            Replaced workarounds (vs_version datapath handling, process identification, unstable versions, NO_SUPPORT_MODE)
#            Enhanced update and reinstall supporting VS api server and download checksums (using wget keypinning for additional security)
#            Clean getopts handling, config options (etc/opt/.vintagestory) to eliminate the need of patching hardcoded values in server.sh
#            Standardized headers, naming, coding conventions (minimizing sideeffects, ...), ported to /bin/sh for better POSIX conformity
#            Command conflict/status model: Restart will only start if server was previously started, etc.
#            Naming conventions and housekeeping features for world data, rollback of SW installs, recover of data backups
# 2018-03-01 Script version 1.5.1.1 (revoked)
#            Fixed (01): Empty migration list will not offered for a interactive selection
#            Fixed (02): Server commands wait for indicator log keyword (instead of fixed time): vs_stop, vs_start, vs_backup
#            Fixed (03): Migrating a folder with multiple worlds preserves the active serverconfig and does not overwrite worlds
#            Fixed (04): Script recognized legacy world saves in the datapath and imports them without user interaction
#            Fixed (05): Additional check during start command to prevent starting multiple servers in parallel (on the same port)
#            Fixed (06): Ownership and group rights of /etc/opt configfile adjusted to root, ownership checked before creating link to configfile
#            Fixed (07): Setup maintains legacy saves once per new VS_DAT location - client specific DATADIR is always pruned from the legacy search
#            Fixed (08): Specific world migration condition for backup task and vs_get_world_id match, duplicate check for world selection condition
#            Fixed (09): Restart and migration after reinstall now recognizes the migrated world properly, error handling of the backup function
#            Fixed (10): Command substitution of vs_command, vs_get_status, vs_get_world_id, vs_host_connect replaced to fix abort
#            Fixed (11): Creating world data folder (including minial serverconfig) not without confirmation, especially not on read-only tasks
#            Fixed (12): Processing of online backup filenames now produces the correct world name input for the recovery function
#            Reduce (sometimes confusing) console output to a reasonable minimum by using debug loglevel
# 2018-03-03 Script version 1.5.1.2
#            Fixed: Setting executable rights properly (now works with /bin/sh too)
#            Fixed: Prevent 1.5.1.6 crash caused by invalid seeds in serverconfig files by limiting seed to 9 decimal digits
#            Usability: Import of legacy worlds keeps seed value from server logfile
#            Usability: Better status handling for recovery, Failed requirement check asks for confirmation
# 2018-03-23 Script version 1.5.1.3
#            Fixed: \n output with some shell implementations
#            Pass -l & -p parameter to set_env function for technical lock handling and technical default port handling
#            Tweak: Startup conflict handling considers the port number: multiple servers can be started as long as port numbers are different
#            Tweak: Recognize need of setup even on manual installation in the default path
#            Tweak: lowered the required screen version and rephrased abort message (that already allows to continue anyway).
#            Tweak: option to continue even on installation inconsistency (considering messing up by manual installation)
#            Tweak: more verbose output to the syslog facility
# 2018-03-26 Script version 1.5.1.4
#            Fixed: Removed user switch related to exit E#24 (user switch is not needed and in some constellations not possible)
#            Fixed: \n output with some shell implementations (special printf handling for log output that may contain % characters)
#            


#######################################
# Standard output (logger) and exit
# Globals:
#   VS_PID : script pidfile
# Arguments:
#   $1 : flag -a|-q (opt. abort|quiet)
#   $2 : msg text   (opt.)
#   $3 : ret value  (opt.)  
# Returns:
#   $3 : 1-n (according to ret value)
#######################################
vs_out() {
  case ${1} in
    -a) shift; local abort=' - aborting'  ;;
    --) shift                             ;;
  esac
  local msg="${1}"
  local ret=${2:-0}
  local me="${USER:=$(id -un)}"    # no console TS by printf "%(%Y-%m-%d %H:%M:%S)T ..." -1 (not posix compliant) 
  if [ -n "${msg}" ] ; then
    case ${ret} in    
     -1) logger -p user.debug   -t "${0##*/}[$$]" "(${me})  <debug> ${msg}${abort}"
         [ ${ret} -ge ${VS_LVL:=0} ]    && printf   "<debug> ${msg}${abort}\n" 
         ret=0 ;;  
      0) logger -p user.info    -t "${0##*/}[$$]" "(${me})  <info>  ${msg}${abort}"
         printf   "<info>  ${msg}${abort}\n"
               ;;  
      1) logger -p user.warning -t "${0##*/}[$$]" "(${me})  <warn>  ${msg}${abort}"
         [ ${ret} -ge ${VS_LVL:=0} ]    && printf   "<warn>  ${msg}${abort}\n"  >&2
               ;;
      2) logger -p user.error   -t "${0##*/}[$$]" "(${me})  <error> ${msg}${abort}"
         [ ${ret} -ge ${VS_LVL:=0} ]    && printf "\n<error> ${msg}${abort}\n"  >&2
               ;;
      *) logger -p user.crit    -t "${0##*/}[$$]" "(${me})  <fatal> ${msg}${abort}"
         printf "\n<fatal> ${msg}${abort}\n" >&2
               ;;
    esac
  fi
  if [ -n "${abort}" ] ; then
     echo
     [ "$(cat ${VS_PID:-pidfile?} 2>/dev/null)" = "$$" ] && rm -f "${VS_PID}"
     exit ${ret} 
  fi
  return ${ret}
}

#######################################
# Formatted usage output
# Globals:
#   none
# Arguments:
#   $1 : flag e.g. -a (opt.)
# Returns:
#   0  : always OK
#######################################
vs_usage() {
  local script="${0##*/}"
  printf "\nUse: ${script} [OPTION]... (setup | update | reinstall | rollback)  \n"
  printf " or: ${script} [OPTION]... (start | stop | restart | status | backup | recover)\n"
  printf " or: ${script} [OPTION]... command SERVER_COMMAND\n"
  printf "\nSetup options:\n -o OWNER     Set custom owner name for software setup.\n -b BASEDIR   Set custom full directory path for software installation.\n"
  printf " -d DATADIR   Set custom full directory path for world data access.\n -C | -R      Consider complete|reduced package for installation.\n"
  printf "\nGeneral options:\n -v VERSION   Set reference versionstring (not latest version).\n -w WORLD     Set custom world subdirectory for data access.\n"
  printf " -U | -S      Consider unstable|stable branch for installation.\n -T           Trace script run in test mode (ignoring some checks).\n"
  printf "\nTechnical options:\n -l PID       Consider the lock that is hold by process id PID\n"
  printf " -p PORT      Set custom port to create or import world instances\n"
  printf "\nServer Commands:\n Try '${script} command help' for available server commands.\n\n"
  if [ -n "${1}" ] ; then
     vs_out ${1} '' ${2:-0}
  fi 
  return ${2:-0}
}

# specific usage hint
VS_UI1="${0##*/} [-o OWNER] [-b BASEDIR] [-d DATADIR] [-v VERSION] [-C|-R] setup"
VS_UI2="${0##*/} [-v VERSION] [-U|-S] reinstall"

#######################################
# Run shell command as VS user
# Globals:
#   VS_OWN : world data owner
# Arguments:
#   $1 : command
# Returns:
#   n  : command return code
#######################################
vs_user() {
  if [ "$(id -u)" = 0 ] ; then
    su "${VS_OWN}" -s /bin/sh -c "umask 002; ${1}"    # intentionally no su - to prevent login shell output or nasty user profile to interact with the script
    return $?
  else
    /bin/sh -c "umask 002; ${1}"
    return $?
  fi
}

#######################################
# Check higher & print delta (max 5 digits)
# Globals:
#   none
# Arguments:
#   $1 : flag -q (opt. quiet)
#   $1 : current version
#   $2 : other version (opt.)
# Returns:
#   0  : other version higher
#   1  : other version lower or equal
#######################################
vs_higher() {
  case ${1} in
	-q) shift; local flag='-q'            ;;
    --) shift                             ;;
  esac
  local delta=$(( $(echo "${1}00000"|tr -dc '[:digit:]'|cut -c-5) - $(echo "${2}00000"|tr -dc '[:digit:]'|cut -c-5) ))
  [ "${flag}" != '-q' ] && echo ${delta} ; [ ${delta} -lt 0 ]
}

#######################################
# Confirmed abort of the script
# Globals:
#   None
# Arguments:
#   $1 : msg text   (opt.)
#   $2 : ret value  (opt.)  
# Returns:
#   1  : abort not confirmed (otherwise abort)
#######################################
vs_abort() {
  vs_out "${1}" 1
  if [ -z "${VS_TST}" ] ; then
    echo; local reply; read -p "ABORT REQUESTED to avoid further issues. Continue anyway? (y/N) " -r reply
    [ "${reply}" = 'y' -o "${reply}" = 'Y' ] && echo || vs_out -a '' ${2:-3}
  fi
  return 1
}

#######################################
# Check installed tools
# Globals:
#   nones
# Arguments:
#   $1 : tool name
#   $2 : version limit (opt.)
#   $3 : check pattern (opt.)
# Returns:
#   0  : always OK (otherwise abort or warn)
#######################################
vs_toolcheck() {
  local tool="${1}"
  local version="${2}"
  local pattern="${3:-${1} }"
  hash "${tool}" 2>/dev/null || vs_abort "Vintage Story requires '${tool}' but it's not installed" 3
  if [ -n "${version}" ] ; then
      vs_higher -q "$("${tool}" --version | grep -i "${pattern}")" "${version}" >/dev/null && vs_abort "Not found: ${tool} version > ${version}" 3
  fi
  return 0
}

#######################################
# Get the VS server instance run status
# Globals:
#   VS_BIN : VS binary name
#   VS_DAT : world data root folder
# Arguments:
#   $1 : -v VAR (opt. variable returns status)
#   $2 : server instance (world id) 
# Returns:
#   0  : server instance up an running
#   1  : server instance not running
#   2  : indeterminate / not responding
#######################################
vs_get_status() {
  local var=''; local val=0
  case ${1} in
	-v) shift; var=${1}; shift ;;
    --) shift                  ;;
  esac
  [ -z "${1}" ] && vs_out -a "vs_get_status() mandatory parameter missing: server instance (world id)" 3
  local world="${1}";  
  local inst="${VS_BIN} --dataPath ${VS_DAT}/${world}"                    # each instance is defined by its own data path
  local run_info=$(cat "${VS_DAT}/${world}/.info"  2>/dev/null)
  local target_status="${run_info%:*}"
  _pid=$(pgrep -fx "mono ${inst}.*")               || [ $? -eq 1 ]        || vs_out -a "Unexpected condition E#10" 3
  if [ -z "${_pid}" ] ; then
    val=1; [ -z "${var}" ]   && vs_out "${inst} (to be ${target_status:-STOPPED}) is not running" ${val} 
  else     # workaround: ensure that service is not about to terminate (server might be waiting for confirmation input after crash)
    vs_command -v _stat_msg "${world}" "stats"     || [ $? -eq 1 ]        || vs_out "Indeterminate ${inst} (to be ${target_status:-STOPPED})" 2 || return $?  
    sleep .5
    _pid=$(pgrep -fx "mono ${inst}.*")             || [ $? -eq 1 ]        || vs_out -a "Unexpected condition E#11" 3
    if [ -z "${_pid}" ] ; then
      val=1; [ -z "${var}" ] && vs_out "${inst} (to be ${target_status:-STOPPED}) is not running" ${val} 
    elif [ -z "${_stat_msg}" ] ; then
      val=2; [ -z "${var}" ] && vs_out "${inst} (to be ${target_status:-STOPPED}) is running but not responding" ${val}
    else   # in quiet mode we want only one output line (only one status code)
      [ -z "${var}" ] && vs_out "$(printf "Server response\n\n%s\n " "${_stat_msg##*] }")"
      [ -n "${run_info#*:}" -a "${run_info#*:}" != "${_VER}" ] && target_status="RESTARTED with new v${_VER}" 
      [ -z "${var}" ] && vs_out "${inst} (to be ${target_status:-STOPPED}) is up and running" ${val} 
    fi
  fi
  [ -n "${var}" ] && eval "${var}='${val}'"
  return ${val}
}

#######################################
# Send VS server instance command
# Globals:
#   VS_DAT : world data root folder
# Arguments:
#   $1 : -v VAR (opt. variable returns output)
#   $2 : -k KEY (opt. keyword limits output)
#   $3 : server instance (world id)
#   $* : command sequence to send  
# Returns:
#   0  : command success
#   1  : no command response
#   2  : command not sent
#######################################
vs_command() {
  local key=''; local var=''; local val=''; local ret
  case ${1} in
	-k) shift; key=$(printf "${1:-'] Handling'}\n] Unknown\n"); var='tmp'; shift ;;
	-v) shift; var="${1}"; shift                                                 ;;
    --) shift                                                                    ;;
  esac
  [ -z "${1}" ] && vs_out -a "vs_command() mandatory parameter missing: server instance (world id)" 3
  local world="${1}"; shift       
  local cmd="${*}"
  if [ "${world#w[0-9][0-9]-}" != "${world}" -a -n "${cmd}" ] ; then
    local inst_log="${VS_DAT}/${world}/Logs/server-main.txt"
    set -- $(wc -l "${inst_log}" 2>/dev/null) 0                       # set pre line count as $1
    if vs_user "screen -p 0 -S ${world} -X eval 'stuff \"/${cmd}\"\015' >/dev/null 2>&1" ; then
      local time=0; local timeout=450                                 # 450 * 0.1 = 45 sec
      while [ ${time} -lt ${timeout} ]; do
        time=$(( time + 1 )); sleep .1                                # expect a fast result within .1 seconds
        tail -n10 "${inst_log}" | grep -qF "${key}" && break          # only one loop if no key is set
      done
      [ ${time} -ge ${timeout} ] && vs_out "Server command timeout" ${ret:=1}
      set -- ${1} $(wc -l "${inst_log}" 2>/dev/null) 0                # set post line count as $2
      if [ ${2} -ne ${1} -a ${2} -gt 0 ] ; then
        val=$(tail -n $(( ${2} - ${1} )) "${inst_log}")               || vs_out -a "Unexpected condition E#12" 3
        if   [ -z "${var}" ]       ; then echo "${val}"
        elif [ "${var}" != "tmp" ] ; then eval "${var}='${val}'"
        fi 
      else
        [ -z "${var}" -a -z "${key}" ] && vs_out "No '${cmd}' response in ${inst_log}" ${ret:=1}
      fi
    else
      [ -z "${var}" -a -z "${key}" ] && vs_out "Failed to execute command '${cmd}'" ${ret:=2} 
    fi
  else
    vs_out -a "Specify command for valid server instance. Use '${0##*/} command help' to query available commands" 2
  fi
  return ${ret:=0}
}

#######################################
# Stop VS server instance
# Globals:
#   VS_BIN : VS binary name
#   VS_DAT : world data root folder
#   VS_PIF : port information file
#   VS_IPN : instance port number
# Arguments:
#   $1 : server instance (world id) 
#   $2 : target status (opt.) 
# Returns:
#   0  : stopped
#   2  : not stopped
#######################################
vs_stop() {
  [ -z "${1}" ] && vs_out -a "vs_stop() mandatory parameter missing: server instance (world id)" 3
  local world="${1}" ; shift     
  local inst="${VS_BIN} --dataPath ${VS_DAT}/${world}"                              # each instance is defined by its own data path
  local run_info=$(cat "${VS_DAT}/${world}/.info" 2>/dev/null)
  local target_status="${1:-STOPPED:${run_info#*:}}" 
  local status; vs_get_status -v status "${world}"
  case "${status}" in
    1)  vs_out "${inst} (to be ${target_status%:*}) was not running." -1
        [ "$(cat ${VS_PIF}.${VS_IPN} 2>/dev/null)" = "${world}" ] && rm -f "${VS_PIF}.${VS_IPN}"
        ;;
    *)  vs_out "Stopping ${inst} (to be ${target_status%:*}) ..." -1
        vs_user "printf '${target_status}' >'${VS_DAT}/${world}/.info' 2>/dev/null" || vs_out -a "Unexpected condition E#13b" 3
        vs_command -k '] Message' "${world}" 'announce SERVER SHUTTING DOWN IN 10 SECONDS.' && sleep 10
        vs_command -k '] Stopped' "${world}" 'stop'
        vs_get_status -v status "${world}"
        if [ "${status}" != "1" ] ; then
          vs_user "screen -p 0 -S ${world} -X quit"                                 || vs_out -a "Unexpected condition E#13" 3
          vs_get_status -v status "${world}"
        fi
        if [ "${status}" != "1" ] ; then
          vs_out "${inst} (to be ${target_status%:*}) could not be stopped." 2
        else
          vs_out "${inst} (to be ${target_status%:*}) is stopped." -1
        fi
        rm -f "${VS_PIF}.${VS_IPN}"                                                 || vs_out -a "Unexpected condition E#13c" 3
        ;;
  esac
  return $?
}

#######################################
# Start VS server instance
# Globals:
#   VS_BIN : VS binary name
#   VS_BAS : SW install base dir
#   VS_DAT : world data root folder
#   VS_PIF : port information file
#   VS_IPN : instance port number
#   VS_RTR : change restart tracker
#   VS_TST : test and trace flag
#   OPTIONS
# Arguments:
#   $1 : server instance (world id) 
#   $2 : target status (opt.) 
# Returns:
#   0  : started
#   1  : not responding
#   2  : not started
#######################################
vs_start() {
  [ -z "${1}" ] && vs_out -a "vs_start() mandatory parameter missing: server instance (world id)" 3
  local world="${1}" ; shift  
  local other=$(cat "${VS_PIF}.${VS_IPN}" 2>/dev/null)
  [ -n "${other}" -a "${other}" != "${world}" ] && vs_out -a "World ${other} was previously started. Check and try again" 2
  local inst="${VS_BIN} --dataPath ${VS_DAT}/${world}"                                         # each instance is defined by its own data path
  local run_info=$(cat "${VS_DAT}/${world}/.info" 2>/dev/null)
  local target_status="STARTED:${_VER}" 
  local status; vs_get_status -v status "${world}"
  case "${status}" in
	0)  vs_out "${inst} (to be ${target_status%:*}) is already running." -1 ;;
    1)  vs_out "Starting ${inst} (to be ${target_status%:*}) ..." -1
        if [ -d "${VS_DAT}/${world}" ] ; then 
          [ "${run_info#*:}" != "${_VER}" ] && vs_out -a "World ${world} was previously saved with divergent version v${run_info#*:}. Please run backup first" 1
        else
          vs_set_workdir "${world}" || vs_out -a "Preparation and start of world data '${world}' canceled" 1
        fi
        vs_user "cp -f '${VS_BAS}/.tag' '${VS_RTR}'"                                           # allow to track needed restarts caused by SW updates, tag will not be deleted by reboot
        vs_user "printf '${target_status}' >'${VS_DAT}/${world}/.info'   2>/dev/null"          || vs_out -a "Unexpected condition E#14b" 3
        vs_user "printf '${world}' >'${VS_PIF}.${VS_IPN}'                2>/dev/null"          || vs_out -a "Unexpected condition E#14c" 3
        vs_user "cd '${VS_BAS}' && screen -h 1024 -dmS ${world} mono ${inst} ${OPTIONS}"       || vs_out -a "Unexpected condition E#14" 3
        sleep 2                                                                                # allow server to initialize the logfiles and the directories in case of an initial startup
        vs_command -k '] Seed' "${world}" 'seed'
        if ! vs_get_status -v status "${world}"; then
          [ "$(cat ${VS_PIF}.${VS_IPN} 2>/dev/null)" = "${world}" ] && rm -f "${VS_PIF}.${VS_IPN}"
          vs_out "${inst} (to be ${target_status%:*}) could not be started." 2
        else
          vs_out "${inst} (to be ${target_status%:*}) is started." -1
        fi
        [ -n "${VS_TST}" ] && vs_command -k '] Message' "${world}" "announce WARNING - ${inst} was started in TEST MODE" >/dev/null 
        ;;
    2)  vs_out "${inst} (to be ${target_status%:*}) is already running but not responding. Check an try again" 1 ;;
  esac
  return $?
}

#######################################
# Recover VS working directory from backup
# Globals:
#   VS_VER : target version (getopts)
#   VS_DAT : world data root folder
# Arguments:
#   $1 : server instance (world id) 
# Returns:
#   0  : finished OK (otherwise abort)
#   1  : need backup folder setup
#######################################
vs_recover() {
  [ -z "${1}" ] && vs_out -a "vs_recover() mandatory parameter missing: server instance (world id)" 3
  local world="${1}"
  local bak=$(ls -tdx ${VS_DAT}/backup/vs_${world}_*_v${VS_VER}*.tar.gz 2>/dev/null | head -n1)
  if [ -f "${bak}" ] ; then
    echo; local reply; read -p "CONFIRMATION REQUIRED: Recover world ${world} from ${bak} (Y/n) " -r reply
    [ "${reply}" = 'n' -o "${reply}" = 'N' ] && return 0 || echo 
    vs_out "Trying to recover ${world} from ${bak} ..." -1
    rm -fr /tmp/vs-recover.*  
    vs_user "mkdir -m 775 -p /tmp/vs-recover.$$                     2>/dev/null"  || vs_out -a "Unexpected condition E#19" 3
    vs_user "tar xzf ${bak} -C /tmp/vs-recover.$$                   2>/dev/null"  || vs_out -a "Unexpected condition E#20" 3
    local io=$(cat "/tmp/vs-recover.$$/.info"                       2>/dev/null)
    local in=$(cat "${VS_DAT}/${world}/.info"                       2>/dev/null)
    vs_user "printf '${in%:*}:${io#*:}' >'/tmp/vs-recover.$$/.info' 2>/dev/null"  || vs_out -a "Unexpected condition E#25" 3
    touch -cr "${VS_DAT}/${world}/.info" "/tmp/vs-recover.$$/.info" 2>/dev/null   # keep the timestamp of previous version if available
    vs_migrate "/tmp/vs-recover.$$" '*.vcdbs' "${world}"
    rm -fr "/tmp/vs.recover.$$"
    vs_out "Finished recovery of ${world}" 0
  else
    vs_out "No backup available for recovery" 1
  fi 
}

#######################################
# Backup VS working directory
# Globals:
#   VS_NUM : threshold (count) to keep backups
#   VS_DAT : world data root folder
#   VS_UI1 : setup usage info
#   _VER   : actual version (install)
# Arguments:
#   $1 : flag -m (opt. migrate)
#   $2 : work dir (for data)
# Returns:
#   0  : finished OK
#   1  : finished online (no full backup)
#   2  : need backup folder setup
#######################################
vs_backup() {
  local flag
  case ${1} in
	-m) shift; flag='-m'                  ;;
    --) shift                             ;;
  esac
  local wd="${1}"; local wn; vs_get_world_id -v wn "${wd##*/}"
  local ri=$(cat "${VS_DAT}/${wn}/.info" 2>/dev/null); ri="${ri#*:}"
  local bk="$(date +%F_%T)_v${ri:--legacy}"; local bn="${bk}_${wn}.vcdbs"
  local fl="Backups/${bn} serverconfig.json servermagicnumbers.json .info"
  local fn="${VS_DAT}/backup/vs_${wn}_${bk}"
  if [ -d "${VS_DAT}/backup" ] ; then
    if [ "${flag}" != '-m' ] && vs_get_status -v flag "${wn}" ; then
      vs_out "Start online world backup of ${wd} ..." -1
      ls -tdx ${wd}/Backups/*_${wn}.vcdbs 2>/dev/null          | sed -e "1,${VS_NUM}d" | xargs rm -f              || vs_out "Housekeeping of online backup databases failed" 2
      ls -tdx ${VS_DAT}/backup/vs_${wn}_*_o.tar.gz 2>/dev/null | sed -e "1,${VS_NUM}d" | xargs rm -f              || vs_out "Housekeeping of online backup archives failed" 2
      vs_command -k '] Backup' "${wn}" "genbackup ${bn}" && vs_user "chmod -f g+w ${wd}/Backups/${bn}"
      [ -f "${wd}/Backups/${bn}" ]                                                                                || vs_out -a "Online backup not available" 3
      vs_user "tar czf '${fn}_o.tar.gz' --transform 's+Backups/${bk}_+Saves/+g' -C ${wd} ${fl}"                   || vs_out -a "Online backup failed" 3
      vs_out "Created backup ${fn}_o.tar.gz (online)" 0
    else
      vs_out "Start full data backup of ${wd} ..." -1
      ls -tdx ${VS_DAT}/backup/vs_${wn}_*_f.tar.gz 2>/dev/null | sed -e "1,${VS_NUM}d" | xargs rm -f              || vs_out "Housekeeping of old full backup archives failed" 2
      vs_user "tar czf '${fn}_f.tar.gz' -C ${wd} . --exclude=backup"                                              || vs_out -a "Full backup failed" 3
      vs_out "Created backup ${fn}_f.tar.gz (full)" 0
      [ "${wd%/*}" = "${VS_DAT}" -a -d "${VS_DAT}/${wn}" -a "${ri#*:}" != "${_VER}" ]                             && vs_migrate "${VS_DAT}/${wn}" '*.vcdbs' "${wn}"
   fi
  else
	vs_out "Please run '${VS_UI1}' with proper privileges to setup ${VS_DAT}/backup first." 2                     # missing folder would indicate a general setup issue
  fi
} 

#######################################
# Get VS host connectstring if available 
# Globals:
#   none
# Arguments:
#   $1 : -v VAR (opt. variable returns connectstring)
#   S2 : package | release
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_host_connect() {
  local var=''; local val=''
  case ${1} in
	-v) shift; var=${1}; shift ;;
    --) shift                  ;;
  esac
  case "${1}" in
    package) local hash='l59rOf/3g9fX7Nxyhg457pQkFONpCN7R/ovScanZ0+g='
             local host='account.vintagestory.at'; local port='443';;
    release) local hash='l59rOf/3g9fX7Nxyhg457pQkFONpCN7R/ovScanZ0+g='
             local host='api.vintagestory.at'; local port='443';;
    *)       vs_out -a "Unexpected condition E#16" 3 ;; 
  esac
  _test=$(echo | openssl s_client -showcerts -servername "${host}" -connect "${host}:${port}" 2>/dev/null | openssl x509 -inform pem -noout -pubkey) || vs_out -a "Unexpected condition E#17" 3
  _test=$(echo "${_test}" | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64) || vs_out -a "Unexpected condition E#18" 3
  if [ "${_test}" = "${hash}" ] ; then
    val="--pinnedpubkey=sha256//${hash} --https-only https://${host}:${port}"
    [ -n "${var}" ] && eval "${var}='${val}'" || echo "${val}"
  else
    vs_out -a "Cannot get VS ${1} host (E#18). Please contact VS support for advisory" 3
  fi
  return $?
}

#######################################
# Try to fix some known oddities
# Globals:
#   none
# Arguments:
#   $1 : target path
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_fix_inst() {
  local target="${1}"
  local IFS="$(printf "\n\b")"
  for i in $(find "${target}/assets"); do 
    local filename="${i##*/}"
    local lowername="$(echo ${filename} | tr '[:upper:]' '[:lower:]')"
    if [ "${filename}" != "${lowername}" ] ; then                                            # check if there is a asset file that is not lowercase 
      vs_out "Asset '${filename}' is not lowercase" -1                                       # complain
      [ -e "${i%/*}/${lowername}" ] || vs_user "ln -sf '${filename}' '${i%/*}/${lowername}'" # create a lowercase symlink to fix it
    fi 
  done
}

#######################################
# Load, verify, install VS archive
# Globals:
#   VS_NUM : threshold (count) to keep backups
# Arguments:
#   $1 : stable | unstable (branch)
#   $2 : archive name
#   $3 : target path
# Returns:
#   0  : always OK (otherwise abort)
#   2  : archive corrupted
#######################################
vs_tar_install() {
  local branch="${1}"
  local archive="${2}"
  local target="${3}"
  local nstamp="$(date +%F_%T)"
  local ostamp="${_DTS}"
  vs_out "Try downloading files/${branch}/${archive}.tar.gz"
  [ "${branch}" = 'pre' -o "${branch}" = 'unstable' ]                                                                          && vs_out "Be aware that branch '${branch}' is not intended for productive use" 1
  local connect; vs_host_connect -v connect 'package'                                                                          # otherwise abort
  wget ${connect}/files/${branch}/${archive}.tar.gz -q -c -O "/tmp/${archive}.tar.gz"
  file "/tmp/${archive}.tar.gz" | grep -q 'HTML'                                                                               && vs_out -a "Remote package ${archive} not found" 3
  file "/tmp/${archive}.tar.gz" | grep -q 'gzip'                                                                               || vs_out -a "Dowloaded package ${archive} is no gzip format" 3
  set -- $(wget ${connect}/files/${branch}/${archive}.md5 -q -O -)
  set -- "${1}" $(md5sum "/tmp/${archive}.tar.gz")
  [ "${branch}" = 'pre' -a -z "${1}" ] && vs_out "No checksum for ${archive} available. Be aware that testing on productive machines is always risky" 1
  if [ "${branch}" = 'pre' -a -z "${1}" ] || [ "${1}" = "${2}" ] ; then
    rm -fr ${target}.new.* 
    vs_user "mkdir -m 775 -p ${target}.new.$$      2>/dev/null"                                                                || vs_out -a "Unexpected condition E#19" 3
    vs_user "echo ${branch} ${archive} ${nstamp} > ${target}.new.$$/.tag; tar -xzf /tmp/${archive}.tar.gz -C ${target}.new.$$" || vs_out -a "Unexpected condition E#20" 3
    mv -f ${target}.new.$$/vintagestory/* "${target}.new.$$" 2>/dev/null && rm -fr ${target}.new.$$/vintagestory               # try might fail
    vs_user "cd ${target}.new.$$; chmod -fR -x+X .; chmod -f ug+x *.exe *.sh"
    rm -rf "/tmp/${archive}.tar.gz" "/tmp/${archive}.tar.gz.corrupt"
    vs_fix_inst "${target}.new.$$"
    if [ -d "${target}" ] ; then
      ls -tdx ${target}.bak_* 2>/dev/null | sed -e "1,${VS_NUM}d" | xargs rm -fr                                               || vs_out "Housekeeping of old SW backups failed" 2
      vs_user "cp ${target}/.tag ${target}.new.$$/.old"
      mv -fT "${target}" "${target}.bak_${ostamp}"
    fi 
    mv -fT "${target}.new.$$" "${target}"                                                                                      || vs_out -a "Unexpected condition E#21" 3
    rm -fr ${target}.new.* 
    vs_set_env '' "${branch}" "${archive#vs_*_}"                                                                               # abort with error if version mismatch
  else
    mv -f "/tmp/${archive}.tar.gz" "/tmp/${archive}.tar.gz.corrupt" 
    vs_out "Package /tmp/${archive} seems to be corrupted (thus not installed). Retry or contact VS support for advisory." 2
  fi
  return $?
}

#######################################
# Rollback previouse VS software
# Globals:
#   VS_BAS : SW install base dir
#   _VER   : actual version (install)
#   _DTS   : actual install timestamp
# Arguments:
#   none
# Returns:
#   0  : always OK (otherwise abort)
#   1  : rollback not possible
#######################################
vs_rollback() {
  local target="${VS_BAS}"
  set -- $(cat "${target}/.old" 2>/dev/null); local ostamp="${3:-*}"                                                           # read rollback parameters from .old file 
  local bak=$(ls -tdx ${target}.bak_${ostamp} 2>/dev/null | head -n1)
  if [ -d "${bak}" ] ; then 
    echo; local reply; read -p "CONFIRMATION REQUIRED: Rollback Vintage Story v${_VER} to previous ${1:-version} ${2} (Y/n) " -r reply
    [ "${reply}" = 'n' -o "${reply}" = 'N' ] && return 0 || echo 
    vs_out "Trying to rollback Vintage Story from current v${_VER} to previous ${1:-version} ${2} ..." -1 
    [ -d "${target}" ] && mv -fT "${target}" "${target}.rollbak_${_DTS}"
    mv -fT "${bak}" "${target}"                                                                                                || vs_out -a "Unexpected condition E#21" 3
    rm -fr "${target}.rollbak_${_DTS}" 
    vs_set_env '' "${1}" "${2}"                                                                                                # abort with error if version mismatch
    vs_out "Finished rollback to v${_VER}" 0
  else
    vs_out "No backup for fast rollback available - try to reinstall previous ${1:-version} ${2}" 1 
  fi
}

#######################################
# Update VS software
# Globals:
#   VS_TAG : (param 1 default)
#   VS_TYP : (param 2 default)
#   VS_VER : target version (getopts)
#   VS_BAS : SW install base dir
#   _TAG   : actual branch stable | unstable
#   _VER   : actual version (install)
# Arguments:
#   $1 : stable | unstable (opt. branch)
#   $2 : server | archive  (opt. type)
# Returns:
#   0  : finished update OK
#   1  : finished NO update
#   2  : canceled update NOK
#######################################
vs_update() {
  local branch="${1:-${VS_TAG}}"
  local newversion="${VS_VER}"
  if [ "${newversion}" = "${_VER}" ] ; then
    local connect; vs_host_connect -v connect 'release'         # otherwise abort
    newversion="$(wget ${connect}/latest${branch}.txt -q -O -)" || vs_out -a "Cannot get regular version info for branch '${branch}'" 3
    if [ "${branch}" != 'stable' ] ; then
      stable="$(wget ${connect}/lateststable.txt -q -O -)"      || vs_out -a "Unexpected condition E#22" 3
      if vs_higher -q ${newversion} ${stable} ; then
        local branch='stable'
        local newversion="${stable}"
      fi
    fi
  fi
  vs_out "Considering latest version v${newversion} belonging to the '${branch}' branch" -1
  if vs_higher -q ${_VER} ${newversion} ; then
    local archive="${2:-${VS_TYP}}_${newversion}"
    echo; local reply; read -p "CONFIRMATION REQUIRED: Update Vintage Story ${_TAG} v${_VER} to newer ${branch} v${newversion} (Y/n) " -r reply
    [ "${reply}" = 'n' -o "${reply}" = 'N' ] && return 0 || echo 
    vs_out "Updating Vintage Story from ${_TAG} v${_VER} to ${branch} v${newversion} ..." -1
    if vs_tar_install "${branch}" "${archive}" "${VS_BAS}" ; then
      vs_out "Finished update to v${newversion}" 0
    else
      vs_out "Canceled update to v${newversion}." 2
    fi
  else
    vs_out "No matching update for Vintage Story v${_VER} available." 1
  fi
  return $?
}

#######################################
# Clean reinstall VS software
# Globals:
#   VS_TAG : target branch stable | unstable
#   VS_TYP : target type vs_server | vs_archive
#   VS_VER : target version (getopts)
#   VS_BAS : SW install base dir
# Arguments:
#   none
# Returns:
#   0  : finished reinstall OK
#   2  : canceled reinstall NOK
#######################################
vs_reinstall() {
  local version="${VS_VER}"
  local connect; vs_host_connect -v connect 'release'        # otherwise abort
  if [ -z "${version}" ] ; then
    version="$(wget ${connect}/latest${VS_TAG}.txt -q -O -)" || vs_out -a "Cannot get version info for branch '${VS_TAG}'" 3
  fi
  local archive="${VS_TYP}_${version}"
  vs_out "Reinstalling Vintage Story ${VS_TAG} v${version} ..." -1
  if vs_tar_install "${VS_TAG}" "${archive}" "${VS_BAS}"; then
    vs_out "Finished reinstall v${version}" 0
  else
    vs_out "Canceled reinstall v${version}" 2
  fi
  return $?
}

#######################################
# Initial setup of VS environment
# Globals:
#   VS_NUM : threshold (count) to keep backups
#   VS_OLD : threshold (days) to maintain world saves
#   VS_DPN : default port number
#   VS_TAG : target branch stable | unstable
#   VS_TYP : target type vs_server | vs_archive
#   VS_OWN : owner of world data (server process)
#   VS_BAS : SW install base dir
#   VS_DAT : world data root folder
#   VS_LOG : logging root folder
#   VS_UI1 : setup usage info
# Arguments:
#   $1 :  target type vs_server | vs_archive
#   $2 :  owner of world data (server process)
#   $3 :  SW install base dir
#   $4 :  world data root folder
# Returns:
#   0  : OK
#   1  : canceled
# Redefines:
#   VS_CFG : configuration file
#######################################
vs_setup() {
  VS_TYP=${1:-${VS_TYP}}; VS_OWN=${2:-${VS_OWN}}; VS_BAS=${3:-${VS_BAS}}; VS_DAT=${4:-${VS_DAT}}
  vs_read_env "${VS_CFG}" HISTDIR DATADIR MENUDIR
  vs_out "CAUTION: Please ensure that no Vintage Story is running on this machine before setup confirmation." 1
  echo; local reply; read -p "CONFIRMATION REQUIRED: Basic setup: package='${VS_TYP}' branch='${VS_TAG}' version='${VS_VER}' owner='${VS_OWN}' basedir='${VS_BAS}' datadir='${VS_DAT}' (y/N) " -r reply
  echo
  if [ "${reply}" = 'y' -o "${reply}" = 'Y' ] ; then
    local path_list="${VS_BAS%/*} ${VS_DAT} ${VS_DAT}/backup ${VS_LOG}"
	if [ "$(id -un)" != "${VS_OWN}" ] ; then
      if ! getent passwd "${VS_OWN}"    >/dev/null ; then
        useradd -r -s "/bin/false" -U "${VS_OWN}"    >/dev/null 2>&1 || vs_out -a "Setup of user '${VS_OWN}' failed" 3
        vs_out "Setup new user: $(getent passwd "${VS_OWN}")"
      fi
      if ! getent group "${VS_OWN}"    >/dev/null ; then
        groupadd -r "${VS_OWN}"                      >/dev/null 2>&1 || vs_out -a "Setup of group '${VS_OWN}' failed" 3
        vs_out "Setup new group: $(getent group "${VS_OWN}")"
      fi
      [ -d '/etc/opt' ] && { chown root:root '/etc/opt'; chmod -fR g-w '/etc/opt'; } || mkdir -m 755 -p '/etc/opt'
      local dir; for dir in ${path_list} ; do
        if [ -d "${dir}" ] ; then
          chmod -fR g+w "${dir}"                     2>/dev/null     || vs_out -a "Path ${dir} privileges adjustment failed" 3
          chown -fR ${VS_OWN}:${VS_OWN} "${dir}"     2>/dev/null     || vs_out -a "Path '${dir}' ownership adjustment failed" 3
          vs_out "Adjusted path: $(ls -ld ${dir})" -1
        else
          mkdir -m 775 -p "${dir}"                   2>/dev/null     || vs_out -a "Path ${dir} creation failed" 3
          chown "${VS_OWN}:${VS_OWN}" -fR "${dir}"   2>/dev/null     || vs_out -a "Path '${dir}' privileges setup failed" 3
          vs_out "Setup new path: $(ls -ld ${dir})"
        fi
	  done
    else
      if ! getent group "${VS_OWN}"    >/dev/null 2>&1 ; then
        vs_out -a "User '${VS_OWN}' cannot setup missing group '${VS_OWN}'" 3
      elif ! id -nG | grep "${VS_OWN}" >/dev/null 2>&1 ; then
        vs_out -a "User '${VS_OWN}' cannot use existing group '${VS_OWN}'" 3
      fi
      for dir in ${path_list} ; do
        if ! [ -d "${dir}" ] ; then
          mkdir -m 775 -p "${dir}"                   2>/dev/null     || vs_out -a "Path ${dir} creation failed (try su)" 3
          chgrp "${VS_OWN}" -fR "${VS_BAS}"          2>/dev/null     || vs_out -a "Path '${dir}' group setup failed (try su)" 3           # attention: avoid links belonging to root!
          vs_out "Setup new path: $(ls -ld ${dir})"
        else
          chmod -fR g+w "${dir}"                     2>/dev/null     || vs_out -a "Path ${dir} privileges adjustment failed (try su)" 3
          chgrp "${VS_OWN}" -fR "${VS_BAS}"          2>/dev/null     || vs_out -a "Path '${dir}' group setup failed (try su)" 3           # attention: avoid links belonging to root!
          vs_out "Adjusted path: $(ls -ld ${dir})" -1
        fi
	  done
      VS_CFG="/home/${VS_OWN}/.vintagestory"                         # cfg is defined by setup and link is placed to persist this definition
    fi
    vs_write_env VS_NUM VS_OLD VS_DPN VS_TAG VS_TYP VS_OWN VS_BAS VS_DAT VS_LOG OPTIONS HISTDIR DATADIR
    [ -e "${VS_BAS%/*}/data" ] || vs_user "ln -sf '${VS_DAT}' '${VS_BAS%/*}/data'"
    [ -e "${VS_BAS%/*}/log" ]  || vs_user "ln -sf '${VS_LOG}' '${VS_BAS%/*}/log'"
    [ -e "${VS_DAT}/log" ]     || vs_user "ln -sf '${VS_LOG}' '${VS_DAT}/log'"
    vs_out "Basic environment setup finished" 0
    vs_reinstall && vs_restart -c  && vs_maintain_legacy ${VS_OLD}
    if [ -f "${VS_BAS}/Vintagestory.desktop" -a -d "${MENUDIR}" -a -z "${VS_MIN}" ] ; then
      vs_read_env "${VS_CFG}" FONTDIR DESKDIR
      vs_write_env VS_NUM VS_OLD VS_DPN VS_TAG VS_TYP VS_OWN VS_BAS VS_DAT VS_LOG OPTIONS HISTDIR DATADIR MENUDIR FONTDIR DESKDIR
      vs_out "Recreate desktop entries"     
      export APPDATA="${VS_BAS%/*}"; export INST_DIR="${VS_BAS##*/}"; export VERSION=""  # fit in existing destop template
      rm -f "${MENUDIR}/Vintagestory.desktop" && vs_user "envsubst < '${VS_BAS}/Vintagestory.desktop' > '${MENUDIR}/Vintagestory.desktop' && chmod -f ugo+x '${MENUDIR}/Vintagestory.desktop'";
      [ -d "${DESKDIR}" ] && vs_user "ln -sf '${MENUDIR}/Vintagestory.desktop' '${DESKDIR}/Vintagestory.desktop'"
      # for i in $(find "${VS_BAS}/assets/fonts" -name *.ttf -type f); do [ -f "${FONTDIR}/${i##*/}" ] || { vs_out "Install gamefont ${i##*/}"; cp -p "${i}" "${FONTDIR}"; }; done
    fi
  else
	vs_out "Setup for owner '${VS_OWN}' canceled\n" 1
	vs_out -a "Use: '${VS_UI1}'" 0
  fi
  return $?
}

#######################################
# Adjust workdir group ownership 
# Globals:
#   VS_OWN : world data owner
#   USER   : current user
# Arguments:
#   $1 : full workdir path
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_adjust_workdir() {
  [ -z "${1}" -o ! -d "${1}" ]                                                                 && vs_out -a "vs_adjust_workdir() parameter '${1}' is no valid workdir path" 3
  if [ "$(id -u)" = 0 ] ; then                                                                 # TODO TEST: group write adjustment needed for regular workdir run, eg. on shutdown? (other group users access)  
    chown "${VS_OWN}:${VS_OWN}" -fR "${1}"                                         2>/dev/null || vs_out -a "SU failed to adjust data privileges" 3
    chmod -fR 775 "${1}"                                                           2>/dev/null
  else
    umask 002
    find "${1}" -user "${USER}" | tr '\n' '\0' | xargs -0 -n1 chgrp -f "${VS_OWN}" 2>/dev/null || vs_out -a "${USER} failed to adjust data privileges" 3
  fi
}

#######################################
# Identify the current world folder
# Globals:
#   VS_BAS : SW install base dir
#   VS_DAT : world data root folder
# Arguments:
#   $1 : switch -y|-n to create world folder (opt)
#   $2 : world id (getopts)
# Returns:
#   0  : world folder set (workdir created)
#   1  : workdir not available
# Redefines:
#   VS_SUB : server instance (world id)
#   VS_IPN : instance port number
#######################################
vs_set_workdir() {
  local reply=''
  case ${1} in
	-n) shift; reply='n';;
    -y) shift; reply='y';;
  esac
  vs_get_world_id -v VS_SUB "${1}"                                       # Assumption: when /etc/vintagestory is present then setup is done, including directories like {VS_DAT}/backup
  if [ ! -d "${VS_DAT}/backup" ] ; then                                  # TODO TEST: need to recreate setup dirs on the fly if possible (instead requesting setup run as in vs_backup)
    vs_user "mkdir -m 775 -p '${VS_DAT}/backup'      2>/dev/null"        || vs_out -a "Recreating ${VS_DAT}/backup failed" 3
    vs_out "Recreated: $(ls -ld ${VS_DAT}/backup)" -1
    vs_adjust_workdir "${VS_DAT}/backup"
  fi                                                                     # Workaround: using vs_user and datapath should prevent wrong database creation
  if [ ! -d "${VS_DAT}/${VS_SUB}" -a -z "${reply}" ] ; then
    echo; read -p "CONFIRMATION REQUIRED: Prepare new world data folder '${VS_DAT}/${VS_SUB}' (y/N) " -r reply
    echo
  fi                              
  [ "${reply}" = 'y' -o "${reply}" = 'Y' ] && vs_gen_workdir "${VS_SUB}"
  local port=$(grep -s '"Port":' "${VS_DAT}/${VS_SUB}/serverconfig.json" | tr -dc '[:digit:]')
  export VS_IPN=${port:-${VS_DPN}}
  [ -d "${VS_DAT}/${VS_SUB}" ]
}

#######################################
# Read vintagestory ENV from filesystem
# Globals:
#   VS_CFG : configuration file
# Arguments:
#   $1   : config file path  
#   $2-n : list of variable names
# Returns:
#   0  : always OK (otherwise abort)
# Redefines:
#   VS_CFG : configuration file
#   _TAG   : actual branch stable | unstable
#   _TYP   : actual type vs_server | vs_archive
#   _VER   : actual version (install)
#   _DTS   : actual install timestamp
#######################################
vs_read_env() {
  VS_CFG="${1}"; shift
  [ -e "${VS_CFG}" ] || vs_read_var VS_CFG
  for var in "$@"; do
    vs_read_var "${var}" "${VS_CFG}"
  done
  set -- $(cat "${VS_BAS}/.tag" 2>/dev/null)
  _TAG="${1}"; 
  _TYP="${2%_*}"; _VER="${2##*_}"
  _DTS="${3}"
}

#######################################
# Write vintagestory ENV to filesystem
# Globals:
#   VS_CFG : configuration file
# Arguments:
#   $1-n : list of variable names
# Returns:
#   0  : always OK (otherwise abort)
# Redefines:
#   VS_CFG : configuration file
#######################################
vs_write_env() {
  [ -z "${VS_CFG}" ] && vs_read_var VS_CFG
  if [ -w "${VS_CFG}" -o ! -e "${VS_CFG}" ] ; then
    echo "# VS config setup $(date '+%F %T')" >"${VS_CFG}"
    for var in "$@"; do
      [ -z "$(eval echo "\$${var}")" ] && vs_read_var "${var}" "${VS_CFG}"
      echo "${var}='$(eval echo "\$${var}")'" >>"${VS_CFG}"
    done
    local etc="$(readlink -f -- "${0%/*}")/.etc"
    [ -O "${etc%/*}" ] && vs_user "ln -sf '${VS_CFG}' '${etc}'" # persist VS_CFG redefinition
  else
    vs_out "No privileges to write configuration file $(readlink -f -- "${VS_CFG}")" 1
  fi
}

#######################################
# Read vintagestory ENV from filesystem
# Globals:
#   none
# Arguments:
#   $1 : variable name
#   $2 : config file path
# Returns:
#   0  : always OK (otherwise abort)
# Redefines:
#   passed variable
#######################################
vs_read_var() {
  local p1="^${1}=['\"]*"; local p2='[-/_., [:alnum:]]+'
  local val="$(grep -m1 -Eo "${p1}${p2}" "${2}" 2>/dev/null | grep -m1 -Eo "${p2}" | tail -n1)"
  local home=$(eval echo "~${VS_OWN}")
  if [ -z "${val#*=}" ] ; then   # use predefined default values
    case ${1} in
      VS_NUM)      val=5                                      ;;
      VS_OLD)      val=180                                    ;;
      VS_DPN)      val=42420                                  ;;
      VS_TAG)      val='stable'                               ;;
      VS_TYP)      val='vs_server'                            ;;
      VS_OWN)      val='vintagestory'                         ;;
      VS_CFG)      val='/etc/opt/vintagestory'                ;;
      VS_BAS)      val='/opt/vintagestory/game'               ;;
      VS_DAT)      val='/var/opt/vintagestory'                ;;
      VS_LOG)      val='/var/log/vintagestory'                ;;
      VS_PID)      val='/var/lock/vs-command.pid'             ;;
      VS_PIF)      val='/var/lock/vs-port.info'               ;;
      VS_RTR)      val='/var/tmp/vs-command.tag'              ;;
      HISTDIR)     val="${home}/ApplicationData"              ;;
      DATADIR)     val="${home}/.config/VintagestoryData"     ;; # or use: "$(csharp -e 'print(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));' 2>/dev/null)/VintagestoryData"
      MENUDIR)     val="${home}/.local/share/applications"    ;; # for all: MENUDIR="/usr/share/applications"
      FONTDIR)     val="${home}/.fonts"                       ;; # for all: FONTDIR="/usr/share/fonts"
      DESKDIR)     val="$(xdg-user-dir DESKTOP)"              ;; # only for the user
    esac
  fi
  eval "export ${1}='${val#*=}'"
}

#######################################
# Identify and set VS instance parameters
# Globals:
#   VS_TYP : type vs_server | vs_archive
#   VS_OWN : world data owner
#   VS_BAS : SW install base dir
#   VS_SUB : server instance (world id)
#   VS_UI1 : setup usage info
#   VS_UI2 : reinstall usage info
#   _TAG   : actual branch stable | unstable
#   _TYP   : actual type vs_server | vs_archive
#   _VER   : actual version (install)
#   _DTS   : actual install timestamp
# Arguments:
#   $1 : script task (leave empty on second call)
#   $2 : branch stable | unstable
#   $3 : target version
#   $4 : server instance (world id)
#   $5 : default port number to consider (opt.)
#   $6 : pid of launching parent process (opt.)
# Returns:
#   0  : always OK (otherwise abort)
# Redefines:
#   VS_NUM : threshold (count) to keep backups
#   VS_OLD : threshold (days) to maintain world saves
#   VS_DPN : default port number
#   VS_BIN : VS binary name
#   VS_TAG : branch stable | unstable
#   VS_TYP : type vs_server | vs_archive
#   VS_OWN : world data owner
#   VS_VER : target version
#   VS_BAS : SW install base dir
#   VS_DAT : world data root folder
#   VS_SUB : server instance (world id)
#   VS_LOG : logging root folder
#   VS_PID : script pidfile
#   VS_PIF : port information file
#   VS_RTR : change restart tracker
#######################################
vs_set_env() {
  local etc="$(readlink -f -- "${0%/*}")/.etc"
  vs_read_env ${etc} VS_NUM VS_OLD VS_DPN VS_TAG VS_TYP VS_OWN VS_BAS VS_DAT VS_LOG VS_PID VS_PIF VS_RTR OPTIONS
  [ ! -e "${etc}" -a -f "${VS_CFG}" -a -O "${etc%/*}" ] && vs_user "ln -sf '${VS_CFG}' '${etc}'"
  vs_toolcheck 'mono'         '4.2'
  vs_toolcheck 'wget'         '1.17.9'
  vs_toolcheck 'screen'       '4.0'
  vs_toolcheck 'openssl' 
  export VS_BIN="VintagestoryServer.exe"
  local i="$(cat ${VS_PID} 2>/dev/null)"; local p="(${0##*/}|vs-.*)"; local err
  if [ ${i:-$$} -ne ${6:-0} ] ; then
    [ ${i:-$$} -ne $$ -a -n "$(pgrep -f "${p}" -F "${VS_PID}" 2>/dev/null)" ]  && vs_out -a "${0##*/} was temporarily locked by another VS command" 1
    printf "$$" > "${VS_PID}"                                                  || vs_out -a "Unexpected condition E#24 (user was not able to create pidfile '${VS_PID}')" 3
    [ "$(cat ${VS_PID} 2>/dev/null)" = "$$" ]                                  || vs_out -a "${0##*/} is temporarily locked by another VS command" 1
    [ -d "${VS_BAS}" ]                      || err=" dir ${VS_BAS}"
    [ -f "${VS_BAS}/${VS_BIN}" ]            || err="${err} bin ${VS_BIN}"
    getent passwd "${VS_OWN}"    >/dev/null || err="${err} owner ${VS_OWN}"    # need to check SW owner? set -- $(ls -ld "${VS_BAS}/${VS_BIN}" 2>/dev/null) && local owner="${3}"
    getent group  "${VS_OWN}"    >/dev/null || err="${err} group ${VS_OWN}"
    [ -n "${err}"  -a "${1}" != "setup" ]                                      && vs_out -a "VS environment of not found (missing${err}). Please run '${VS_UI1}' with proper privileges" 1
    [ -z "${_TAG}" -a "${1}" != "setup" ]                                      && vs_out -a "VS environment not properly set up. Please run '${VS_UI1}' with proper privileges" 1
    if [ -f "${VS_BAS}/${VS_BIN}" ] ; then
      local bv=$(vs_user "mono '${VS_BAS}/${VS_BIN}' -v | tr -dc '[:print:]'") # datapath workaround not needed in 1.5.1 ff.
      if [ "${bv}" != "${_VER}" -a "${1}" != "reinstall" ] ; then      
        vs_out   "Current ${VS_BIN} binary version ${bv} differs from ${_TYP} package tag ${_VER} from ${_DTS}" 1
        vs_abort "Version ${bv} might be installed manually. Please repair environment by running '${VS_UI2}' with proper privileges" 1
      fi
      if [ "${VS_TYP}" != 'vs_server' -a "$(id -u)" != "0" ] ; then
        vs_toolcheck 'mono-xmltool'                                            # indicates mono-complete (not needed for a server)
      fi
    fi
  fi
  export VS_DPN="${5:-${VS_DPN}}"
  [ -n "${1}" -a "${1}" != 'setup' ] && vs_set_workdir -n "${4}"
  export VS_VER="${3:-${_VER}}"
  export VS_TAG="${2:-${_TAG:-stable}}"
  [ -n "${1}" ]                           && vs_out "Vintage Story ${_VER:-none} ${0##*/} task '${1}' (world ${VS_SUB:-none})"
  [ -n "${1}" -a "${_TAG}" != 'stable' ]  && vs_out "Be aware that branch '${_TAG}' is not intended for productive use" 1
  return 0
}

#######################################
# Check command privileges
# Globals:
#   none
# Arguments:
#   $1 : privileged user
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_cmd_priv() {
  if ! [ "$(id -u)" = "0" -o "$(id -un)" = "${1:-vintagestory}" ] ; then
    vs_out -a "This command is only available for the users root and ${1:-vintagestory}." 1
  fi
}

#######################################
# Generate world seed (decimal number)
# Globals:
#   none
# Arguments:
#   $1 : -v VAR (opt. variable returns seed)
#   $2 : given seed (opt.)
#   $3 : world name (opt.)
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_gen_seed() {
  local var=''; local val=''; local wn=''
  case ${1} in
	-v) shift; var=${1}; shift ;;
    --) shift                  ;;
  esac
  if [ -z "${1}" ] ; then
    [ "${wn:=${2}}" = "New World" ] && wn="$(head -200 /dev/urandom)"
    val=$(echo "${wn}" | cksum | cut -f1 -d " " | cut -c-9 2>/dev/null)
  elif ! [ ${1} -le 2147483647 -a ${1} -ge -2147483648 ] ; then 
    val=$(echo "${1}"  | cksum | cut -f1 -d " " | cut -c-9 2>/dev/null)
  else
    val=${1}
  fi
  [ -n "${var}" ] && eval "${var}='${val}'" || echo "${val}"
}

#######################################
# Generate working directory (world folder)
# Globals:
#   VS_DAT : world data root folder
#   VS_LOG : logging root folder
#   VS_DPN : default port number
# Arguments:
#   $1 : working subdirectory
#   $2 : world seed (opt.)
#   $3 : world port (opt.)
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_gen_workdir() {
  local nd="${1}"; local wd="${1#new.$$.}"; local pn=${3:-${VS_DPN}}; local rn; local cf='serverconfig.json' 
  local wn="$(echo ${wd#w[0-9][0-9]-} | tr '-' ' ' | sed 's/\b./\u&/g')"
  vs_gen_seed -v rn "${2}" "${wn}"
  local jf="{\n \"ServerName\": \"VS\",\n \"Port\": ${pn},\n \"WorldConfig\": {\n  \"Seed\": \"${rn}\",\n  \"SaveFileLocation\": \"${VS_DAT}/${wd}/Saves/${wd}.vcdbs\",\n  \"WorldName\": \"${wn}\",\n },\n}\n"
  local md; for md in ${VS_DAT}/${nd} ${VS_DAT}/${nd}/Saves ${VS_LOG}/${wd} ; do
    if ! [ -d "${md}" ] ; then
      vs_user "mkdir -m 775 -p '${md}'                                                          2>/dev/null"   || vs_out -a "Creating new dir ${md} failed" 3
      vs_out "Created new dir: $(ls -ld ${md})" -1
    fi
  done
  [ -f "${VS_DAT}/${nd}/.info" ] || vs_user "printf 'STOPPED:${_VER}' >'${VS_DAT}/${nd}/.info'  2>/dev/null"   || vs_out -a "Unexpected condition E#25" 3
  [ -e "${VS_DAT}/${nd}/Logs"  ] || vs_user "ln -sf '${VS_LOG}/${wd}' '${VS_DAT}/${nd}/Logs'"                  || vs_out -a "Unexpected condition E#26" 3
  [ -f "${VS_DAT}/${nd}/${cf}" ] || vs_user "printf '${jf}' >'${VS_DAT}/${nd}/${cf}'            2>/dev/null"   || vs_out -a "Unexpected condition E#27" 3
}

#######################################
# Print last accessed world-id identified by input
# (matching either string part or prefix number)
# or overall when no input is provided.
# Non-matching input generates a new world-id.
# Globals:
#   VS_DAT : world data root folder
# Arguments:
#   $1 : -v VAR   (opt. variable returns id)
#   $2 : world id (opt. globbing)
# Returns:
#   0  : always OK
#######################################
vs_get_world_id() {
  local var=''; local val=''
  case ${1} in
	-v) shift; var=${1}; shift ;;
    --) shift                  ;;
  esac
  local i=$(echo "${1%.vcdbs}" | tr '[:upper:]' '[:lower:]' | tr '[:space:][:punct:]' '-' | tr -s '-'); i=${i%-}
  [ $(echo ${VS_DAT}/${i:--}* | wc -w) -gt 1 ]                    && vs_out -a "vs_get_world_id() input parameter '${1}' matches too many world ids" 3 # protect rule 2 from picking wrong world
  local nid; [ "${1#w[0-9][0-9]-}" != "${1}" -a ! -d ${VS_DAT}/${i%%-*}-* ] && nid="${i%%-*}"     # preserve valid (unused) input prefixes
  local wid; i="${i#w[0-9][0-9]-}"; 
  local count=101; for d in $(ls -tdx ${VS_DAT}/w[0-9][0-9]-*/.info 2>/dev/null) ; do 
    local base="${d%/.*}"; base="${base##*/}"; local num="${base%%-*}"; count=$((count+1))
    [  ${num#w}             -eq  ${1:-0}      ] 2>/dev/null       && wid="${base}" && break       # 1. numeric input: number matches to prefix
    [ "${base#${1:-w}}"     !=  "${base}"     ]                   && wid="${base}" && break       # 2. input without extension (starting with prefix): beginning string part matches (empty input too)
    [ "${base#w[0-9][0-9]-}" =  "${1}"        ]                   && wid="${base}" && break       # 3. input without extension and prefix: full name matches exactly
    [ "${base}"              =  "${1%.vcdbs}" ]                   && wid="${base}" && break       # 4. input with extension: combination of prefix and full name matches exactly
  done;
  [ -z "${wid:-${nid}}" ] && while [ -d ${VS_DAT}/w${count#1}-* ] ; do count=$((count-1)) ; done  # validate an unused prefix
  val="${wid:-${nid:-w${count#1}}-${i:-new-world}}"                                               # construct a (new) world name
  [ -n "${var}" ] && eval "${var}='${val}'" || echo "${val}"
}

#######################################
# Migrate world saves (rename, config)
# Precondition: stopped and backup done
# Globals:
#   VS_NUM : threshold (count) to keep backups
#   VS_DAT : world data root folder
#   VS_OWN : world data owner
# Arguments:
#   $1 : full world saves path to migrate/relocate
#   $2 : vcdbs name (opt. globbing, extension)
#   $3 : target subfolder name (opt.)
# Returns:
#   0  : Relocation OK (otherwise abort)
#   1  : Nothing found to relocate
#######################################
vs_migrate() {
  local saves="${1:-.}"; local vcdbs="${2%.vcdbs}"; local match
  local flags="-type f -group ${VS_OWN} -size +99k"
  local files="$(find ${saves} ${flags} -name "${vcdbs:-*}.vcdbs" | sort)"
  if [ -n "${files}" ] ; then
    echo "${files}" | grep -q "${saves}/Saves/${3}.vcdbs" && grep -q "${3}.vcdbs" "${saves}/serverconfig.json" 2>/dev/null && match="${saves}/Saves/${3}.vcdbs"
    echo "${files}" | while read line; do
      vcdbs="${line%.vcdbs}"; vcdbs="${vcdbs##*/}"; vcdbs="${vcdbs#default}"
      local wi; vs_get_world_id -v wi "${vcdbs:-new-world}.vcdbs"                                                             # world id (files, folders) prefixed in lowercase
      local wn="$(echo ${wi#w[0-9][0-9]-} | tr '-' ' ' | sed 's/\b./\u&/g')"                                                  # world name (title) without prefix in titlecase
      local wd="${3:-${wi}}"                                                                                                  # world data folder (e.g. given by parameter 3)
      local sd="${line%/Saves/*.vcdbs}"                                                                                       # source data folder (path)
      local td="${VS_DAT}/new.$$.${wd}"                                                                                       # target data folder (path)
      vs_out "Migrate world '${vcdbs}' found in '${saves}' to v${_VER} subfolder '${wd}' ..." -1
      local rn="$(grep '] Seed: ' "${sd}/Logs/server-main.txt" 2>/dev/null)"; rn="${rn#*Seed: }"                              # no issue if no seed logged
      vs_gen_seed -v rn "${rn}" "${wn}"
      vs_gen_workdir "new.$$.${wd}" "${rn}" &&  touch -cr "${line}" "${td}/.info"                                             # new dir including .info file (pointing to current version)
      [ ! -f "${line}" ] || vs_user "mv -f '${line}' '${td}/Saves/${wi}.vcdbs'                                   2>/dev/null" || vs_out -a "Unexpected condition E#x2 during file move" 3
      if [ -f "${sd}/serverconfig.json" -a "${line}" = "${match:-${line}}" ] ; then
        vs_user "cp -f ${sd}/.info '${td}/.old'                                                                  2>/dev/null" # no issue if no old .info copy
        vs_user "cp -f ${sd}/server*.json '${td}'                                                                2>/dev/null" # no issue if no json files
        vs_user "sed -i 's/\"[^\"]*.vcdbs\"/\"${VS_DAT}/${wi}/Saves/${wi}.vcdbs\"/' '${td}/serverconfig.json'    2>/dev/null" # no issue if no json files
        vs_user "sed -i 's/\"WorldName\":[^,]*,/\"WorldName\": \"${wn}\",/' '${td}/serverconfig.json'            2>/dev/null" # no issue if no json files
        vs_user "sed -i 's/\"Seed\":[^,]*,/\"Seed\": \"${rn}\",/' '${td}/serverconfig.json'                      2>/dev/null" # no issue if no json files
      fi
    done
    local retval=$?; [ ${retval} -le 1 ]                                                                                      || exit ${retval} # catch abort from piped 'while' (subshell)
    local wi; for wi in ${VS_DAT}/new.$$.w[0-9][0-9]-* ; do
      td="${VS_DAT}/${wi##*/new.$$.}"
      vs_out "Make migrated world folder '${td}' accessible" -1
      [ -d "${wi}" -a   -d "${td}" ] && mv -fT "${td}" "${VS_DAT}/replaced_$(date +%F_%T)_${wi##*/new.$$.}"                   # move the 'to-be-replaced' subfolder out of the way
      [ -d "${wi}" -a ! -d "${td}" ] && mv -fT "${wi}" "${td}"                                                                # relocate the post-migration target subfolder
      [ -d "${wi}" ] && vs_out "Moving ${wi} to ${td} failed. Manual cleanup required." 2
    done 
    ls -tdx ${VS_DAT}/replaced_*_w[0-9][0-9]-* 2>/dev/null | sed -e "1,${VS_NUM}d" | xargs rm -fr                             || vs_out "Housekeeping of replaced world folders failed." 0
  else
    vs_out "World '${vcdbs}' from '${saves}' is already removed" 1
  fi
}

#######################################
# Archive world saves
# Globals:
#   VS_OLD : threshold (days) to maintain world saves
#   VS_OWN : world data owner
# Arguments:
#   $1 : scope folders to scan
#   $2 : days in the past to consider
#   $3 : prune expression (opt.)
# Returns:
#   0  : Archiving OK (otherwise abort)
#   1  : Nothing found to archive
#######################################
vs_archive() {
  local scope="${1:-.}"; local days=${2:-${VS_OLD}};  local prune="${3}"
  local flags="-type f -group ${VS_OWN} -mtime -${days} -size +99k"
  vs_out "Archiving legacy world saves of the last ${days} days may take some minutes ..." -1
  local scan="$(find ${scope} ${flags} -path '*/Saves/*.vcdbs' -printf '%f:/%TY-%Tm-%Td_%.8TT_%kK:/%h\n' 2>/dev/null | grep -v ${prune} | sort -r)" 
  if [ -n "${scan}" ] ; then
    echo "${scan}" | while read line; do
      local world="${line%%.vcdbs*}"; local saves="${line##*:/}";
      vs_backup "${saves%/*}" && rm -fr ${saves%/*} 2>/dev/null
      vs_out "Archived '${saves%/*}'" -1
    done
    local retval=$?; [ ${retval} -le 1 ] || exit ${retval} # catch abort from piped 'while' (subshell)
  else
    vs_out "Nothing left to archive in this time window" 1
  fi
} 

#######################################
# Manually maintain legacy world saves
# Globals:
#   VS_OLD : threshold (days) to maintain world saves
#   VS_DAT : world data root folder
#   VS_OWN : world data owner
# Arguments:
#   $1 : days in the past to consider
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_maintain_legacy() {
  local days=${1:-${VS_OLD}};
  [ -f "${VS_DAT}/.mig" ] && return 0                                                                                                        # diff -q ${VS_BAS}/.tag ${VS_DAT}/.mig 2>&1
  echo; local reply; read -p "INTERACTION REQUIRED: Datapath of world saves seems to be changed. Do you want to maintain legacy saves (Y/n) " -r reply
  [ "${reply}" = 'n' -o "${reply}" = 'N' ] && return 0 || echo 
  local scope='/home /var /opt'
  local prune="${VS_DAT}\|${DATADIR}\|${HISTDIR}"                                                                                            # DATADIR relates to non root / client environment
  local flags="-type f -group ${VS_OWN} -mtime -${days} -size +99k"
  vs_out "Scanning data path '${VS_DAT}' for legacy world saves of the last ${days} days ..." -1
  find ${VS_DAT} ${flags} -path '*/Saves/*.vcdbs' -printf '%f:/%h\n' 2>/dev/null | while read line; do
    local vcdbs="${line%%.vcdbs*}"; local saves="${line##*:/}"
    [ -f "${saves%/*}/.info" ] && continue                                                                                                   # skip already migrated folders
    vs_backup -m "${saves%/*}"                                                                                                               # full backup excludes the legacy backup subfolder
    for bak in ${saves%/VintagestoryData/*}/backup/vs-server.*tar.gz ; do
      [ ! -f "${bak}" ] || vs_user "mv -f '${bak}' '${VS_DAT}/backup'   2>/dev/null"                                                         || vs_out -a "Unexpected condition E#x3" 3
    done
    local retval=$?; [ ${retval} -le 1 ]                                                                                                     || exit ${retval} # catch abort from piped 'while' (subshell)
    [ -d ${saves%/VintagestoryData/*}/backup ] && rm -fr ${saves%/VintagestoryData/*}/backup                                   2>/dev/null   # no issue when deleting the empty folder fails
    vs_migrate "${saves}" "${vcdbs}" && [ $(ls -d ${saves%/*}/*/*.vcdbs 2>/dev/null | wc -l) -eq 0 ] && rm -fr ${saves%/*}     2>/dev/null   # remove old the data folder
  done
  while true ; do
    num=0; vs_out "Scanning file system for legacy world saves of the last ${days} days may take some minutes ...\n"
    local scan="$(find ${scope} ${flags} -path '*/Saves/*.vcdbs' -printf '%f:/%TY-%Tm-%Td_%.8TT_%kK:/%h\n' 2>/dev/null | grep -v ${prune} | sort -r)" 
    echo "${scan}" | while [ -n "${scan}" ] && read line; do
      num=$((num+1)); local world="${line%%.vcdbs*}"; local saves="${line##*:/}"; local found="${line#*:/}"
      vs_out "${num}\t $(echo "${world}                             "|cut -c-30) [${found%%:/*}]\t in '${saves}'"
    done
    [ -z "${scan}" ] && break
    while true ; do
      echo; local reply; read -p "Please enter number to migrate this save to data location '${VS_DAT}' (leave with enter) " -r reply
      if [ ${reply} -le $(echo "${scan}" | wc -l) ]                         2>/dev/null ; then
        line="$(echo "${scan}" | sed "${reply}!d")"
        local vcdbs="${line%%.vcdbs*}"; local saves="${line##*:/}"
        vs_backup -m "${saves%/*}"                                                                                                           # full backup excludes the legacy backup subfolder
        for bak in ${saves%/VintagestoryData/*}/backup/vs-server.*tar.gz ; do
          [ ! -f "${bak}" ] || vs_user "mv -f '${bak}' '${VS_DAT}/backup'   2>/dev/null"                                                     || vs_out -a "Unexpected condition E#x3" 3
        done
        [ -d ${saves%/VintagestoryData/*}/backup ] && rm -fr ${saves%/VintagestoryData/*}/backup                               2>/dev/null   # no issue when deleting the empty folder fails
        vs_migrate "${saves}" "${vcdbs}" && [ $(ls -d ${saves%/*}/*/*.vcdbs 2>/dev/null | wc -l) -eq 0 ] && rm -fr ${saves%/*} 2>/dev/null   # remove old the data folder
      else
        [ -z "${reply}" ] && break
        vs_out "Only valid numbers allowed" 1
      fi
    done
    echo; local reply; read -p "Do you want to continue migrating legacy world saves (Y/n) " -r reply
    [ "${reply}" = 'n' -o "${reply}" = 'N' ] && break || echo
  done
  vs_user "cp -f '${VS_BAS}/.tag' '${VS_DAT}/.mig'"                                                                                          # persist info that migration is done
  if [ -n "${scan}" ] ; then
    echo; local reply; read -p "INTERACTION REQUIRED: Do you want to ARCHIVE the remaining legacy world saves (y/N) " -r reply
    [ "${reply}" = 'y' -o "${reply}" = 'Y' ] && vs_archive "${scope}" "${days}" "${prune}"; echo
  else
    vs_out "No legacy world saves found"
  fi
  return 0
}

#######################################
# Control restart under following conditions:
#   Restart world directly requested by restart commmand (no flag)
#   Restart world implicitly requested by recover command (-r flag)
#   Restart all needed after software change (-c flag and real change)
# Globals:
#   VS_BAS : SW install base dir
#   VS_DAT : world data root folder
#   VS_RTR : change restart tracker
# Arguments:
#   $1 : change | recover flag (opt.)
#   $2 : server instance (world id) 
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_restart() {
  case ${1} in
	-c) shift; local flag='-c'            ;;
	-r) shift; local flag='-r'            ;;
    --) shift                             ;;
  esac
  local world="${VS_DAT}/${1:-w[0-9][0-9]-*}"                          # world id not set in case of update/reinstall, default matches to all valid folders
  local changed="$(diff -q ${VS_BAS}/.tag ${VS_RTR} 2>&1)"             # real change means: version differs and restart has not done yet
  if [ -n "${changed}" -o "${flag}" != '-c' ] ; then
    local wd; for wd in ${world} ; do
      if [ -d "${wd}" ] ; then
        local run_info=$(cat "${wd}/.info" 2>/dev/null)
        vs_stop "${wd##*/}" "${run_info}"                              # all instances will be stopped
        [ "${flag}" = '-c' ]             && vs_backup  "${wd}"         # including migration in the case of a version change
        [ "${flag}" = '-r' ]             && vs_recover "${wd##*/}"     # including migration in the case of a backup recovery (means world id should be set) 
        [ "${run_info%:*}" = "STARTED" ] && vs_start   "${wd##*/}"     # decide to start per world id
      fi
    done
    vs_user "cp -f '${VS_BAS}/.tag' '${VS_RTR}'"                       # persist the information a restart sequence is performed (even if no server has been started)
  fi
  return 0
}

#######################################
# Main function to switch commands
# Globals:
#   VS_OWN : world data owner
#   VS_DAT : world data root folder
#   VS_SUB : server instance (world id)
#   VS_TST : test and trace flag
# Arguments:
#   $1  : command           (see usage)
#   $2+ : command parameter (opt.)
# Returns:
#   0   : OK
#   1-n : NOK (depends on command)
#######################################
main() {
  local keywords="$(printf "start\nstop\nrestart\nbackup\nrecover\nupdate\nreinstall\nrollback\nsetup\nstatus\ncommand\n")"
  if echo "${1}" | grep -qwF "${keywords}" ; then
    local task="${1}"; shift
  fi
  while getopts ":o:b:d:w:v:l:p:USPCRT" opt; do
      case ${opt} in
        o) local o="${OPTARG}"                                                  ;;
	    b) local b="${OPTARG}"                                                  ;;
        d) local d="${OPTARG}"                                                  ;;
        w) local w="${OPTARG}"                                                  ;;
        v) local v="${OPTARG}"                                                  ;;
        l) local l="${OPTARG}"                                                  ;;
        p) local p="${OPTARG}"                                                  ;;
        U) local t='unstable'                                                   ;;
        S) local t='stable'                                                     ;;
        P) local t='pre'                                                        ;;
        C) local s='vs_archive'                                                 ;;
        R) local s='vs_server'                                                  ;;
        T) VS_TST=1                                                             ;;
        :) vs_out "-${OPTARG} argument needed" 2; vs_usage -a $?                ;;
        *) vs_out "Invalid option -${OPTARG}"  2; vs_usage -a $?                ;;
      esac
  done
  shift $((OPTIND-1))
  if [ -z "${task}" ] ; then
    if echo "${1}" | grep -qwF "${keywords}" ; then
      local task="${1}"; shift
    else
      vs_out "Invalid keyword ${1}" 2; vs_usage -a $?	                  
    fi
  fi
  echo
  if [ -n "${VS_TST}" ] ; then
    vs_out "TEST MODE overrides some restrictions and enables console debug output. Use at own risk!\n" 1
    VS_LVL=-1; # set -x
  fi
  vs_set_env "${task}" "${t}" "${v}" "${w}" "${p}" "${l}"                        # check env and reset global parameters from cfg, otherwise abort
  case "${task}" in
    start)     vs_start      "${VS_SUB}"                                         ;;
    stop)      vs_stop       "${VS_SUB}"                                         ;;
    restart)   vs_restart    "${VS_SUB}"                                         ;;
    backup)    vs_cmd_priv   "${VS_OWN}" && vs_backup "${VS_DAT}/${VS_SUB}"      ;;
    recover)   vs_cmd_priv   "${VS_OWN}" && vs_restart -r "${VS_SUB}"            ;;
    update)    vs_cmd_priv   "${VS_OWN}" && vs_update    && vs_restart -c        ;;
    reinstall) vs_cmd_priv   "${VS_OWN}" && vs_reinstall && vs_restart -c        ;;
    rollback)  vs_cmd_priv   "${VS_OWN}" && vs_rollback  && vs_restart -c        ;;
    setup)     vs_cmd_priv   "${VS_OWN}" && vs_setup "${s}" "${o}" "${b}" "${d}" ;;
    status)    vs_get_status "${VS_SUB}"                                         ;;
    command)   vs_command    "${VS_SUB}" "$*"                                    ;; 
    *)         vs_usage                                                          ;;
  esac
  vs_out -a '' $?                                                                # standard exit without an additional message
}

main "$@"                                                                        # starting the main program

#######################################
# Potential topics for the next script versions 
#######################################
# TODO 01: Split start-stop from setup, maybe setup needs a split version of get_inst (set_inst vs get_inst)
# TODO 02: Replace host connect test with a test that does not rely on openssl
# TODO 03: Replace screen, tee script all output to syslog, make force stop (per kill)
# TODO 04: Write more documentation, better check of minimal requirements
# TODO 05: Maybe cleanup for old/failed legacy installs as option for an purge/uninstall task of the main/setup script (search /home for $bin)
# TODO 06: Consider installing a script link that resides in the user path / integrate init commands (or setting path for VS_OWN)
#
# TODO 08: Have a stopall and startall option to be prepared (scanning all world folders in the data path) and a list option to show the worlds
# TODO 09: Invoke trace with optional code to trace the funktion that raised the error code (includes error-code systematics)
#
# TODO 11: Better portability (instead printf feature) for the find in vs_archive, vs_maintain_legacy
# TODO 12: Implement a force stop / restart feature (to be used in status indeterminate after timeout and with confirmation)
# TODO 13: Change current restart logic in case of SW installation: no stop/start, instead notification (console/server) to recommend restart
# TODO 14: GenWorkdir should use a kind of serverconfig.json template
# TODO 15: Rename feature, Commandfile feature.

