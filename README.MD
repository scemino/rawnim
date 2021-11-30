# rawnim

Another World/Out of This World engine reimplementation written in pure nim.

# Supported Versions

The program requires the original data files.

* Amiga (Bank*)
* Atari (Bank*)
* DOS (Bank*, memlist.bin)

# Usage

    rawnim [options]

    Options:  
    --help,          -h        Shows this help and quits
    --datapath:path, -d:path   Path to data files (default '.')
    --language=lang, -l:lang   Language (fr,us,de,es,it)
    --part=num,      -p:num    Game part to start from (0-35 or 16001-16009)
    --ega            -e        Use EGA palette

In game hotkeys :

    Arrow Keys      move Lester
    Enter/Space     run/shoot
    C               enter a code to start at a specific position
    P               pause the game