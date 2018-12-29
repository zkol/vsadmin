#!/bin/sh
# /etc/init.d/vintagestory.sh
# version 1.5.1.8 2018-05-10 (YYYY-MM-DD)
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

# Changelog:
# 2018-03-28 Script version 1.5.1.5
#            Fixed: grep might recognize server-main.txt as binary file because of NUL bytes (gives an unexpected output)
#            Fixed: Remove archived online backup files from Backups folder and exclude Backups folder from full backup (would affect recovery from backup)
#            Tweak: Avoid regeneration of Playerdata from Savegame: Playerdata now included in Migration and Online Backup
#            Tweak: Message about resource conflict now includes the port number
#            Tweak: Host connection test simplified (dependency from openssl eliminated)
#            Tweak: Keep a (manually) linked configuration file during update/reinstall
# 2018-04-01 Script version 1.5.1.6
#            Fixed: setup of folder group permissions for a non-root user now considers the right folders
#            Fixed: link to editable configuation file sometimes messed up
#            Fixed: reinstall of same version triggers a world data migration (which was not necessary) 
#            Tweak: setup considers existing install to adjust/relocate/update (instead of always doing a full reinstall)
#            Tweak: restart on version change considers only started worlds for backup/migration (instead of all worlds) 
#            Tweak: weighted housekeeping threshold parameter (factor 1 for directories, factor 3 for files)
#            Tweak: added host connection parameters to the editable text configuration (centralizing the static constants) 
#            Tweak: adjusted timestamp format to long-iso (according to POSIX file date handling with ls)
#            Tweak: Try to sync installation metadata (on confirmation) before abort
#            Tweak: Reduced dependency from naming conventions: World folder suffix is now configurable (and can be disabled by -s -)
#            Refactoring: new functions `vs_idx_base`, `vs_idx_data`, `vs_set_cfg` to prepare script modularization
# 2018-04-02 Script version 1.5.1.7
#            Fixed: $HOME of software owner with desktop environment not properly set up
#            Fixed: Last data access not properly recognized without metadata
#            Fixed: Data replaced by recovery misinterpreted with suffix disabled
#            Fixed: Wrong (non-existing) world name not properly handled with suffix disabled
#            Fixed: Match pattern of the process signature is not backward compatible
# 2018-12-26 Script version 1.5.1.8
#            Fixed: Restart finishes with wrong result message
#            Tweak: Replaced the use of pgrep with posix compliant code
#            Tweak: Updated the VintageStory Public Keys
# 2018-12-27 Script version 1.6.0
#            Tweak: consider new location for game fonts


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
  local abort msg ret me
  case ${1} in
    -a) shift; abort=' - aborting'  ;;
    --) shift                       ;;
  esac
  msg="${1}"
  ret=${2:-0}
  me="${USER:=$(id -un)}"    # no console TS by printf "%(%Y-%m-%d %H:%M:%S)T ..." -1 (not posix compliant) 
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
  printf " -d DATADIR   Set custom full directory path for world data access.\n -s SUFFIX    Set custom static suffix as naming convention for world data.\n"
  printf " -C | -R      Consider complete|reduced package for installation.\n"
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
  local flag delta
  case ${1} in
	-q) shift; flag='-q'            ;;
    --) shift                       ;;
  esac
  delta=$(( $(echo "${1}00000"|tr -dc '[:digit:]'|cut -c-5) - $(echo "${2}00000"|tr -dc '[:digit:]'|cut -c-5) ))
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
  local reply=''
  vs_out "${1}" 1
  if [ -z "${VS_TST}" ] ; then
    echo; read -p "ABORT REQUESTED to avoid further issues. Continue anyway? (y/N) " -r reply
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
  local tool="${1}" version="${2}" pattern="${3:-${1} }"
  hash "${tool}" 2>/dev/null || vs_abort "Vintage Story requires '${tool}' but it's not installed" 3
  if [ -n "${version}" ] ; then
      vs_higher -q "$("${tool}" --version | grep -i "${pattern}")" "${version}" >/dev/null && vs_abort "Not found: ${tool} version > ${version}" 3
  fi
  return 0
}

#######################################
# Check running process instance
# Globals:
#   _CNT : count of matching process instances
#   _USR : effective username of the last matching process instance
#   _PID : process id of the last matching process instance
# Arguments:
#   $1 : process commandline (to be matched from the beginning)
# Returns:
#   0  : process is running
#   1  : process is not running
#######################################
vs_procheck() {
  local p
  unset _PID _USR _CNT 
  while read p; do
    _PID=${p#* }; _PID=${_PID%% *}
    _USR=$(ps -p ${_PID} -o user= 2>/dev/null) && _CNT=$((_CNT+1))
  done <<EOF
  "$(ps -eo stime=,pid=,args= | grep -E "[0-9] ${1}" | sort)"f
EOF
  [ ${_CNT:=0} -gt 0 ]
}

#######################################
# Get the current VS server instance run status
#   Derives the "to be" status from optional metadata (.info)
# Globals:
#   VS_CLR : C# runtime environment (interpreter)
#   VS_BAS : SW install base dir
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
  local var='' val=0 world inst run_info target_status _pid
  case ${1} in
    -v) shift; var=${1}; shift ;;
    --) shift                  ;;
  esac
  [ -z "${1}" ] && vs_out -a "vs_get_status() mandatory parameter missing: server instance (world id)" 3
  world="${1}";
  inst="${VS_CLR} ${VS_BAS}/${VS_BIN} --dataPath ${VS_DAT}/${world}"     # each instance is defined by its own data path
  ###
  run_info=$(cat "${VS_DAT}/${world}/.info"  2>/dev/null)
  target_status="${run_info%:*}"
  ###
  if [ ! -d "${VS_DAT}/${world}" ] ; then
    val=1; [ -z "${var}" ]   && vs_out "World ${world} not found" ${val} 
  elif ! vs_procheck "${inst}"; then
    val=1; [ -z "${var}" ]   && vs_out "${inst} (to be ${target_status:-STOPPED}) is not running" ${val} 
  else     # workaround: ensure that service is not about to terminate (server might be waiting for confirmation input after crash)
    vs_command -v _stat_msg "${world}" "stats"     || [ $? -eq 1 ]        || vs_out "Indeterminate ${inst} (to be ${target_status:-STOPPED})" 2 || return $?  
    sleep .5
    if ! vs_procheck "${inst}"; then
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
#   VS_CFG : server config file name
#   VS_OUT : server output file
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
  local key='' var='' val='' ret world cmd inst_log time timeout cfg
  case ${1} in
    -k) shift; key=$(printf "${1:-'] Handling'}\n] Unknown\n"); var='tmp'; shift ;;
    -v) shift; var="${1}"; shift                                                 ;;
    --) shift                                                                    ;;
  esac
  [ -z "${1}" ] && vs_out -a "vs_command() mandatory parameter missing: server instance (world id)" 3
  world="${1}"; shift       
  cmd="${*}"
  [ -d "${VS_DAT}/${world}" ] || vs_out -a "World ${world} not found" 2   
  cfg=$(grep -s '"SaveFileLocation":' "${VS_DAT}/${world}/${VS_CFG}" | cut -d: -f2)
  if [ -f "$(eval echo ${cfg%,})" -a -n "${cmd}" ] ; then             # check if the world refers to properly configured world
    inst_log="${VS_DAT}/${world}/${VS_OUT}"
    set -- $(wc -l "${inst_log}" 2>/dev/null) 0                       # set pre line count as $1
    if vs_user "screen -p 0 -S ${world} -X eval 'stuff \"/${cmd}\"\015' >/dev/null 2>&1" ; then
      time=0; timeout=450                                             # 450 * 0.1 = 45 sec
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
      [ -z "${var}" -a -z "${key}" ] && vs_out "Failed to execute command '${cmd}' (server maybe not running)" ${ret:=2} 
    fi
  else
    vs_out -a "Specify command for valid server instance. Use '${0##*/} command help' to query available commands" 2
  fi
  return ${ret:=0}
}

