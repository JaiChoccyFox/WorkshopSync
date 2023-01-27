# ![Jai's WorkshopSync](/images/WorkshopSync.png)
A simple "install & play" add-on for the latest version of Garry's Mod.
This is a successor to my previous ***Simple Automatic Workshop Downloader*** add-on but designed to be as minimal as possible.
The add-on aims to synchronize all mounted Workshop add-ons to any client that joins the server, avoiding potentially missing assets because a client did not install a specific add-on.

WorkshopSync also implements what I call the "Dynamic Downloads" system. This means not every Workshop add-on will be downloaded while waiting at the loading screen, some add-ons will be installed while the client is in-game.
It uses the files present in a GMA to determine if the add-on is suitable for this system, otherwise it uses the resource system built into Garry's Mod.
If you encounter any issues with this system, you can either disable it or use the manual JSON method.

As part of the minimal design, there are no menus to customise anything. If you're looking for a more sophisticated solution, this add-on may not suit your needs.

## Installation
Download the latest release of this add-on via Steam Workshop or from the Releases/Downloads page here.

If you're installing this on SRCDS, it's recommended to use `+host_workshop_collection` to fully automate WorkshopSync's process.
If you wish to use the manual method, you are allowed to place **`*.json`** files into both the **`../garrysmod/data/workshop_sync/resource`** and **`../garrysmod/data/workshop_sync/dynamic`** directories.

## Console variables/commands
* `wsync_dynamic_downloads [0..1]`: enable WorkshopSync's Dynamic Downloads system. Takes effect upon loading a map.
* `wsync_resynchronize`: re-synchronize WorkshopSync's Dynamic Downloads system.
