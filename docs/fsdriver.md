# Filesystem Drivers

The Paragon kernel has natively integrated support for unmanaged filesystem and partition-table drivers, with some limitations.

Drivers should set `k.drv.fs["FS_NAME"]` to a library whose sole function is `create(partition_proxy:table)`.  This function should return an **object** whose methods correspond to those of the `filesystem` component, excepting the addition of `fsobject:stat(file:string)` and the omission of `fsobject:exists()`.  This function should return `{permissions=number, isDirectory=boolean, owner=number, group=number, lastModified=number, size=number}`.  Partition table drivers should behave similarly, excepting that their sole `create()` function should return an object on which `:partition(start:number, end:number)` may be called to return an emulated `drive` component limited to the specified sectors.
