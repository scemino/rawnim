# rawnim

**Another World / Out of This World** engine re-implementation written in pure nim.
This project is a rewrite of [rawgl](https://github.com/cyxx/rawgl) by Grégory Montoir.

![rawnim](https://repository-images.githubusercontent.com/435237620/0501fef5-2b38-42b4-af9e-d61c0fa89ff9)

# Supported Versions

The program requires the original data files.

* Amiga (Bank*)
* Atari (Bank*)
* DOS (Bank*, memlist.bin)
* DOS demo (Demo*, memlist.bin)

# Usage

    rawnim [options]

    Options:  
    --help,          -h        Shows this help and quits
    --datapath:path, -d:path   Path to data files (default '.')
    --language=lang, -l:lang   Language (fr,us)
    --part=num,      -p:num    Game part to start from (0-35 or 16001-16009)
    --ega            -e        Use EGA palette
    --demo3-joy      -j        Use inputs from 'demo3.joy' (DOS demo)

In game hotkeys :

    Arrow Keys      move Lester
    Enter/Space     run/shoot
    C               enter a code to start at a specific position
    P               pause the game