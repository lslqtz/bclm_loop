# BCLM_Loop

bclm_loop is a background looping utility that maintains the battery level of Apple Silicon based Mac computers. This project was inspired by several battery management solutions, including Apple's own battery health management.

The purpose of limiting the battery's max charge is to prolong battery health and to prevent damage to the battery. Various sources show that the optimal charge range for operation of lithium-ion batteries is between 40% and 80%, commonly referred to as the 40-80 rule [[1]](https://www.apple.com/batteries/why-lithium-ion/)[[2]](https://www.eeworldonline.com/why-you-should-stop-fully-charging-your-smartphone-now/)[[3]](https://www.csmonitor.com/Technology/Tech/2014/0103/40-80-rule-New-tip-for-extending-battery-life). This project is especially helpful to people who leave their Macs on the charger all day, every day.

To use it, Apple Optimized Battery Charging must be turned off. It will first try to use firmware based battery level limits on supported firmware.

If the current battery level is higher than the target battery level, please manually discharge it to the target battery level or lower, otherwise it may only stay at the current battery level. This tool does not implement forced discharge because it may make the system unable to recognize the power adapter status.

When the battery is no longer charging (for any reason, including but not limited to reaching the target battery level or insufficient power from the power adapter), MagSafe LED will turn green, which may be inconsistent with system behavior (which only turn green when fully charged).

It only supports Apple Silicon based Mac computers.

This project was forked from upstream (https://github.com/zackelia/bclm).

## Installation

### Brew

```
$ brew tap lslqtz/formulae
$ brew install bclm_loop
```

### From Source

```
$ make build
$ sudo make install
```

### From Releases

```
$ unzip bclm_loop.zip
$ sudo mkdir -p /usr/local/bin
$ sudo cp bclm_loop /usr/local/bin/bclm_loop
$ sudo xattr -c /usr/local/bin/bclm_loop
$ sudo chmod +x /usr/local/bin/bclm_loop
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
  loop                    Loop bclm on target battery level (Default: 80%).
  persist                 Persists bclm loop service.
  unpersist               Unpersists bclm loop service.

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

It can run in the background to maintain battery levels. This command will create a new plist in `/Library/LaunchDaemons` and load it via `launchctl`. 

```
$ sudo bclm_loop persist
```

Likewise, this command can also unpersist by unloading the service and removing the plist.

```
$ sudo bclm_loop unpersist
```
