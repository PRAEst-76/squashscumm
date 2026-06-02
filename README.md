# squashscumm
A script for converting game data folders to [SquashFS](https://www.kernel.org/doc/html/latest/filesystems/squashfs.html) for recent SCUMMVM versions in [Batocera](https://wiki.batocera.org/systems:scummvm) and other supported retro-frontends.

The script will search for folders containing a .scummvm file and convert them to squashfs using the same name and back the original folders up.

scummvm (rom) directory, squashfs file directory and backup dir are configurable via the .conf file.

Script will prompt if multiple .scummvm files are found

> [!NOTE]
> SquashFS is NOT supported in the scummvm libretro (Retroarch) core as of writing.