#######################################
# Stop VS server instance
#  Defines a "to be" status in the metadata (.info)
# Globals:
#   VS_BIN : VS binary name
#   VS_BAS : SW install base dir
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
  local world inst run_info target_status status
  [ -z "${1}" ] && vs_out -a "vs_stop() mandatory parameter missing: server instance (world id)" 3
  world="${1}" ; shift
  [ -d "${VS_DAT}/${world}" ] || vs_out -a "World ${world} not found" 3
  inst="${VS_BAS}/${VS_BIN} --dataPath ${VS_DAT}/${world}"                          # each instance is defined by its own data path
  ###
  run_info=$(cat "${VS_DAT}/${world}/.info" 2>/dev/null)
  target_status="${1:-STOPPED:${run_info#*:}}" 
  vs_idx_data "${VS_DAT}/${world}" "${target_status}"                               # update metadata
  vs_get_status -v status "${world}"
  ###
  case "${status}" in
    1)  vs_out "${inst} (to be ${target_status%:*}) was not running." -1
        [ "$(cat ${VS_PIF}.${VS_IPN} 2>/dev/null)" = "${world}" ] && rm -f "${VS_PIF}.${VS_IPN}"
        ;;
    *)  vs_out "Stopping ${inst} (to be ${target_status%:*}) ..." -1
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
#  Defines a "to be" status in the metadata (.info)
# Globals:
#   VS_CLR : C# runtime environment (interpreter)
#   VS_BAS : SW install base dir
#   VS_BIN : VS binary name
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
  local world other inst run_info target_status status
  [ -z "${1}" ] && vs_out -a "vs_start() mandatory parameter missing: server instance (world id)" 3
  world="${1}" ; shift 
  other=$(cat "${VS_PIF}.${VS_IPN}" 2>/dev/null)
  [ -n "${other}" -a "${other}" != "${world}" ] && vs_out -a "Other world ${other} previously allocated port ${VS_IPN}. Check and try again (maybe stop ${other} or reboot)" 2
  inst="${VS_BAS}/${VS_BIN} --dataPath ${VS_DAT}/${world}"                                     # each instance is defined by its own data path
  ###
  run_info=$(cat "${VS_DAT}/${world}/.info" 2>/dev/null)
  target_status="STARTED:${_VER}" 
  vs_get_status -v status "${world}"
  vs_idx_data "${VS_DAT}/${world}" "${target_status}"                                          # update metadata
  ###
  case "${status}" in
    0)  vs_out "${inst} (to be ${target_status%:*}) is already running." -1 ;;
    1)  vs_out "Starting ${inst} (to be ${target_status%:*}) ..." -1
        if [ -d "${VS_DAT}/${world}" ] ; then 
          [ "${run_info#*:}" != "${_VER}" ] && vs_out -a "World ${world} was previously saved with divergent version v${run_info#*:}. Please run backup first" 1
        else
          vs_set_workdir "${world}" || vs_out -a "Preparation and start of world data '${world}' canceled" 1
        fi
        vs_user "cp -f '${VS_BAS}/.tag' '${VS_RTR}'"                                           # allow to track needed restarts caused by SW updates, tag will not be deleted by reboot
        vs_user "printf '${world}' >'${VS_PIF}.${VS_IPN}'                2>/dev/null"          || vs_out -a "Unexpected condition E#14c" 3
        vs_user "screen -h 1024 -dmS ${world} ${VS_CLR} ${inst} ${OPTIONS}"                    || vs_out -a "Unexpected condition E#14" 3
        sleep 3                                                                                # allow server to initialize the logfiles and the directories in case of an initial startup
        vs_command -k '] Seed' "${world}" 'seed'
        if ! vs_get_status -v status "${world}"; then
          [ "$(cat ${VS_PIF}.${VS_IPN} 2>/dev/null)" = "${world}" ] && rm -f "${VS_PIF}.${VS_IPN}"
          vs_out "${inst} (to be ${target_status%:*}) could not be started." 2
        else
          vs_out "${inst} (to be ${target_status%:*}) is started." -1
          if [ -n "${VS_TST}" ]; then 
            vs_command -k '] Message' "${world}" "announce WARNING - ${inst} was started in TEST MODE" >/dev/null
          fi 
        fi
        ;;
    2)  vs_out "${inst} (to be ${target_status%:*}) is already running but not responding. Check an try again" 1 ;;
  esac
  return $?
}

#######################################
# Launch VS as daemon process
# Globals:
#   VS_BIN : VS binary name
#   VS_BAS : SW install base dir
#   VS_DAT : world data root folder
#   VS_RTR : change restart tracker
#   OPTIONS
# Arguments:
#   $1 : server instance (world id) 
#   $2 : target status (opt.) 
# Returns:
#   0  : started
#   1  : not responding
#   2  : not started
#######################################
vs_launch() {
  local c="mono ${VS_BAS}/${VS_BIN} --dataPath ${VS_DAT}/${world} ${OPTIONS}"
  local o="${0}.out"
  local p='/tmp/vs.command'                          #/var/run/vintagestory/w01.command
  local n=0
  [ -p "${p}" ] || mkfifo -m 660 "${p}"
  if [ -t 0 ] ; then
    echo "command - pid $$"                          # TODO command pidfile handling (remove) 
    setsid "$(readlink -f -- ${0})" "$@" </dev/null  >"${o}" 2>&1  &
  else
    echo "daemon launch - pid $$"                    # TODO daemon pidfile handling (create)
    cd / 
    exec nice -n ${n} ${c} "$@"          <"${p}"    >>"${o}" 2>&1
  fi
  echo '/stats' > "${p}"
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
  local reply='' world="${1}" bak io in
  [ -z "${1}" ] && vs_out -a "vs_recover() mandatory parameter missing: server instance (world id)" 3
  bak=$(ls -tdx ${VS_DAT}/backup/vs_${world}_*_v${VS_VER}*.tar.gz 2>/dev/null | head -n1)
  if [ -f "${bak}" ] ; then
    echo; read -p "CONFIRMATION REQUIRED: Recover world ${world} from ${bak} (Y/n) " -r reply
    [ "${reply}" = 'n' -o "${reply}" = 'N' ] && return 0 || echo 
    vs_out "Trying to recover ${world} from ${bak} ..." -1
    rm -fr /tmp/vs-recover.*  
    vs_user "mkdir -m 775 -p /tmp/vs-recover.$$                     2>/dev/null"  || vs_out -a "Unexpected condition E#19" 3
    vs_user "tar xzf ${bak} -C /tmp/vs-recover.$$                   2>/dev/null"  || vs_out -a "Unexpected condition E#20" 3
    ###
    io=$(cat "/tmp/vs-recover.$$/.info"                             2>/dev/null)
    in=$(cat "${VS_DAT}/${world}/.info"                             2>/dev/null)
    vs_idx_data /tmp/vs-recover.$$
    vs_user "printf '${in%:*}:${io#*:}' >'/tmp/vs-recover.$$/.info' 2>/dev/null"  || vs_out -a "Unexpected condition E#25" 3
    ###
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
#   VS_HIS : threshold (count) to keep backups
#   VS_DAT : world data root folder
#   VS_CFG : server config file name
#   VS_MIG : world data migration list
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
  local flag wd wn ri bk bn fl fn num
  case ${1} in
    -m) shift; flag='-m'                  ;;
    --) shift                             ;;
  esac
  num=$((${VS_HIS}*3))                                                                                            # 3 times the threshold for file based housekeeping use (compared to directory based)
  wd="${1}"; vs_get_world_id -v wn "${wd##*/}"
  [ -d "${VS_DAT}/${wn}" ] || vs_out -a "World ${wn} not found" 3
  ###
  ri=$(cat "${VS_DAT}/${wn}/.info" 2>/dev/null); ri="${ri#*:}"
  bk="$(date +%F_%H:%M)_v${ri:--legacy}"; bn="${bk}_${wn}.vcdbs"
  ###
  fl="Backups/${bn} ${VS_CFG} ${VS_MIG}"
  fn="${VS_DAT}/backup/vs_${wn}_${bk}"
  if [ -d "${VS_DAT}/backup" ] ; then
    if [ "${flag}" != '-m' ] && vs_get_status -v flag "${wn}" ; then
      vs_out "Start online world backup of ${wd} ..." -1
      ls -tdx ${wd}/Backups/*_${wn}.vcdbs 2>/dev/null          | sed -e "1,${num}d" | xargs rm -f                 || vs_out "Housekeeping of online backup databases failed" 2
      ls -tdx ${VS_DAT}/backup/vs_${wn}_*_o.tar.gz 2>/dev/null | sed -e "1,${num}d" | xargs rm -f                 || vs_out "Housekeeping of online backup archives failed" 2
      vs_command -k '] Backup' "${wn}" "genbackup ${bn}" && vs_user "chmod -f g+w ${wd}/Backups/${bn}"
      [ -f "${wd}/Backups/${bn}" ]                                                                                || vs_out -a "Online backup not available" 3
      vs_user "tar czf '${fn}_o.tar.gz' --transform 's+Backups/${bk}_+Saves/+g' -C ${wd} ${fl}"                   || vs_out -a "Online backup failed" 3
      rm -f "${wd}/Backups/${bn}"                                                                                 # remove the archived backup file
      vs_out "Created backup ${fn}_o.tar.gz (online)" 0
    else
      vs_out "Start full data backup of ${wd} ..." -1
      ls -tdx ${VS_DAT}/backup/vs_${wn}_*_f.tar.gz 2>/dev/null | sed -e "1,${num}d" | xargs rm -f                 || vs_out "Housekeeping of old full backup archives failed" 2
      vs_user "tar czf '${fn}_f.tar.gz' -C ${wd} . --exclude=backup --exclude=Backups"                            || vs_out -a "Full backup failed" 3
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
#   SR_HOST: release api hostname:port 
#   SR_PKEY: release api pubkey sha256 digest
#   SP_HOST: package repo hostname:port 
#   SP_PKEY: package repo pubkey sha256 digest
# Arguments:
#   $1 : -v VAR (opt. variable returns connectstring)
#   S2 : package | release
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_host_connect() {
  local var='' val='' err='' ret=-1 host port sha
  case ${1} in
    -v) shift; var=${1}; shift ;;
    --) shift                  ;;
  esac
  case "${1}" in
    package) sha="${SP_PKEY%=}="; host=${SP_HOST%:*}; port=${SP_HOST#${host}}; port=${port#:} ;;
    release) sha="${SR_PKEY%=}="; host=${SR_HOST%:*}; port=${SR_HOST#${host}}; port=${port#:} ;;
    *)       vs_out -a "Function vs_host_connect: Invalid call with parameter '${1}' (E#16)" 3 ;; 
  esac
  val="--pinnedpubkey=sha256//${sha} --https-only https://${host}:${port:-443}"
  err=$(wget -q --spider ${val}/robots.txt 2>&1); ret=$?
  if [ ${ret} -eq 0 -o ${ret} -eq 8 ]; then 
    [ -n "${var}" ] && eval "${var}='${val}'" || echo "${val}"
  else
    vs_out "Connection check (wget) returned code ${ret} from host '${host}:${port}'. ${err}" 2
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
  local target="${1}" IFS="$(printf "\n\b")" filename lowername
  for i in $(find "${target}/assets"); do 
    filename="${i##*/}"
    lowername="$(echo ${filename} | tr '[:upper:]' '[:lower:]')"
    if [ "${filename}" != "${lowername}" ] ; then                                            # check if there is a asset file that is not lowercase 
      vs_out "Asset '${filename}' is not lowercase" -1                                       # complain
      [ -e "${i%/*}/${lowername}" ] || vs_user "ln -sf '${filename}' '${i%/*}/${lowername}'" # create a lowercase symlink to fix it
    fi 
  done
}

