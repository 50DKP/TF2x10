## Multiply A Weapon Stats by 10: The Plugin [![Build Status](http://198.27.69.149/jenkins/buildStatus/icon?job=TF2x10)](http://198.27.69.149/jenkins/job/TF2x10/)
It's in the name! All weapon stats multipled by 10. Everything about that (un)balanced goodness that you can run on your own TF2 server.

Join our group for a list of servers running the latest and greatest: http://steamcommunity.com/groups/tf2x10

### Requirements
* SourceMod 1.6+ (working on 1.7)
* TF2Items
* TF2Attributes
* SteamTools
* Updater

For the Updater bit: there will be times where Valve may change weapon attributes or add new ones. This is to ensure the server gets fast, timely updates to weapon attributes and any possible SourceMod plugin additions we have to complement the update. Highly recommended, but you can compile without the updater requirement if you so wish.


### Cvars
`tf2x10_autoupdate` (default 1):
Tells updater.smx to automatically update this plugin. 0 = off, 1 = on.

`tf2x10_crits_diamondback` (default 10):
Number of crits after successful sap with Diamondback equipped.

`tf2x10_crits_fj` (default 10):
Number of crits after Frontier kill or for buildings. Half this for assists.

`tf2x10_crits_manmelter` (default 10):
Number of crits after Manmelter extinguishes player.

`tf2x10_enabled` (default 1):
Toggle TF2x10. 0 = disable, 1 = enable

`tf2x10_gamedesc` (default 1):
Toggle setting game description. 0 = disable, 1 = enable.

`tf2x10_headscaling` (default 1):
Enable any decapitation weapon (eyelander etc) to grow their head as they gain heads. 0 = off, 1 = on.

`tf2x10_headscalingcap` (float, default 6.0):
The number of heads before head scaling stops growing their head. 6.0 = 24 heads.

`tf2x10_healthcap` (default 2000):
The max health a player can have. -1 to disable.

`tf2x10_includebots` (default 0):
1 allows bots (MvM or not) to receive TF2x10 weapons, 0 disables this.


### Admin Commands
`sm_tf2x10_disable`:
Disable TF2x10.

`sm_tf2x10_enable`:
Enable TF2x10.

`sm_tf2x10_getmod`:
Gets the current "mod" that is loaded over the default x10 weapons. See below.

`sm_tf2x10_recache`:
Clears the x10 weapon trie cache and loads x10.default.txt. Useful if you're testing out attributes on-the-fly.

`sm_tf2x10_setmod` *filename*:
Sets the current "mod". e.g. if the file is named `x10.myweaponstuffs.txt` then you will do `sm_tf2x10_setmod myweaponstuffs`.


### Mods
All TF2x10 weapon stats are placed in `x10.default.txt` in the configs folder. The TF2x10 weapon plugin also includes rudimentary tf2items-esque coded weapon mods that will allow you to load different weapon attributes than what will be loaded from the main default file. An example of this is `x10.vshff2.txt`, which is manually loaded on map change by a VSH/FF2 x10 server I run. Things in this file will cancel out things in the default.

Note that in your `x10.filenamehere.txt` file, the first line should be what you named your file.

See `x10.vshff2.txt` and how things are done if you want a good example. Please, NEVER touch `x10.default.txt` as that will be updated as Valve sends out weapon attribute changes, and it's so much easier to load a "mod" so you don't have to go through the hassle of modifying things.


### Known Compatibility With Other Game Mods
TF2x10's goal is for 100% compatibility with game mods. There may be one or two other game mods that will not ever work with x10, and that is fine. But things like Randomizer, Saxton Hale, Prop Hunt, etc. is what we're trying to be compatible with. Here's the full list:

* **Advanced Weaponiser**: due to the way it gives weapons, will not load tf2x10 if present.
* **Freak Fortress 2 & VS Saxton Hale**: should work mostly but some things (e.g. powerjack) and kunai may need to be adjusted. will post when I can get together everything.
* **Randomizer**: currently has something going with it that it crashes(?) it may be my server. In my bitbucket, there's a very unstable randomizer in it that you can try out, but I'd much rather get it to where the x10 plugin can take over stuff without needing to modify the actual plugin.


### Credits and Thanks
**Coders**:

InvisGhost - original x10 plugin to complement the tf2items txt

Isatis - overhaul, implementing TF2Attributes and pretty much 90% of what you see in the source

Dark Skript - bugfixing, additional support

RavenShadow - additional support

**Weapon Attributists**:

UltiMario - creating the mod and weapon attributes

Mr. Blue - PR and weapon attributes

**Thanks**:

FlaminSarge - for putting up with me and for some code examples I took (e.g. loading into trie) :p


### Install Instructions

Place all three folders in your `addons/sourcemod/` folder. Launch, and go!

If you are having any issues with the plugin itself, please post in the [AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=249361) instead of contacting anyone on the x10 team individually so we can better help you. Thanks!