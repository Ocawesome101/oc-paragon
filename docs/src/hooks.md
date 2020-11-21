# hooks

Provides the kernel hook interface.  Used heavily in sandbox creation.

  - `k.hooks.add(k:string, v:function): boolean` - call `v` on action `k`
  - `k.hooks.call(k:string, ...)`: call action `k` with args `...`