#######################################
# Collect version metadata (write .tag)
# Globals:
#   VS_CLR : C# runtime environment (interpreter)
#   VS_BIN : VS binary name
#   VS_DTL : VS desktop launcher
# Arguments:
#   $1 : SW install base dir
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_idx_base() {
  local con slist bf bd bv bb nt
  vs_host_connect -v con 'release'
  slist="$(wget ${con}/stable.json -q -O -)"
  for bf in $(ls -tdx ${1}/${VS_BIN} 2>/dev/null) ; do
    bd="${bf%/*}"
    nt=$(ls -tdl "${bf}" | cut -d ' ' -f 6,7 | tr '[:space:]' '_'); nt=${nt%_} # like "date +%F_%H:%M" if TIME_TYPE=long-iso works, otherwise like "date +%b_%d"
    bv=$(${VS_CLR} ${bf} -v | tr -dc '[:print:]')
    bb=$(echo "${slist}" | grep -c "${bv}"); 
    [ "${bb}" -gt 0 ]        && bb='stable'     || bb='unstable'   
    [ -f "${bd}/${VS_DTL}" ] && ba='vs_archive' || ba='vs_server'
    vs_out "$(printf 'VS_IDX basedir="%s" branch="%s" type="%s" version="%s" time="%s"' "${bd}" "${bb}" "${ba}" "${bv}" "${nt}")" -1
    vs_user "echo ${bb} ${ba}_${bv} ${nt} > ${bd}/.tag" || vs_abort "Metadata creation failed. Please repair environment by running '${VS_UI2}' with proper privileges" 1
  done
  return 0
}

#######################################
# Collect instance metadata (write .info)
# Globals:
#   VS_CLR : C# runtime environment (interpreter)
#   VS_BAS : SW install base dir
#   VS_BIN : VS binary name
#   VS_CFG : server config file name
#   VS_OUT : server output file
# Arguments:
#   $1 : world data folder (opt. with wildcard)
#   $2 : full status info to be set (opt.)
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_idx_data() {
  local form wi wd wn sf cp cs mi lv ls lp lr
  for wd in $(ls -tdx ${1} 2>/dev/null) ; do
    wi="${wd}/${VS_CFG}"
    mi="${wd}/.info"
    if [ -f "${wi}" ] ; then
      sf=$(grep -s '"SaveFileLocation":' "${wi}" | cut -d: -f2); sf=$(eval echo ${sf%,})
      wn=$(grep -s '"WorldName":'        "${wi}" | cut -d: -f2); wn=$(eval echo ${wn%,})
      cs=$(grep -s '"Seed":'             "${wi}" | cut -d: -f2); cs=$(eval echo ${cs%,})
      cp=$(grep -s '"Port":'             "${wi}" | cut -d: -f2); cp=$(eval echo ${cp%,})
      if [ -f "${sf}" ] ; then
        ls=$(cat "${wd}/${VS_OUT}" 2>/dev/null | tr -d '\000' | grep '] Seed: '                ); ls=${ls#*] Seed: }
        lp=$(cat "${wd}/${VS_OUT}" 2>/dev/null | tr -d '\000' | grep 'Server running on Port ' ); lp=${lp#*Server running on Port }
        lv=$(cat "${wd}/${VS_OUT}" 2>/dev/null | tr -d '\000' | grep '] Server v'              ); lv=${lv#*] Server v}
        lr=$(cat "${wd}/${VS_OUT}" 2>/dev/null | tr -d '\000' | grep '] Stopped the server'    ); lr=${lr:+STOPPED}
        if vs_procheck "${VS_CLR} ${VS_BAS}/${VS_BIN} --dataPath ${wd}"; then
          [ -n "${lr}" ] && vs_out "VS server ${wd} found STARTED (logged as stopped in ${VS_OUT} - maybe stop has failed)"
          lr='STARTED'
        elif [ -z "${lr}" -a -n "${ls}" ] ; then
          vs_out "VS server ${wd} not found STARTED (previously logged as started in ${VS_OUT} - maybe crashed)"
          lr='STARTED'
        else
          lr='STOPPED'
        fi
        if [ -n "${ls}" -a -n "${cs}" -a "${cs}" != "${ls}" ] ; then
          vs_out "Syncing configuration ${wi} with seed ${ls} (as previously logged in ${VS_OUT})"
          vs_set_cfg "${wd}" -sn "${ls}"
        fi
        if [ -n "${lp%%!*}" -a -n "${cp}" -a "${cp}" != "${lp%%!*}" ] ; then
          vs_out "Configuration ${wi} has port ${cp} (differs from port ${lp%%!*} previously logged in ${VS_OUT})"
        fi
        form='VS IDX datadir="%s" subdir="%s" worldsave="%s"\nJSON seed="%s" port="%s" worldname="%s"\nLOG  seed="%s" port="%s" version="%s" stop="%s"' 
        vs_out "$(printf "${form}" "${wd%/*}" "${wd##*/}" "${sf##*/}" "${cs}" "${cp}" "${wn}" "${ls}" "${lp%%!*}" "${lv%%,*}" "${lr}")" -1
        if [ -n "${2}" ] ; then
          vs_user "echo ${2} > ${wd}/.info" || vs_out "Metadata creation in ${wd} failed." 2
          touch "${wd}" 2>/dev/null   # set timestamp of status change
          touch "${wi}" 2>/dev/null   # set timestamp of status change
        else
          vs_user "echo ${lr}:${lv%%,*} > ${wd}/.info" || vs_out "Metadata creation in ${wd} failed." 2
          touch -cr "${sf}" "${wd}" 2>/dev/null   # set timestamp of last world usage
          touch -cr "${sf}" "${wi}" 2>/dev/null   # set timestamp of last world usage
        fi
      fi
    fi
  done
}

#######################################
# Set parameters in server config 
# Globals:
#   VS_CFG : server config file name
# Arguments:
#   $1   : world data subdir (server config location)
#   $2-5 : -sf SAVEFILE   (opt. parameter)
#   $2-5 : -wn WORLDNAME  (opt. parameter)
#   $2-5 : -sn SEEDNUMBER (opt. parameter)
#   $2-5 : -pn PORTNUMBER (opt. parameter)
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_set_cfg() {
  local cfg="${1}/${VS_CFG}" sf wn sn pn
  while [ $# -gt 1 ] ; do
    case ${2} in
      -sf) shift; sf="${2}"; shift ;;
      -wn) shift; wn="${2}"; shift ;;
      -sn) shift; sn="${2}"; shift ;;
      -pn) shift; pn="${2}"; shift ;;
      *)   vs_out "Wrong parameter '${2}'" 1; shift ;;
    esac
  done
  if [ -f "${cfg}" ] ; then      # no issue if not writable
    [ -n "${sf}" ] && vs_user "sed -i 's/\"[^\"]*.vcdbs\"/\"${sf}\"/'                     '${cfg}'  2>/dev/null" 
    [ -n "${wn}" ] && vs_user "sed -i 's/\"WorldName\":[^,]*,/\"WorldName\": \"${wn}\",/' '${cfg}'  2>/dev/null"
    [ -n "${sn}" ] && vs_user "sed -i 's/\"Seed\":[^,]*,/\"Seed\": \"${sn}\",/'           '${cfg}'  2>/dev/null"
    [ -n "${pn}" ] && vs_user "sed -i 's/\"Port\":[^,]*,/\"Port\": \"${pn}\",/'           '${cfg}'  2>/dev/null"
  fi
  return 0
}

