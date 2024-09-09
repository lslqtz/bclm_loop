# BCLM_Loop

bclm_loop is a background looping utility that maintains the battery level of Apple Silicon based Mac computers. This project was inspired by several battery management solutions, including Apple's own battery health management.

The purpose of limiting the battery's max charge is to prolong battery health and to prevent damage to the battery. Various sources show that the optimal charge range for operation of lithium-ion batteries is between 40% and 80%, commonly referred to as the 40-80 rule [[1]](https://www.apple.com/batteries/why-lithium-ion/)[[2]](https://www.eeworldonline.com/why-you-should-stop-fully-charging-your-smartphone-now/)[[3]](https://www.csmonitor.com/Technology/Tech/2014/0103/40-80-rule-New-tip-for-extending-battery-life). This project is especially helpful to people who leave their Macs on the charger all day, every day.

This project was forked from upstream (https://github.com/zackelia/bclm).

## Installation

### From Source

```
$ make build
$ make test
$ sudo make install
```

### From Releases

```
$ unzip bclm_loop.zip
$ sudo mkdir -p /usr/local/bin
$ sudo cp bclm_loop /usr/local/bin
```

## Usage

```
$ bclm_loop
OVERVIEW: Battery Charge Level Max (BCLM) Utility.

USAGE: bclm_loop <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  loop                    Loop bclm on battery level 80%.
  persist                 Persists bclm loop service on reboot.
  unpersist               Unpersists bclm on reboot.

  See 'bclm_loop help <subcommand>' for detailed help.
```

The program must be run as root.

## Migrate

If you are migrating from upstream bclm or older version (ver < 1.0) of bclm_loop.

```
$ sudo bclm unpersist
$ sudo rm -f /Library/LaunchDaemon/com.zackelia.bclm_loop.plist
```

## Persistence

It can run in the background to maintain battery levels. Just create a new plist in `/Library/LaunchDaemons` and load it via `launchctl`. 

```
$ sudo bclm_loop persist
```

Likewise, it can be unpersisted which will unload the service and remove the plist.

```
$ sudo bclm_loop unpersist
```
