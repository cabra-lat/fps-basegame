---
description: Verify the range plays correctly — import check, scripted GPU run, filmstrip plus GIF evidence.
---

Run the full verification loop for the scene in $ARGUMENTS (default `res://scenes/debug_range.tscn`) and report PASS/FAIL with evidence paths. Do not leave temp files behind.

1. Parse check: `godot --headless --path . --import` — must be error-free (ignore the benign `ScopeViewport` editor-layout lines).
2. Write a temporary `extends SceneTree` runner at `addons/cabra.lat_shooters/test/spot_tmp.gd` that loads the scene, drives it (walk, fire taps, reload hold ~4s), saves frames to `/tmp/shooter/frm_*.png`, then quits. It must force `Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)` every frame so it never hijacks the cursor.
3. Run it invisibly on the NVIDIA card: `DISPLAY=:99 nix shell nixpkgs#virtualgl -c vglrun -d :0 godot --path . --resolution 1280x720 --script addons/cabra.lat_shooters/test/spot_tmp.gd` (Xvfb on `:99` must be up; start with `Xvfb :99 &` if not).
4. Assemble `/tmp/shooter/spot.gif`: `nix shell nixpkgs#ffmpeg -c ffmpeg -y -framerate 8 -pattern_type glob -i '/tmp/shooter/frm_*.png' /tmp/shooter/spot.gif`.
5. Delete the temp runner. Report: shots/hits/reload lines from the log, the GIF path, and any ERROR lines (the known `%CollisionShape3D` one is pre-existing — say so instead of alarming).