#######################################
# Load, verify, install VS archive
# Globals:
#   VS_HIS : threshold (count) to keep backups
# Arguments:
#   $1 : stable | unstable (branch)
#   $2 : archive name
#   $3 : target path
# Returns:
#   0  : always OK (otherwise abort)
#   2  : archive corrupted
#######################################
vs_tar_install() {
  local branch="${1}" archive="${2}" target="${3}" ostamp="$(date +%F_%H:%M)" connect                                             
  vs_out "Try downloading files/${branch}/${archive}.tar.gz"
  [ "${branch}" = 'pre' -o "${branch}" = 'unstable' ]                                                                          && vs_out "Be aware that branch '${branch}' is not intended for productive use" 1
  vs_host_connect -v connect 'package'                                                                                         # otherwise abort
  wget ${connect}/files/${branch}/${archive}.tar.gz -q -c -O "/tmp/${archive}.tar.gz"
  file "/tmp/${archive}.tar.gz" | grep -q 'HTML'                                                                               && vs_out -a "Remote package ${archive} not found" 3
  file "/tmp/${archive}.tar.gz" | grep -q 'gzip'                                                                               || vs_out -a "Dowloaded package ${archive} is no gzip format" 3
  set -- $(wget ${connect}/files/${branch}/${archive}.md5 -q -O -)
  set -- "${1}" $(md5sum "/tmp/${archive}.tar.gz")
  [ "${branch}" = 'pre' -a -z "${1}" ] && vs_out "No checksum for ${archive} available. Be aware that testing on productive machines is always risky" 1
  if [ "${branch}" = 'pre' -a -z "${1}" ] || [ "${1}" = "${2}" ] ; then
    rm -fr ${target}.new.* 
    vs_user "mkdir -m 775 -p ${target}.new.$$      2>/dev/null"                                                                || vs_out -a "Unexpected condition E#19" 3
    vs_user "tar -xzf /tmp/${archive}.tar.gz -C ${target}.new.$$"                                                              || vs_out -a "Unexpected condition E#20" 3
    mv -f ${target}.new.$$/vintagestory/* "${target}.new.$$" 2>/dev/null && rm -fr ${target}.new.$$/vintagestory               # try might fail
    vs_user "cd ${target}.new.$$; chmod -fR -x+X .; chmod -f ug+x *.exe *.sh"
    rm -rf "/tmp/${archive}.tar.gz" "/tmp/${archive}.tar.gz.corrupt"
    vs_idx_base "${target}.new.$$"                                                                                             # parse installation and create installation tag
    vs_fix_inst "${target}.new.$$"
    if [ -d "${target}" ] ; then
      ls -tdx ${target}.bak_* 2>/dev/null | sed -e "1,${VS_HIS}d" | xargs rm -fr                                               || vs_out "Housekeeping of old SW backups failed" 2
      [ -L "${target}/.etc" ] && vs_user "cp -Pf ${target}/.etc ${target}.new.$$/.etc"
      [ -f "${target}/.tag" ] && vs_user "cp -Pf ${target}/.tag ${target}.new.$$/.old"
      vs_user "echo '${ostamp}' >> ${target}.new.$$/.old"
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
# Arguments:
#   none
# Returns:
#   0  : always OK (otherwise abort)
#   1  : rollback not possible
#######################################
vs_rollback() {
  local target="${VS_BAS}" reply='' nstamp="$(date +%F_%H:%M)" ostamp bak
  set -- $(cat "${target}/.old" 2>/dev/null); ostamp="${4:-*}"                                                                 # read rollback parameters from .old file 
  bak=$(ls -tdx ${target}.bak_${ostamp} 2>/dev/null | head -n1)
  if [ -d "${bak}" ] ; then 
    echo; read -p "CONFIRMATION REQUIRED: Rollback Vintage Story v${_VER} to previous ${1:-version} ${2} (Y/n) " -r reply
    [ "${reply}" = 'n' -o "${reply}" = 'N' ] && return 0 || echo 
    vs_out "Trying to rollback Vintage Story from current v${_VER} to previous ${1:-version} ${2} ..." -1 
    [ -d "${target}" ] && mv -fT "${target}" "${target}.rollbak_${nstamp}"
    mv -fT "${bak}" "${target}"                                                                                                || vs_out -a "Unexpected condition E#21" 3
    rm -fr "${target}.rollbak_${nstamp}" 
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
  local branch="${1:-${VS_TAG}}" reply='' newversion="${VS_VER}" connect stable archive
  if [ "${newversion}" = "${_VER}" ] ; then
    vs_host_connect -v connect 'release'                        # otherwise abort
    newversion="$(wget ${connect}/latest${branch}.txt -q -O -)" || vs_out -a "Cannot get 'latest${branch}.txt' for version info" 3
    if [ "${branch}" != 'stable' ] ; then
      stable="$(wget ${connect}/lateststable.txt -q -O -)"      || vs_out -a "Cannot get 'lateststable.txt' for comparison' (E#22)" 3
      if vs_higher -q ${newversion} ${stable} ; then
        branch='stable'
        newversion="${stable}"
      fi
    fi
  fi
  vs_out "Considering latest version v${newversion} belonging to the '${branch}' branch" -1
  if vs_higher -q ${_VER} ${newversion} ; then
    archive="${2:-${VS_TYP}}_${newversion}"
    echo; read -p "CONFIRMATION REQUIRED: Update Vintage Story ${_TAG} v${_VER} to newer ${branch} v${newversion} (Y/n) " -r reply
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
  local version="${VS_VER}" connect archive
  vs_host_connect -v connect 'release'                       # otherwise abort
  if [ -z "${version}" ] ; then
    version="$(wget ${connect}/latest${VS_TAG}.txt -q -O -)" || vs_out -a "Cannot get version info for branch '${VS_TAG}'" 3
  fi
  archive="${VS_TYP}_${version}"
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
#   VS_HIS : threshold (count) to keep backups
#   VS_OLD : threshold (days) to maintain world saves
#   VS_DPN : default port number
#   VS_PRE : world data naming prefix
#   VS_TAG : target branch stable | unstable
#   VS_TYP : target type vs_server | vs_archive
#   VS_OWN : owner of world data (server process)
#   VS_BAS : SW install base dir
#   VS_DAT : world data root folder
#   VS_LOG : logging root folder
#   VS_DTL : VS desktop launcher
#   VS_UI1 : setup usage info
# Arguments:
#   $1 :  target type vs_server | vs_archive
#   $2 :  owner of world data (server process)
#   $3 :  SW install base dir
#   $4 :  world data root folder
#   $5 :  world data naming prefix
# Returns:
#   0  : OK
#   1  : canceled
# Redefines:
#   VS_ETC : editable text configuration file
#######################################
vs_setup() {
  local reply='' path_list md local_bin headless
  VS_TYP=${1:-${VS_TYP}}; VS_OWN=${2:-${VS_OWN}}; VS_BAS=${3:-${VS_BAS}}; VS_DAT=${4:-${VS_DAT}}; VS_PRE=${5:-${VS_PRE}}
  vs_read_env "${VS_ETC}" HISTDIR DATADIR MENUDIR FONTDIR DESKDIR HOME
  vs_out "CAUTION: Please ensure that no Vintage Story is running on this machine before setup confirmation." 1
  echo; read -p "CONFIRMATION REQUIRED: Basic setup: package='${VS_TYP}' branch='${VS_TAG}' version='${VS_VER}' owner='${VS_OWN}' basedir='${VS_BAS}' datadir='${VS_DAT}' (y/N) " -r reply
  echo
  if [ "${reply}" = 'y' -o "${reply}" = 'Y' ] ; then
    path_list="${VS_BAS%/*} ${VS_DAT} ${VS_DAT}/backup ${VS_LOG}"
    if hash xdg-user-dir 2>/dev/null && ps -eo args= | grep -qE "(kde|gnome|lxde|xfce|mint|unity|fluxbox|openbox)" ; then
      path_list="${path_list} ${FONTDIR} ${DESKDIR} ${MENUDIR}"
    else
      headless="yes"
    fi
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
      for md in ${HOME} ${path_list} ; do
        if [ -d "${md}" ] ; then
          chmod -fR g+w "${md}"                     2>/dev/null      || vs_out -a "Path ${md} privileges adjustment failed" 3
          chown -fR ${VS_OWN}:${VS_OWN} "${md}"     2>/dev/null      || vs_out -a "Path '${md}' ownership adjustment failed" 3
          vs_out "Adjusted path: $(ls -ld ${md})" -1
        else
          mkdir -m 775 -p "${md}"                   2>/dev/null      || vs_out -a "Path ${md} creation failed" 3
          chown "${VS_OWN}:${VS_OWN}" -fR "${md}"   2>/dev/null      || vs_out -a "Path '${md}' privileges setup failed" 3
          vs_out "Setup new path: $(ls -ld ${md})"
        fi
      done
    else
      if ! getent group "${VS_OWN}"    >/dev/null 2>&1 ; then
        vs_out -a "User '${VS_OWN}' cannot setup missing group '${VS_OWN}'" 3
      elif ! id -nG | grep "${VS_OWN}" >/dev/null 2>&1 ; then
        vs_out -a "User '${VS_OWN}' cannot use existing group '${VS_OWN}'" 3
      fi
      for md in ${path_list} ; do
        if ! [ -d "${md}" ] ; then
          mkdir -m 775 -p "${md}"                   2>/dev/null      || vs_out -a "Path ${md} creation failed (try su)" 3
          chgrp "${VS_OWN}" -fR "${md}"             2>/dev/null      || vs_out -a "Path '${md}' group setup failed (try su)" 3           # attention: avoid links belonging to root!
          vs_out "Setup new path: $(ls -ld ${md})"
        else
          chmod -fR g+w "${md}"                     2>/dev/null      || vs_out -a "Path ${md} privileges adjustment failed (try su)" 3
          chgrp "${VS_OWN}" -fR "${md}"             2>/dev/null      || vs_out -a "Path '${md}' group setup failed (try su)" 3           # attention: avoid links belonging to root!
          vs_out "Adjusted path: $(ls -ld ${md})" -1
        fi
      done
      VS_ETC="/home/${VS_OWN}/.vintagestory"                         # VS_ETC is defined by setup and link is placed to persist this definition
    fi
    vs_write_env VS_HIS VS_OLD VS_DPN VS_PRE VS_TAG VS_TYP VS_OWN VS_BAS VS_DAT VS_LOG OPTIONS HISTDIR DATADIR SR_HOST SR_PKEY SP_HOST SP_PKEY
    [ -e "${VS_BAS%/*}/data" ] || vs_user "ln -sf '${VS_DAT}' '${VS_BAS%/*}/data'"
    [ -e "${VS_BAS%/*}/log" ]  || vs_user "ln -sf '${VS_LOG}' '${VS_BAS%/*}/log'"
    [ -e "${VS_DAT}/log" ]     || vs_user "ln -sf '${VS_LOG}' '${VS_DAT}/log'"
    vs_out "Basic environment setup finished" 0
    vs_idx_data "${VS_DAT}/*"
    local_bin="$(readlink -f -- "${0%/*}/${VS_BIN}")"
    setup_bin="$(readlink -f -- "${VS_BAS}/${VS_BIN}")"
    if [ -f "${local_bin}" -a "${local_bin}" = "${setup_bin}" ] ; then
        vs_adjust_workdir "${VS_BAS}"
    elif [ -f "${local_bin}" -a ! -f "${setup_bin}" ] ; then
      echo; read -p "CONFIRMATION REQUIRED: Do you want to move directory ${local_bin%/*} to ${VS_BAS} instead of a complete reinstall (y/N) " -r reply; echo
      if [ "${reply}" = 'y' -o "${reply}" = 'Y' ] ; then
        mv -f "${local_bin%/*}" "${VS_BAS}"
        vs_adjust_workdir "${VS_BAS}"
      else
        vs_reinstall
      fi
    elif [ -f "${setup_bin}" ] ; then
      vs_update
    else
      vs_reinstall
    fi
    vs_restart -c  && vs_maintain_legacy ${VS_OLD}
    if [ -f "${VS_BAS}/${VS_DTL}" -a -z "${headless}" ] ; then
      vs_write_env VS_HIS VS_OLD VS_DPN VS_PRE VS_TAG VS_TYP VS_OWN VS_BAS VS_DAT VS_LOG OPTIONS HISTDIR DATADIR MENUDIR FONTDIR DESKDIR SR_HOST SR_PKEY SP_HOST SP_PKEY
      for i in $(find "${VS_BAS}/${VS_FNT}" -name *.ttf -type f); do 
        [ -f "${FONTDIR}/${i##*/}" ] || ln -sf "${i}" "${FONTDIR}"
      done
      if [ -f "${MENUDIR}/${VS_DTL}" ] ; then
        vs_out "Recreate launcher icons"; reply='y'
      else
        echo; read -p "CONFIRMATION REQUIRED: Do you want to create launcher icons (Y/n) " -r reply; echo
      fi
      if [ "${reply}" != 'n' -a "${reply}" != '-N' ] ; then
        export APPDATA="${VS_BAS%/*}"; export INST_DIR="${VS_BAS##*/}"; export VERSION=""  # fit in existing desktop template
        rm -f "${MENUDIR}/${VS_DTL}" && vs_user "envsubst < '${VS_BAS}/${VS_DTL}' > '${MENUDIR}/${VS_DTL}' && chmod -f ugo+x '${MENUDIR}/${VS_DTL}'";
        [ -d "${DESKDIR}" ] && vs_user "ln -sf '${MENUDIR}/${VS_DTL}' '${DESKDIR}/${VS_DTL}'"
      fi
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
#   VS_CFG : server config file name
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
  local reply='' port
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
  port=$(grep -s '"Port":' "${VS_DAT}/${VS_SUB}/${VS_CFG}" | tr -dc '[:digit:]')
  export VS_IPN=${port:-${VS_DPN}}
  [ -d "${VS_DAT}/${VS_SUB}" ]
}

