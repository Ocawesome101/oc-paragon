# px: Paragon eXecutable

The Paragon eXecutable is a signed executable format used in Paragon.  It provides signatire validation and hashing.

Note that support for `.px` files is completely unimplemented.  This file should be disregarded.

```
+------------------------------------------------+
| Paragon eXecutable Header Format               |
+--------+---------------------------------------+
| Bytes  | Description                           |
+--------+---------------------------------------+
| 1-8    | .px header - \27PEXEC\13\27 - 8 bytes |
+--------+---------------------------------------+
| 9-32   | Signer - 24 bytes                     |
+--------+---------------------------------------+
| 33-64  | Data signature, ec25519 - 32 bytes    |
+--------+---------------------------------------+
| 65-96  | Data hash, SHA3-256 - 32 bytes        |
+--------+---------------------------------------+
| 97-100 | Executable flags - see 'flags'        |
+--------+---------------------------------------+
| 100+   | Executable data                       |
+--------+---------------------------------------+

+------------------------------------------------+
| Flags                                          |
+--------+---------------------------------------+
| Flag   | Meaning                               |
+--------+---------------------------------------+
| 0x01   | The executable is compressed with     |
|        | LZSS.                                 |
+--------+---------------------------------------+
| 0x02   | The executable is unsigned and the    |
|        | signature is invalid.                 |
+--------+---------------------------------------+
| 0x04   | The executable's signer is anonymous. |
+--------+---------------------------------------+
```
