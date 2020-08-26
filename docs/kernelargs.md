# Paragon Kernel Arguments

    /boot/paragon [arguments ...]

Arguments may NOT contain spaces.

## root=PARTSPEC

This argument selects a partition to use as the root device.  For example, `ocgpt(74792ddf-e603-43e3-bd71-c066c416d798,3)` for the third partition in the OCGPT of the drive with address `74792ddf-e603-43e3-bd71-c066c416d798`.

## loglevel=NUM

Sets the log level. All messages with a value smaller than the specified NUM will be printed to the console. Levels:

  - 0: system condition is critical and boot cannot continue
  - 1: error conditions
  - 2: warning condidions
  - 3: normal but significant
  - 4: debug-level info

## console=DEVICE

Sets the boot console output device. DEVICE must be in the form of a pair of UUIDs for a GPU and screen, such as `fe9a273b-247b-b382-d3b0-070b2d505cad,6eee9b13-5159-4d21-917c-fdd197d96122`.

## initrd=FILE

The kernel will attempt to load FILE as its initrd image on boot.

## Other Options

Some optional modules may take additional options. These are documented in `docs/mods/$MODNAME.md`.
