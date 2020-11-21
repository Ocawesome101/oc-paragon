# Paragon

*Paragon is to Monolith as GNU Hurd is to Linux.*

Paragon is a UNIX-like kernel for the OpenComputers Minecraft mod.

I decided to start developing Paragon alongside the Monolith distribution for a few reasons:

  - Monolith's kernel is not very modular; that is, while module support is technically implemented, it is very basic and frankly not very useful, and there is no way to dynamically include or exclude optional modules.
  - Monolith does not provide an interface for cryptography or for easy native management of unmanaged-drive filesystems.
  - Monolith is by design at least partially OpenOS-compatible. While this is not necessarily a bad thing, it somewhat decreases security.

## Building

To build Paragon, you will need `lua` 5.3 or newer\*, a VT100-compatible terminal, and a Unix-like shell. It may be easiest to build on Linux or MacOS. Run `lua build.lua` and follow the prompts.  Passing `-d` will omit prompts and include everything.


*\* Lua 5.0, 5.1, and 5.2 may work but are unsupported and untested.*

## Documentation

Documentation is available in the `docs` folder of this repository.
