# VSadmin

This repository contains admin scripts for Vintage Story (see https://www.vintagestory.at if you want to learn about Vintage Story). 

## History

Tyron created an initial server script to be shipped with Vintage Story (heavily adapted from http://minecraft.gamepedia.com/Tutorials/Server_startup_script). His idea was to provide a shell script for setting up a Vintage Story Multiplayer server on a Linux based host via terminal commands, especially mentioned as a quick start for users that are not familiar with creating their own scripts. This server script was not mentioned as a production ready hosting solution and had the following (limited) features:

* start, stop, restart the server as daemon (meant to be integrated in the boot process)
* simple status check of the server daemon
* console interface to interactive server commands 
* offline backup of software and world data
* clean update and reinstall of Vintage Story versions

Having this features in a shell script, it is important to emphasize that this script was never mandatory to run a Vintage Story server (running mono VintagestoryServer.exe is sufficient)

As the Vintage Story evolved, more and more script features were broken by changes in VintagestoryServer.exe and Tyron had no time to fix the usablitity and compatibilty issues that were reported. So he asked me if I could help and fix the script. Working on the development priorities 1-4 (see below), I reached step by step the point, where I felt it necessary to refacore the script in order to manage the switch from Vintage Story versions 1.4.9 to 1.5.1. In consequence, Tyron asked me to set up a git repository to access script code (and documentation).

## Development Focus

Like Vintage Story this script is in development.

Currently, my main goals are (ordered by priority)
1. continue Tyrons approach of the script and adapt it according to his wishes
1. keep it in sync with the evolution of Vintage Story (e.g. stay compatible and make new server features available)
1. make it as robust and portable as possible (e.g. reduce dependencies, reach full POSIX comformity, logging of script actions, prevent resource conflicts, code documentation)
1. enhance the usability and hence decrease the maintainance issues (e.g. eliminating data corruption caused by wrong usage)
1. carefully extend the support of more use cases (e.g. data recovery, update rollbacks, data migration from previous versions, multiple instances)
1. create and enhance documentation of the script and the use cases (e.g. this README)
1. reduce the increased complexity driven by the points above (e.g. to mitigate limitations of the shell script approach)

Currently I take Ubuntu 16.04 LTS as the main reference for development and test of this script (using Ubuntu 18.04 LTS, too).

## Script Installation Requirements

The server script (server.sh) can be used to set up and manage a Vintage Story installation as well as managing Vintage Story via shell console.
It is a POSIX shell script, this means everybody can check the source code, nothing is hidden or obscure (provided shell knowlegde is available).

To start, simply download the script

* server.sh

with your POSIX compatible computer into a folder of your choice and make the script excutable (If you do not know how to do this please start reading with https://linuxconfig.org/bash-scripting-tutorial-for-beginners#h7-script-execution).

The script needs as a minimum
* computer with internet access (at least to set everything up)
* wget package (at least version 1.17.9 that supports keypinning) used by the script itself
* mono package (at least version 4.2, latest stable version is highly recommended) used by Vinage Story

### Reduced install
For a reduced server only install (option -R) essentially the mono **runtime** package should be sufficient (e.g. on a headless minimal server OS):
1. mono-runtime
1. libnewtonsoft-json5.0-cil
1. libmono-system-drawing4.0-cil
1. libmono-system-io-compression4.0-cil
1. libmono-system-io-compression-filesystem4.0-cil

As Newtonsoft.Json is packaged with Vintage Story, there should be a way to get rid of package 2 and 3. 

### Complete install
For a complete server/client install (option -C) capable to run the client too, the mono **complete** package is required (e.g. on a graphical desktop OS)
1. mono-complete

## Current Features

### Usage

* server.sh [OPTION]... (setup | update | reinstall | rollback) 
* server.sh [OPTION]... (start | stop | restart | status | backup | recover)
* server.sh [OPTION]... command SERVER_COMMAND

### Setup options

 -o OWNER     Set custom owner name for software setup.
 -b BASEDIR   Set custom full directory path for software installation.
 -d DATADIR   Set custom full directory path for world data access.
 -C | -R      Consider complete|reduced package for installation.

### General options

 -v VERSION   Set reference versionstring (not latest version).
 -w WORLD     Set custom world subdirectory for data access.
 -U | -S      Consider unstable|stable branch for installation.
 -T           Trace script run in test mode (ignoring some checks).

### Technical options
 
 -l PID       Consider the lock that is hold by process id PID
 -p PORT      Set custom port to create or import world instances

### Server Commands

Try 'server.sh command help' for available server commands.

## How to

The following instructions assume that the server script is already downloaded and installed on a Linux server

1. **Install Vintage Story to play on Linux and to share worlds with a local multiplayer LAN-Server**
   * Check the requirements for a complete install
   * Log in as the user who shall run the client and manage the LAN-Server
   * Open a terminal, change to the directory of server.sh, and execute:
     * **./server.sh -C -o $USER setup**
   * Script result:
     * Asks for confirmation to set up the installation with the chosen parameters
     * Downloads and installs latest stable Vintage Story software under base directory /opt/vintagestory/game
     * Prepares server data directory /var/opt/vintagestory (not only for world saves, also for log files and backups)
     * Log files can be found under /var/log/vintagestory too
     * Creates a menu shortcut to start the client (as well as a desktop link)
     * Location for single player worlds will be standard $HOME/.config/VintagestoryData
     * Setup offers interacive option to move existing worlds in /var, /opt, and /home to the new server data location (except single player worlds in $HOME/.config/VintagestoryData and $HOME/ApplicationData) 
   * If you do not like the location of base directory or data directory, please use instead the options -b and -d
     * Run for example: ./server.sh -C -o $USER -b $HOME/vintage/game -d $HOME/vintage/data setup

1. **Install Vintage Story on Linux as a headless multiplayer LAN-Server**
   * Check the requirements for a reduced install
   * Log in as an admin user who is allowed to run commands per sudo
   * Open a terminal, change to the directory of server.sh, and execute:
     * **sudo ./server.sh -R setup**
   * Script result:
     * Asks for confirmation to set up the installation with the chosen parameters
     * Prepares system user and system group vintagestory as the software and data owner
     * Downloads and installs latest stable Vintage Story software under base directory /opt/vintagestory/game
     * Prepares server data directory /var/opt/vintagestory (not only for world saves, also for log files and backups)
     * Log files can be found under /var/log/vintagestory too
     * Setup offers interacive option to move existing worlds in /var, /opt, and /home to the new server data location (except worlds in /home/vintagestory/.config/VintagestoryData and /home/vintagestory/ApplicationData) 
   * If you do not like the location of base directory or data directory, please use instead the options -b and -d
     * Run for example: sudo ./server.sh -R -b /home/vintage/game -d /home/vintage/data setup

1. **Create and start the first multiplayer world** (e.g. on a headless LAN-Server)
   * Log in as an admin user who is allowed to run commands per sudo
   * Choose a custom name for the first world, e.g. "Hunger Madness"
   * Open a terminal, change to the directory of server.sh, and execute:
     * **sudo ./server.sh -w "Hunger Madness" start**
   * Script result:
     * Asks for confirmation to create a new world (if no world is running on the default port)
     * Creates world folder /var/opt/vintagestory/w01-hunger-madness
     * Starts the forst server process
     * Prints the stats of the (hopefully sucessful) start of this process

1. **Privilege an admin user for the first world** (e.g. on a headless LAN-Server)
   * Log in as an admin user who is allowed to run commands per sudo
   * Open a terminal, change to the directory of server.sh, and execute:
     * **sudo ./server.sh -w1 command op skol** (assuming skol is the Vintage Story username)
   * Parameter -w is not necessary to address the instance with the lastet start time 
   * Script result:
     * Sends command op to the server
     * Prints the command result (that has been logged by the server)
     
1. **Create and start the second multiplayer world in parallel** (e.g. on a headless LAN-Server)
   * Log in as an admin user who is allowed to run commands per sudo
   * Choose a custom name for the second world, e.g. "Second World"
   * Open a terminal, change to the directory of server.sh, and execute:
     * **sudo ./server.sh -w "Second World" -p 47111 start**
   * Script result:
     * Asks for confirmation to create a new world (if no world is running on port 47111)
     * Creates world folder /var/opt/vintagestory/w02-second-world
     * Starts the second server process in parallel
     * Prints the stats of the sucessful start for this process

1. **Check the status of a server instance** (e.g. on a headless LAN-Server)
   * Log in as an admin user who is allowed to run commands per sudo
   * Know the number or name of the world, e.g. 1 or hunger-madness (otherwise the script checks the instance with the latest start/stop time)
   * Open a terminal, change to the directory of server.sh, and execute for example one of the following commands: 
     * **sudo ./server.sh -w1 status**
     * **sudo ./server.sh -w hunger-madness status**
   * Script result:
     * Prints the stats for this process

1. **Stop, restart, or backup a server instance** (e.g. on a headless LAN-Server)
   * Log in as an admin user who is allowed to run commands per sudo
   * Know the number or name of the world, e.g. 2 or second-world (otherwise the script checks the instance with the latest start/stop time)
   * Open a terminal, change to the directory of server.sh, and execute for example one of the following commands: 
     * **sudo ./server.sh -w2 stop (or restart, or backup)**
     * **sudo ./server.sh -w second-world stop (or restart, or backup)**
   * Script result:
     * Stops (or restarts, or backs up) the server instance

1. **Update the stable software to the lastest unstable version** (e.g. on a headless LAN-Server)
   * Log in as an admin user who is allowed to run commands per sudo
   * Open a terminal, change to the directory of server.sh, and execute: 
     * **sudo ./server.sh -U update**
   * Script result:
     * Downlads and installs the latest unstable version (if not already installed)
     * Backs up all worlds
     * Restarts all running instances

1. **Rollback the last update** (e.g. on a headless LAN-Server)
   * Log in as an admin user who is allowed to run commands per sudo
   * Open a terminal, change to the directory of server.sh, and execute:
     * **sudo ./server.sh rollback**
   * Script result:
     * Downlads and installs the latest unstable version (if not already installed)
     * Restarts all running instances

1. **Downgrade to a specific software version** (e.g. on a headless LAN-Server)
   * Log in as an admin user who is allowed to run commands per sudo
   * Know the desired verion number and wether it is stable or untable
   * Open a terminal, change to the directory of server.sh, and execute for example one of the following commands:
     * **sudo ./server.sh -U -v 1.5.2.3 reinstall**
     * **sudo ./server.sh -S -v 1.5.1.6 reinstall**
   * Script result:
     * Downlads and installs the desired stable or unstable version (even if already installed)
     * Restarts all running instances



## Roadmap

This is a list of potential topics for the next script versions.

### Prio 1 
1. Test and document how to install multiple server versions in parallel (considerung script/configuration links that reside in different locations)
1. Split basic start/stop/status features from server.sh (portable according to system V init style, with minimized handling of one datapath relative to the script location) from the extended admin features (move the existing features to a vsadmin.sh script)
1. Replace screen, instead start the daemon by POSIX shell commands, improve force stop/restart feature (in the case of a not responsive server status)
1. Replace host existing connect test (by using a openssl command sequence) with wget-based connection test (eliminate openssl dependency)
1. Better documentation of minimal server requirements as well as refinement of requirement checks

### Prio 2
1. Reduce the dependency on naming conventions, to provide a better interface to other server management tools (e.g. web GUI written by other community members)
1. Add options to repair/cleanup/uninstall for old/failed installs (searching the file system for Vintage Story binaries)
1. Provide option to start/stop all registered parallel instances with one command (including option to list this instances)
1. Improve trace feature as well as error-code systematics and documentation (trace could be selective by providing a previous error code)
1. Test and document how to setup the OS to autmatically restart the server on a failure

### Prio 3
1. Better portability of used shell tools (e.g. alternative to the find -printf feature)
1. Improve current restart logic in case of SW installation: no quick stop/start, instead scheduling server admin notification (console/server) to recommend restart
1. Manage full serverconfig.json template when serverconfig.json is missing (or use the JSON merge feature)
1. Manage to consistently rename worlds/datafiles
1. Introduce to execute prepared server commandfiles, e.g. for world upgrade by block remapping  

## How the script works

This script relies on some environment parameters: 
1. a bit of meta data to define which custom locations were chosen and which stable/unstable package has been installed
1. a naming convention to manage different datafolders with the means of a shell script
1. the inital setup that defined the parameters (and saved them to either /etc/opt/vintagestory or a local ./.etc file)
1. the success of a integrity check that is performed on each script use

This means manual moving and renaming will most probably mess up everything (means the script complains). 
More info will be added later.

