# Changelog

Overview of all changes in the admin scripts for Vintage Story

## server.sh

### 2016-02-09 Script version 0.4.2 (shipped until VS 1.4.8 stable) 
* Initially adapted from http://minecraft.gamepedia.com/Tutorials/Server_startup_script

### 2018-01-04 (testing)
* Fixed: Download path of tar.gz changed
* Fixed: Status command checks for 2 processes with service signature (screen and mono)
* Fixed: Server stop command tries to quit screen as last option
* Feature: Check for mono-xmltool and compiler version > 4.2
* Tweak: Can be run as user of group vintagestory (not only by vintagestory owner)
* Tweak: Can be run as vintagestory owner by SU even when the default shell permits a login

### 2018-01-05 (testing)
* Fixed update to consider versions as documented (shall not downgrade newer unstable versions)
* Fixed: Adjusted some operators & co for better script portability and better fault tolerance  (removing deprecated notation)
* Fixed: Check if downloaded archive is not HTML file (e.g. 404 page)
* Fixed: Check if downloaded archive is really a gzip file
* Fixed: ownership of reinstalled/updated/archived files
* Fixed: install function truncating version number from 5 chars to 7 chars
* Fixed: command handling (accessing the logged result)
* Tweak: Environment-Variable `NO_SUPPORT_MODE` to possibly ignore the version check
* Tweak: Mixed coding practises slightly harmonized for better maintainability (less style mixing)
* Tweak: Switched download to HTTPS
* Tweak: Optional version parameter for reinstall in order to allow a downgrade

### 2018-01-06 Script version (shipped with VS 1.4.9 unstable)
* Fixed: command output
* Feature: Adding a general installation check
* Feature: Adding basic server environment setup
* Tweak: Using -v instead of monodis (eliminates one dependency and its check)
* Tweak: Adding command probe to the status check (as function `vs_status`)
* Tweak: Adding proper return values and error messages to the functions

### 2018-01-13 Script version (shipped with VS 1.4.9.2 stable)
* Fixed: Clean installation approach (create new folder) that should work even with major updates
* Fixed: Backup during install to archive the OLD version (and not the NEW version)
* Fixed: Workaround to recognize running server process by user of group vintagestory (and vice versa)
* Fixed: Function `vs_version` to work around implicit datapath creation silently done by VintagestoryServer -v 
* Feature: Support of changed data path logic in VintagestoryServer 1.4.9.2 
* Tweak: Define standard data path for server installation as /var/vintagestory/data
* Tweak: Setup defines and passes the data path parameter to VintagestoryServer 1.4.9.2
* Tweak: Install new version in parallel to running server and switch/restart afterwards
* Tweak: Support a seperate data backup (on a different path)
* Tweak: Improved return value handling for independent processing steps
* Tweak: Use `NO_SUPPORT_MODE` as quick workaround to install/test unstable versions

### 2018-02-22 Script version 1.5.1 (testing)
* Refactoring: `vs_status` as `vs_get_status` to get unique service instance status independent from user
* Refactoring: Streamlined version check, code backup, data backup, setup (eliminating redundant tasks)
* Refactoring: Replaced workarounds (`vs_version` datapath handling, process identification, unstable versions, `NO_SUPPORT_MODE`)
* Refactoring: Standardized headers, naming, coding conventions (minimizing sideeffects, ...), ported to /bin/sh for better POSIX conformity
* Feature: Enhanced update and reinstall supporting VS api server and download checksums (using wget keypinning for additional security)
* Feature: Naming conventions and housekeeping features for world data, rollback of SW installs, recover of data backups
* Tweak: Adjusted umask and datapath group rights, default paths according to http://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html
* Tweak: Functions `vs_usage` and `vs_out` with improved formatting (to console and syslog), e.g. for fatal errors like failed install checks
* Tweak: Prompt to run ./server.sh setup instead of calling setup function directly
* Tweak: Clean getopts handling, config options (etc/opt/.vintagestory) to eliminate the need of patching hardcoded values in server.sh
* Tweak: Command conflict/status model: Restart will only start if server was previously started, etc.

