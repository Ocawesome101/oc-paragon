# hostname.lua

Provides system hostname facilities.

  - `h.set(hn:string): boolean or nil, string` - calls the kernel hook `hnset`.  Only root can do this.
  - `k.get(): table` - calls the kernel hook `hnget` and returns the resulting table.
