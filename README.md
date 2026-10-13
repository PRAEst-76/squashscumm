# squashscumm
A script for converting game data folders to [SquashFS](https://www.kernel.org/doc/html/latest/filesystems/squashfs.html) for recent SCUMMVM versions in [Batocera](https://wiki.batocera.org/systems:scummvm) and other supported retro-frontends.

The script will search for folders containing a .scummvm file and convert them to squashfs using the same name and back the original folders up.

scummvm (rom) directory, squashfs file directory and backup dir are configurable via the .conf file.

Script will prompt if multiple .scummvm files are found

I've included an unsquash script to reverse the process if you wanted to use your collection with another front-end or scummvm on it's own.

> [!NOTE]
> SquashFS is NOT supported in the scummvm itself or scummvm libretro (Retroarch) core as of writing, and requires the files to be accessed via Batocera or similar.
