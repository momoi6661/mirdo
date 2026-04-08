# Errors

## [ERR-20260408-001] godot-remote-executor executor-id stale

**Logged**: 2026-04-08T09:30:19.5739572+08:00
**Priority**: medium
**Status**: pending
**Area**: tooling

### Summary
POST /api/execute failed because executor_id became stale after editor reconnect.

### Error
`
No connected Hastur Executor matched the query
`

### Context
- Operation: execute remote GDScript via broker-server
- Cause: Godot reconnection changed executor id

### Suggested Fix
Always query /api/executors immediately before execute and use latest id.

### Metadata
- Reproducible: yes
- Related Files: n/a
- Tags: godot-remote-executor, hastur, executor-id

---
## [ERR-20260408-002] bunker_local_pbr invalid subresource id

**Logged**: 2026-04-08T09:37:28.6812635+08:00
**Priority**: high
**Status**: pending
**Area**: config

### Summary
PBR scene parse failed because node referenced non-existent SubResource id.

### Error
`
Parse Error: Invalid parameter. [Resource file res://levels/bunker_local_pbr.tscn:9858]
Condition "!int_resources.has(id)" is true.
`

### Context
locker_door_006 mesh was set to SubResource("ArrayMesh_so8p1"), but this id no longer exists in file.

### Suggested Fix
Before changing SubResource("...") in .tscn, verify target id exists in same file. If not, switch to existing mirror variant id.

### Metadata
- Reproducible: yes
- Related Files: levels/bunker_local_pbr.tscn
- Tags: godot, tscn, parse-error, subresource

---
## [ERR-20260408-003] gdscript snippet local-func parse error

**Logged**: 2026-04-08T10:21:14.0691943+08:00
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
Remote snippet compile failed because a helper function was declared inside snippet body.

### Error

Parse Error: Standalone lambdas cannot be accessed. Consider assigning it to a variable.


### Context
- Operation: execute GDScript snippet via Hastur broker
- Cause: declared unc apply_door(...) inside snippet run body

### Suggested Fix
Keep remote snippets flat (no nested function declarations); inline repeated logic or switch to full-class mode.

### Metadata
- Reproducible: yes
- Related Files: levels/bunker_local_pbr.tscn
- Tags: gdscript, remote-executor, parse-error

---
## [ERR-20260408-004] gdscript snippet local-func parse error (repeat)

**Logged**: 2026-04-08T10:40:14.0375519+08:00
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
Again hit compile error when using a local helper unc inside remote snippet code.

### Error

Parse Error: Standalone lambdas cannot be accessed. Consider assigning it to a variable.


### Context
- Operation: execute GDScript snippet in Hastur remote executor
- Trigger: tried to define helper function in snippet body for repeated door updates

### Suggested Fix
Keep snippet scripts flat; avoid local function declarations. If reuse is needed, switch to full class mode with xecute().

### Metadata
- Reproducible: yes
- Related Files: levels/bunker_local_pbr.tscn
- Tags: gdscript, hastur, snippet, parse-error
- See Also: ERR-20260408-003

---

## [ERR-20260408-005] ripgrep binary access denied

**Logged**: 2026-04-08T11:05:00+08:00
**Priority**: medium
**Status**: pending
**Area**: tooling

### Summary
`rg.exe` could not start in this Codex desktop environment because of an access denied error.

### Error
Program 'rg.exe' failed to run with working directory 'D:\AAgodot\FPS': access denied.

### Context
- Operation: recursive text search in workspace
- Command: `rg -n "MOUSE_MODE_CAPTURED|mouse_mode|capture|captured" -S`
- Environment: Codex desktop bundled ripgrep path under WindowsApps

### Suggested Fix
Fallback to `Get-ChildItem` + `Select-String` when `rg` fails with access denied in this environment.

### Metadata
- Reproducible: yes
- Related Files: n/a
- Tags: tooling, ripgrep, powershell, access-denied

---
## [ERR-20260408-005] godot-remote-executor executor-id stale (repeat)

**Logged**: 2026-04-08T11:14:31.7055057+08:00
**Priority**: medium
**Status**: pending
**Area**: tooling

### Summary
Remote execute failed because connected executor id changed after editor reconnect.

### Error

No connected Hastur Executor matched the query


### Context
- Operation: POST /api/execute
- Previous executor id became invalid after reconnect

### Suggested Fix
Always query /api/executors before execute calls and use latest id.

### Metadata
- Reproducible: yes
- Related Files: n/a
- Tags: godot-remote-executor, hastur, executor-id
- See Also: ERR-20260408-001

---
## [ERR-20260408-006] godot-remote-executor NodePath concat parse error

**Logged**: 2026-04-08T11:48:00+08:00
**Priority**: low
**Status**: pending
**Area**: tooling

### Summary
GDScript snippet failed to compile when concatenating `NodePath` directly with `String`.

### Error
Parse Error: Invalid operands "NodePath" and "String" for "+" operator.

### Context
- Operation: POST /api/execute
- Script attempted `n.get_path() + " | E=" + str(...)`
- Godot 4.6 remote snippet compile in Hastur executor

### Suggested Fix
Always wrap node paths using `str(n.get_path())` before string concatenation in remote snippets.

### Metadata
- Reproducible: yes
- Related Files: n/a
- Tags: godot-remote-executor, gdscript, parse-error, nodepath
- See Also: ERR-20260408-005

---