#######################################
# Read vintagestory ENV (from defaults or text config)
# Globals:
#   VS_ETC : editable text configuration file
# Arguments:
#   $1   : config file path  
#   $2-n : list of variable names
# Returns:
#   0  : always OK (otherwise abort)
# Redefines:
#   VS_ETC : editable configuration file
#   _TAG   : actual branch stable | unstable
#   _TYP   : actual type vs_server | vs_archive
#   _VER   : actual version (install)
#   _DTS   : actual install timestamp
#   sets TIME_STYLE to long-iso
#######################################
vs_read_env() {
  export TIME_STYLE=long-iso
  VS_ETC="$(readlink -f -- "${1}")"; shift                      # VS_ETC is the link destination (initially taken from the very first call)  
  [ ! -e "${VS_ETC}" -o -L "${VS_ETC}" ] && vs_read_var VS_ETC  # but maybe neither link nor destination exists, yet (so take default)
  for var in "$@"; do
    vs_read_var "${var}" "${VS_ETC}"
  done
  set -- $(cat "${VS_BAS}/.tag" 2>/dev/null)
  _TAG="${1}"; 
  _TYP="${2%_*}"; _VER="${2##*_}"
  _DTS="${3}"
}

#######################################
# Write vintagestory ENV to filesystem
# Globals:
#   VS_ETC : editable text configuration file
# Arguments:
#   $1-n : list of variable names
# Returns:
#   0  : always OK (otherwise abort)
# Redefines:
#   VS_ETC : editable text configuration file
#######################################
vs_write_env() {
  local etc
  [ -z "${VS_ETC}" ] && vs_read_var VS_ETC                      # VS_ETC is either /var/opt/vintagestory (default) $HOME/.vintagestory (setup)
  if [ -w "${VS_ETC}" -o ! -e "${VS_ETC}" ] ; then              # must be either writable or not exist during setup
    echo "# VS config setup $(date '+%F %H:%M')" >"${VS_ETC}"
    for var in "$@"; do
      [ -z "$(eval echo "\$${var}")" ] && vs_read_var "${var}" "${VS_ETC}"
      echo "${var}='$(eval echo "\$${var}")'" >>"${VS_ETC}"
    done
    etc="$(readlink -f -- "${0%/*}")/.etc"                      # etc is the "physical" location of the symbolic link file
    [ -O "${etc%/*}" ] && vs_user "ln -sf '${VS_ETC}' '${etc}'" # persist VS_ETC redefinition
  else
    vs_out "No privileges to write configuration file ${VS_ETC}" 1
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
  local p1="^${1}=['\"]*" p2='[-+/_.,: [:alnum:]]+' val home
  val="$(grep -m1 -Eo "${p1}${p2}" "${2}" 2>/dev/null | grep -m1 -Eo "${p2}" | tail -n1)"
  home=$(eval echo "~${VS_OWN}")
  if [ -z "${val#*=}" ] ; then   # use predefined default values
    case ${1} in
      VS_HIS)      val=2                                             ;;
      VS_OLD)      val=180                                           ;;
      VS_DPN)      val=42420                                         ;;
      VS_PRE)      val='w'                                           ;; # val='-' to disable
      VS_TAG)      val='stable'                                      ;;
      VS_TYP)      val='vs_server'                                   ;;
      VS_OWN)      val='vintagestory'                                ;;
      VS_ETC)      val='/etc/opt/vintagestory'                       ;;
      VS_BAS)      val='/opt/vintagestory/game'                      ;;
      VS_DAT)      val='/var/opt/vintagestory'                       ;;
      VS_LOG)      val='/var/log/vintagestory'                       ;;
      VS_PID)      val='/var/lock/vs-command.pid'                    ;;
      VS_PIF)      val='/var/lock/vs-port.info'                      ;;
      VS_RTR)      val='/var/tmp/vs-command.tag'                     ;;
      VS_BIN)      val='VintagestoryServer.exe'                      ;;
      VS_DTL)      val='Vintagestory.desktop'                        ;;
      VS_FNT)      val='assets/game/fonts'                           ;; # previously: assets/fonts
      VS_CFG)      val='serverconfig.json'                           ;;
      VS_MIG)      val='servermagicnumbers.json Playerdata'          ;;
      VS_OUT)      val='Logs/server-main.txt'                        ;;
      VS_CLR)      val='mono'                                        ;;
      SP_HOST)     val='account.vintagestory.at:443'                 ;;
      SP_PKEY)     val='HFZBBiTM/vicQlTpQQR1aJgJZcITsBMJfDqHhByVQJ0' ;;
      SR_HOST)     val='api.vintagestory.at:443'                     ;;
      SR_PKEY)     val='HFZBBiTM/vicQlTpQQR1aJgJZcITsBMJfDqHhByVQJ0' ;;
      HOME)        val="${home}"                                     ;;
      HISTDIR)     val="${home}/ApplicationData"                     ;;
      DATADIR)     val="${home}/.config/VintagestoryData"            ;; # or use: "$(csharp -e 'print(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));' 2>/dev/null)/VintagestoryData"
      MENUDIR)     val="${home}/.local/share/applications"           ;; # for all: MENUDIR="/usr/share/applications"
      FONTDIR)     val="${home}/.fonts"                              ;; # for all: FONTDIR="/usr/share/fonts"
      DESKDIR)     val="$(vs_user xdg-user-dir DESKTOP)"             ;; # only for the user
    esac
  fi
  eval "export ${1}='${val#*=}'"
}

#######################################
# Identify and set VS instance parameters
# Globals:
#   VS_CLR : C# runtime environment (interpreter)
#   VS_BAS : SW install base dir
#   VS_BIN : VS binary name
#   VS_TYP : type vs_server | vs_archive
#   VS_OWN : world data owner
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
#   VS_HIS : threshold (count) to keep backups
#   VS_OLD : threshold (days) to maintain world saves
#   VS_DPN : default port number
#   VS_PRE : world data naming prefix
#   VS_BIN : VS binary name
#   VS_DTL : VS desktop launcher
#   VS_FNT : VS game font location
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
#   VS_CFG : serverconfig file name
#   VS_OUT : server output file
#   VS_CLR : C# runtime environment (interpreter)
#   VS_MIG : world data migration list
#   SR_HOST: release api hostname:port 
#   SR_PKEY: release api pubkey sha256 digest
#   SP_HOST: package repo hostname:port 
#   SP_PKEY: package repo pubkey sha256 digest
#######################################
vs_set_env() {
  local etc="$(readlink -f -- "${0%/*}")/.etc" reply='' i p err bv             # etc is the "physical" location of the symbolic link file
  vs_read_env ${etc} VS_HIS VS_OLD VS_DPN VS_PRE VS_TAG VS_TYP VS_OWN VS_BAS VS_DAT VS_LOG VS_PID VS_PIF VS_RTR OPTIONS VS_BIN VS_DTL VS_FNT VS_CFG VS_MIG VS_OUT VS_CLR SR_HOST SR_PKEY SP_HOST SP_PKEY
  [ ! -e "${etc}" -a -f "${VS_ETC}" -a -O "${etc%/*}" ] && vs_user "ln -sf '${VS_ETC}' '${etc}'"
  vs_toolcheck ${VS_CLR}      '4.2'
  vs_toolcheck 'wget'         '1.17.9'
  vs_toolcheck 'screen'       '4.0'
  i="$(cat ${VS_PID} 2>/dev/null)"; p="(${0##*/}|vs-.*)"
  if [ ${i:-$$} -ne ${6:-0} ] ; then
    [ ${i:-$$} -ne $$ -a -n "$(ps -p "${i:-$$}" -eo comm | grep -qE "${p}")" ] && vs_out -a "${0##*/} was temporarily locked by another VS command" 1
    printf "$$" > "${VS_PID}"                                                  || vs_out -a "Unexpected condition E#24 (user was not able to create pidfile '${VS_PID}')" 3
    [ "$(cat ${VS_PID} 2>/dev/null)" = "$$" ]                                  || vs_out -a "${0##*/} is temporarily locked by another VS command" 1
    [ -d "${VS_BAS}" ]                      || err=" dir ${VS_BAS}"
    [ -f "${VS_BAS}/${VS_BIN}" ]            || err="${err} bin ${VS_BIN}"
    getent passwd "${VS_OWN}"    >/dev/null || err="${err} owner ${VS_OWN}"    # need to check SW owner? set -- $(ls -ld "${VS_BAS}/${VS_BIN}" 2>/dev/null) && local owner="${3}"
    getent group  "${VS_OWN}"    >/dev/null || err="${err} group ${VS_OWN}"
    [ -n "${err}"  -a "${1}" != "setup" ]                                      && vs_out -a "VS environment of not found (missing${err}). Please run '${VS_UI1}' with proper privileges" 1
    [ -z "${_TAG}" -a "${1}" != "setup" -a ! -x "${VS_BAS}/${VS_BIN}" ]        && vs_out -a "VS environment set up incomplete. Please run '${VS_UI1}' with proper privileges" 1
    if [ -f "${VS_BAS}/${VS_BIN}" ] ; then
      bv=$(vs_user "${VS_CLR} '${VS_BAS}/${VS_BIN}' -v | tr -dc '[:print:]'")  # datapath workaround not needed in 1.5.1 ff.
      if [ "${bv}" != "${_VER}" -a "${1}" != "reinstall" ] ; then      
        vs_out "Current ${VS_BIN} binary version ${bv} out of sync with installation metadata tag (typically caused by manual installation)" 1
        echo; read -p "CONFIRMATION REQUIRED: Trying to recover metadata (Y/n) " -r reply; echo
        [ "${reply}" = 'y' -o "${reply}" = 'Y' ]  && vs_idx_base "${VS_BAS}"   || vs_out "You denied the metadata recovery. Be aware that missing metadata might cause unexpected behaviour."
        vs_read_env "${VS_ETC}" VS_TAG                                         # reads the .tag file again
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
  local var='' val='' wn=''
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
#   VS_PRE : world data naming prefix
#   VS_CFG : serverconfig file name
# Arguments:
#   $1 : working subdirectory
#   $2 : world seed (opt.)
#   $3 : world port (opt.)
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_gen_workdir() {
  local nd="${1}" wd="${1#new.$$.}" pn=${3:-${VS_DPN}} cf=${VS_CFG} sfix='' rn='' wn='' jf='' md=''
  [ -n "${VS_PRE}" -a "${VS_PRE}" != '-' ] && sfix="${VS_PRE}[0-9][0-9]-"
  wn="$(echo ${wd#${sfix}} | tr '-' ' ' | sed 's/\b./\u&/g')"                                                  # extract world name in titlecase from the lowercase folder name
  vs_gen_seed -v rn "${2}" "${wn}"
  jf="{\n \"ServerName\": \"VS\",\n \"Port\": ${pn},\n \"WorldConfig\": {\n  \"Seed\": \"${rn}\",\n  \"SaveFileLocation\": \"${VS_DAT}/${wd}/Saves/${wd}.vcdbs\",\n  \"WorldName\": \"${wn}\",\n },\n}\n"
  for md in ${VS_DAT}/${nd} ${VS_DAT}/${nd}/Saves ${VS_LOG}/${wd} ; do
    if ! [ -d "${md}" ] ; then
      vs_user "mkdir -m 775 -p '${md}'                                                          2>/dev/null"   || vs_out -a "Creating new dir ${md} failed" 3
      vs_out "Created new dir: $(ls -ld ${md})" -1
    fi
  done
  ###
  [ -f "${VS_DAT}/${nd}/.info" ] || vs_user "printf 'STOPPED:${_VER}' >'${VS_DAT}/${nd}/.info'  2>/dev/null"   || vs_out -a "Unexpected condition E#25" 3
  ###
  [ -e "${VS_DAT}/${nd}/Logs"  ] || vs_user "ln -sf '${VS_LOG}/${wd}' '${VS_DAT}/${nd}/Logs'"                  || vs_out -a "Unexpected condition E#26" 3
  [ -f "${VS_DAT}/${nd}/${cf}" ] || vs_user "printf '${jf}' >'${VS_DAT}/${nd}/${cf}'            2>/dev/null"   || vs_out -a "Unexpected condition E#27" 3
}