### 2018-03-01 Script version 1.5.1.1 (testing)
* Fixed: Known issue 01 - Empty migration list will not offered for a interactive selection
* Fixed: Known issue 02 - Server commands wait for indicator log keyword (instead of fixed time): `vs_stop`, `vs_start`, `vs_backup`
* Fixed: Known issue 03 - Migrating a folder with multiple worlds preserves the active serverconfig and does not overwrite worlds
* Fixed: Known issue 04 - Script recognized legacy world saves in the datapath and imports them without user interaction
* Fixed: Known issue 05 - Additional check during start command to prevent starting multiple servers in parallel (on the same port)
* Fixed: Known issue 06 - Ownership and group rights of /etc/opt configfile adjusted to root, ownership checked before creating link to configfile
* Fixed: Known issue 07 - Setup maintains legacy saves once per new `VS_DAT` location - client specific DATADIR is always pruned from the legacy search
* Fixed: Known issue 08 - Specific world migration condition for backup task and `vs_get_world_id` match, duplicate check for world selection condition
* Fixed: Known issue 09 - Restart and migration after reinstall now recognizes the migrated world properly, error handling of the backup function
* Fixed: Known issue 10 - Command substitution of `vs_command`, `vs_get_status`, `vs_get_world_id`, `vs_host_connect` replaced to fix abort
* Fixed: Known issue 11 - Creating world data folder (including minial serverconfig) not without confirmation, especially not on read-only tasks
* Fixed: Known issue 12 - Processing of online backup filenames now produces the correct world name input for the recovery function
* Tweak: Reduce (sometimes confusing) console output to a reasonable minimum by using debug loglevel

### 2018-03-03 Script version 1.5.1.2 (shipped with VS 1.5.2 unstable)
* Fixed: Setting executable rights properly (now works with /bin/sh too)
* Fixed: Prevent 1.5.1.6 crash caused by invalid seeds in serverconfig files by limiting seed to 9 decimal digits
* Tweak: Import of legacy worlds keeps seed value from server logfile
* Tweak: Better status handling for recovery, Failed requirement check asks for confirmation

### 2018-03-23 Script version 1.5.1.3 (testing)
* Fixed: \n output with some shell implementations
* Tweak: Pass -l & -p parameter to `vs_set_env` function for technical lock handling and technical default port handling
* Tweak: Startup conflict handling considers the port number: multiple servers can be started as long as port numbers are different
* Tweak: Recognize need of setup even on manual installation in the default path
* Tweak: lowered the required screen version and rephrased abort message (that already allows to continue anyway).
* Tweak: option to continue even on installation inconsistency (considering messing up by manual installation)
* Tweak: more verbose output to the syslog facility

### 2018-03-26 Script version 1.5.1.4 (shipped with VS 1.5.2.6 stable)
* Fixed: Removed user switch related to exit E#24 (user switch is not needed and in some constellations not possible)
* Fixed: \n output with some shell implementations (special printf handling for log output that may contain % characters)

### 2018-03-28 Script version 1.5.1.5 (testing)
* Fixed: grep might recognize server-main.txt as binary file because of NUL bytes (gives an unexpected output)
* Fixed: Remove archived online backup files from Backups folder and exclude Backups folder from full backup (would affect recovery from backup)
* Tweak: Avoid regeneration of Playerdata from Savegame: Playerdata now included in Migration and Online Backup
* Tweak: Message about resource conflict now includes the port number
* Tweak: Host connection test simplified (dependency from openssl eliminated)
* Tweak: Keep a (manually) linked configuration file during update/reinstall

### 2018-04-01 Script version 1.5.1.6 (testing)
* Refactoring: new functions `vs_idx_base`, `vs_idx_data`, `vs_set_cfg` to prepare script modularization
* Fixed: setup of folder group permissions for a non-root user now considers the right folders
* Fixed: link to editable configuation file sometimes messed up
* Fixed: reinstall of same version triggers a world data migration (which was not necessary) 
* Tweak: setup considers existing install to adjust/relocate/update (instead of always doing a full reinstall)
* Tweak: restart on version change considers only started worlds for backup/migration (instead of all worlds) 
* Tweak: weighted housekeeping threshold parameter (factor 1 for directories, factor 3 for files)
* Tweak: added host connection parameters to the editable text configuration (centralizing static constants) 
* Tweak: adjusted timestamp format to long-iso (according to POSIX file date handling with ls)
* Tweak: Try to sync installation metadata (on confirmation) before abort
* Tweak: Reduced dependency from naming conventions: World folder suffix is now configurable (and can be disabled by -s -)

### 2018-04-02 Script version 1.5.1.7 (testing)
* Fixed: $HOME of software owner with desktop environment not properly set up
* Fixed: Last data access not properly recognized without metadata
* Fixed: Data replaced by recovery misinterpreted with suffix disabled
* Fixed: Wrong (non-existing) world name not properly handled with suffix disabled
* Fixed: Match pattern of the process signature is not backward compatible
