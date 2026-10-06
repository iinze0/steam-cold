# steam-cold

List installed Steam games you have not played in a long time, and how much disk they use.

Windows 10/11. No install. Reads local Steam files only. Does not uninstall anything.

Made by iinze0.

## Use

```powershell
.\steam-cold.cmd
.\steam-cold.cmd -Days 30
.\steam-cold.cmd -Days 180 -Csv cold.csv
.\steam-cold.cmd -All
```

Default is 90 days. Games are sorted by size, largest first.

`-All` lists every installed game, still sorted by size.

A row is cold when Steam's `LastPlayed` in the app manifest is older than the cutoff, or missing. Size comes from `SizeOnDisk` in the same file.

The Uninstall column is a `steam://uninstall/<appid>` link. Open it yourself if you want the game gone. This tool never clicks it.

## What it reads

- Steam install path from the registry
- `steamapps/libraryfolders.vdf` for library folders
- `appmanifest_*.acf` in each library

It skips tools and redistributables (Steamworks Common Redistributables, Proton, dedicated servers, and app ids under 10).

## Not this

- [steam-reclaim](https://github.com/iinze0/steam-reclaim) finds leftover folders after a game is gone
- [steam-saves](https://github.com/iinze0/steam-saves) backs up save folders
- [shelf](https://github.com/iinze0/shelf) lists and launches games