#######################################
# Print last accessed world-id identified by input
# (matching either string part or prefix number)
# or overall when no input is provided.
# Non-matching input generates a new world-id.
#   Depends on metadata to 
# Globals:
#   VS_DAT : world data root folder
#   VS_PRE : world data naming prefix
#   VS_CFG : serverconfig file name
# Arguments:
#   $1 : -v VAR   (opt. variable returns id)
#   $2 : world id (opt. globbing)
# Returns:
#   0  : always OK
#######################################
vs_get_world_id() {
  local var='' val='' sfix='' count=101 data base num nid wid i
  [ -n "${VS_PRE}" -a "${VS_PRE}" != '-' ] && sfix="${VS_PRE}[0-9][0-9]-"
  case ${1} in
    -v) shift; var=${1}; shift ;;
    --) shift                  ;;
  esac
  i=$(echo "${1%.vcdbs}" | tr '[:upper:]' '[:lower:]' | tr '[:space:][:punct:]' '-' | tr -s '-'); i=${i%-}
  [ $(echo ${VS_DAT}/${i:--}* | wc -w) -gt 1 ]                    && vs_out -a "vs_get_world_id() input parameter '${1}' matches too many world ids" 3 # protect rule 2 from picking wrong world
  [ "${1#${sfix}}" != "${1}" -a ! -d ${VS_DAT}/${i%%-*}-* ]  && nid="${i%%-*}"                  # preserve valid (unused) input prefixes
  i="${i#${sfix}}"
  for d in $(ls -tdx ${VS_DAT}/${sfix}*/${VS_CFG} 2>/dev/null) ; do
    data="${d%/${VS_CFG}}"; base="${data##*/}"; num="${base%%-*}"; count=$((count+1))
    ###
    [ -f "${data}/.info" ] || vs_idx_data "${data}"                                             # collect/create missing metadata from existing configs and logs
    ###
    [  ${num#${VS_PRE}}       -eq  ${1:-0}      ] 2>/dev/null   && wid="${base}" && break       # 1. numeric input: number matches to prefix (without prefix: section before first dash)
    [ "${base#${1:-${base}}}" !=  "${base}"     ]               && wid="${base}" && break       # 2. input without extension (starting with prefix): beginning string part matches (empty input too)
    [ "${base#${sfix}}"        =  "${1}"        ]               && wid="${base}" && break       # 3. input without extension and prefix: full name matches exactly
    [ "${base}"                =  "${1%.vcdbs}" ]               && wid="${base}" && break       # 4. input with extension: combination of prefix and full name matches exactly
  done;
  if [ -n "${sfix}" ] ; then
    [ -z "${wid:-${nid}}" ] && while [ -d ${VS_DAT}/${VS_PRE}${count#1}-* ] ; do count=$((count-1)) ; done  # validate an unused prefix
    val="${wid:-${nid:-${VS_PRE}${count#1}}-${i:-new-world}}"                                               # construct a (new) world name with prefix
  else
    val="${wid:-${i:-new-world}}"                                                                           # construct a (new) world name without prefix
  fi
  [ -n "${var}" ] && eval "${var}='${val}'" || echo "${val}"
}

#######################################
# Migrate world saves (rename, config)
# Precondition: stopped and backup done
# Globals:
#   VS_HIS : threshold (count) to keep backups
#   VS_DAT : world data root folder
#   VS_OWN : world data owner
#   VS_PRE : world data naming prefix
#   VS_CFG : serverconfig file name
#   VS_MIG : world data migration list
#   VS_OUT : server output file
# Arguments:
#   $1 : full world saves path to migrate/relocate
#   $2 : vcdbs name (opt. globbing, extension)
#   $3 : target subfolder name (opt.)
# Returns:
#   0  : Relocation OK (otherwise abort)
#   1  : Nothing found to relocate
#######################################
vs_migrate() {
  local sfix='' saves vcdbs match flags files wi wn wd sd td rn retval mf
  [ -n "${VS_PRE}" -a "${VS_PRE}" != '-' ] && sfix="${VS_PRE}[0-9][0-9]-"
  saves="${1:-.}"; vcdbs="${2%.vcdbs}"
  flags="-type f -group ${VS_OWN} -size +99k"
  files="$(find ${saves} ${flags} -name "${vcdbs:-*}.vcdbs" | sort)"
  if [ -n "${files}" ] ; then
    echo "${files}" | grep -q "${saves}/Saves/${3}.vcdbs" && grep -q "${3}.vcdbs" "${saves}/${VS_CFG}" 2>/dev/null && match="${saves}/Saves/${3}.vcdbs"
    echo "${files}" | while read line; do
      vcdbs="${line%.vcdbs}"; vcdbs="${vcdbs##*/}"; vcdbs="${vcdbs#default}"
      vs_get_world_id -v wi "${vcdbs:-new-world}.vcdbs"                                                                       # world id (files, folders) prefixed in lowercase
      wn="$(echo ${wi#${sfix}} | tr '-' ' ' | sed 's/\b./\u&/g')"                                                             # world name (title) without prefix in titlecase
      wd="${3:-${wi}}"                                                                                                        # world data folder (e.g. given by parameter 3)
      sd="${line%/Saves/*.vcdbs}"                                                                                             # source data folder (path)
      td="${VS_DAT}/new.$$.${wd}"                                                                                             # target data folder (path)
      vs_out "Migrate world '${vcdbs}' found in '${saves}' to v${_VER} subfolder '${wd}' ..." -1
      rn="$(cat "${sd}/${VS_OUT}" 2>/dev/null | tr -d '\000' | grep '] Seed: ')"; rn="${rn#*Seed: }"                          # no issue if no seed logged
      vs_gen_seed -v rn "${rn}" "${wn}"
      vs_gen_workdir "new.$$.${wd}" "${rn}"                                                                                   # including serverconfig
      [ ! -f "${line}" ] || vs_user "mv -f '${line}' '${td}/Saves/${wi}.vcdbs'                                   2>/dev/null" || vs_out -a "Unexpected condition E#x2 during file move" 3
      if [ "${line}" = "${match:-${line}}" ] ; then
        for mf in ${VS_CFG} ${VS_MIG}; do
          [ -e "${sd}/${mf}" ] && vs_user "mv -f ${sd}/${mf} '${td}'                                             2>/dev/null" # no issue if no migration files
        done
        vs_set_cfg "${td}" -sf "${VS_DAT}/${wi}/Saves/${wi}.vcdbs" -wn "${wn}" -sn "${rn}"       
        vs_user "mv -f ${sd}/.info '${td}/.old'                                                                  2>/dev/null" # no issue if no old .info copy
      fi
    done
    retval=$?; [ ${retval} -le 1 ]                                                                                            || exit ${retval} # catch abort from piped 'while' (subshell)
    for wi in ${VS_DAT}/new.$$.* ; do
      td="${VS_DAT}/${wi##*/new.$$.}"
      vs_out "Make migrated world folder '${td}' accessible" -1
      [ -f "${td}/${VS_CFG}"       ] && mv -fT "${td}/${VS_CFG}" "${td}/replaced_${VS_CFG}"                                   # rename the 'to-be-replaced' config to mark it replaced
      [ -d "${wi}" -a   -d "${td}" ] && mv -fT "${td}" "${VS_DAT}/replaced_$(date +%F_%H:%M)_${td##*/}"                       # move the 'to-be-replaced' subfolder out of the way
      [ -d "${wi}" -a ! -d "${td}" ] && mv -fT "${wi}" "${td}"                                                                # relocate the post-migration target subfolder
      [ -d "${wi}" ] && vs_out "Moving ${wi} to ${td} failed. Manual cleanup required." 2
      ls -tdx ${VS_DAT}/replaced_*_${td##*/} 2>/dev/null | sed -e "1,${VS_HIS}d" | xargs rm -fr                               || vs_out "Housekeeping of replaced world folders failed." 0
    done 
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
#   Uses metadata to identify already migrated folders
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
  local days=${1:-${VS_OLD}} reply=''
  ls -tdx ${VS_DAT}/replaced_*/${VS_CFG} 2>/dev/null | xargs rm -fr                                                                          || vs_out "Cleanup of obsolete legacy configurations failed."
  [ -f "${VS_DAT}/.mig" ] && return 0                                                                                                        # diff -q ${VS_BAS}/.tag ${VS_DAT}/.mig 2>&1
  echo; read -p "INTERACTION REQUIRED: Datapath of world saves seems to be changed. Do you want to maintain legacy saves (Y/n) " -r reply
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
      echo; read -p "Please enter number to migrate this save to data location '${VS_DAT}' (leave with enter) " -r reply
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
    echo; read -p "Do you want to continue migrating legacy world saves (Y/n) " -r reply
    [ "${reply}" = 'n' -o "${reply}" = 'N' ] && break || echo
  done
  vs_user "cp -f '${VS_BAS}/.tag' '${VS_DAT}/.mig'"                                                                                          # persist info that migration is done
  if [ -n "${scan}" ] ; then
    echo; read -p "INTERACTION REQUIRED: Do you want to ARCHIVE the remaining legacy world saves (y/N) " -r reply
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
#   Restart depends on metadata to define the restart scope (.info)
#   Restart depends on metadata to detect software changes (.tag)
# Globals:
#   VS_BAS : SW install base dir
#   VS_DAT : world data root folder
#   VS_RTR : change restart tracker
#   VS_PRE : world data naming prefix
# Arguments:
#   $1 : change | recover flag (opt.)
#   $2 : server instance (world id) 
# Returns:
#   0  : always OK (otherwise abort)
#######################################
vs_restart() {
  local sfix='' flag world changed wd run_info run
  case ${1} in
    -c) shift; flag='-c'                  ;;
    -r) shift; flag='-r'                  ;;
    --) shift                             ;;
  esac
  [ -n "${VS_PRE}" -a "${VS_PRE}" != '-' ] && sfix="${VS_PRE}[0-9][0-9]-"
  world="${VS_DAT}/${1:-${sfix}*}"                                     # world id not set in case of update/reinstall, default matches to all valid folders
  changed="$(diff -q ${VS_BAS}/.tag ${VS_RTR} 2>&1)"                   # real change means: version differs and restart has not done yet
  if [ -n "${changed}" -o "${flag}" != '-c' ] ; then
    for wd in ${world} ; do
      if [ -d "${wd}" -a -f "${wd}/.info" ] ; then
        run_info=$(cat "${wd}/.info" 2>/dev/null)
        vs_stop "${wd##*/}" "${run_info}"                              # all instances will be stopped
        [ "${run_info%:*}" = "STARTED"    ] && run='Y' || run=''       # identify instance to be started
        [ "${flag}" = '-r'                ] && vs_recover "${wd##*/}"  # including migration in the case of a backup recovery (means world id should be set) 
        [ "${flag}" = '-c' -a -n "${run}" ] && vs_backup  "${wd}"      # including migration in the case of a version change
        if [ -n "${run}" ] ; then 
          vs_start "${wd##*/}"
        else
          vs_out "${wd##*/} (to be ${run_info%:*}) is not restarted."
        fi
      else
        vs_out "World ${wd##*/} not found" 1
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
  local keywords task o b d w v l p t s x
  keywords="$(printf "start\nstop\nrestart\nbackup\nrecover\nupdate\nreinstall\nrollback\nsetup\nstatus\ncommand\n")"
  if echo "${1}" | grep -qwF "${keywords}" ; then
    task="${1}"; shift
  fi
  while getopts ":o:b:d:w:v:l:p:s:USPCRT" opt; do
      case ${opt} in
        o) o="${OPTARG}"                                                        ;;
        b) b="${OPTARG}"                                                        ;;
        d) d="${OPTARG}"                                                        ;;
        w) w="${OPTARG}"                                                        ;;
        v) v="${OPTARG}"                                                        ;;
        l) l="${OPTARG}"                                                        ;;
        p) p="${OPTARG}"                                                        ;;
        s) x="${OPTARG}"                                                        ;;
        U) t='unstable'                                                         ;;
        S) t='stable'                                                           ;;
        P) t='pre'                                                              ;;
        C) s='vs_archive'                                                       ;;
        R) s='vs_server'                                                        ;;
        T) VS_TST=1                                                             ;;
        :) vs_out "-${OPTARG} argument needed" 2; vs_usage -a $?                ;;
        *) vs_out "Invalid option -${OPTARG}"  2; vs_usage -a $?                ;;
      esac
  done
  shift $((OPTIND-1))
  if [ -z "${task}" ] ; then
    if echo "${1}" | grep -qwF "${keywords}" ; then
      task="${1}"; shift
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
    setup)     vs_cmd_priv   "${VS_OWN}" && vs_setup "${s}" "${o}" "${b}" "${d}" "${x}" ;;
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

# see https://github.com/zkol/vsadmin#roadmap 

#######################################
# About this script 
#######################################

# see https://github.com/zkol/vsadmin#how-the-script-works


