# sounds/ — Fase 2 SFX + ambient (game repo, untracked binaries)

Every file below is **CC0 (public domain)** sourced from OpenGameArt.org
(direct file links, no account). License badge `cc0.png` verified on each
asset page at download time (2026-09-20). Binaries stay **uncommitted**
until the coordinator says otherwise; this registry is the paper trail.

Original filenames are kept in the "Source file" column so anyone can
re-download and verify.

| Game file | Source file | Asset page | Author | License |
|---|---|---|---|---|
| sfx_rifle_blast.wav | sounds/sks.wav (ex sounds.zip) | https://opengameart.org/content/gunshot-sounds | Tabasco | CC0 |
| sfx_rifle_mech.mp3 | ShotgunSounds/Shell in Chamber.mp3 (ex shotgunsounds.zip) | https://opengameart.org/content/shotgun-reload-sound-effects | zer0_sol | CC0 |
| sfx_rifle_tail.wav | Black Powder.wav | https://opengameart.org/content/gunshots | kurt | CC0 |
| sfx_reload_mag_out.mp3 | ShotgunSounds/First Shell.mp3 (ex shotgunsounds.zip) | https://opengameart.org/content/shotgun-reload-sound-effects | zer0_sol | CC0 |
| sfx_reload_mag_in.mp3 | ShotgunSounds/Subsequent Shells.mp3 (ex shotgunsounds.zip) | https://opengameart.org/content/shotgun-reload-sound-effects | zer0_sol | CC0 |
| sfx_reload_charging.mp3 | ShotgunSounds/Rack.mp3 (ex shotgunsounds.zip) | https://opengameart.org/content/shotgun-reload-sound-effects | zer0_sol | CC0 |
| sfx_impact_flesh.ogg | qubodupImpact/qubodupImpactMeat01.ogg (ex qubodupImpact.7z) | https://opengameart.org/content/impact | qubodup | CC0 |
| sfx_impact_steel.wav | clink2.wav | https://opengameart.org/content/metal-impact-sounds | BMacZero | CC0 |
| sfx_step_concrete.ogg | 01-footstep.ogg | https://opengameart.org/content/footsteps-0 | GboxMikeFozzy | CC0 |
| sfx_step_dirt.ogg | 04-footstep.ogg | https://opengameart.org/content/footsteps-0 | GboxMikeFozzy | CC0 |
| sfx_ui_click.wav | click1.wav (ex UI_SFX_Set.zip, Kenney Vleugels kenney.nl) | https://opengameart.org/content/51-ui-sound-effects-buttons-switches-and-clicks | Kenney | CC0 |
| amb_wind_loop.mp3 | winter-wind.mp3 | https://opengameart.org/content/winter-wind | wipics | CC0 |

## Layering notes (how the game uses them)

- Rifle shot = 3 layers on `cartridge_fired`: mech (metallic clack, 0 ms),
  blast (SKS rifle, 0 ms), tail (black-powder decay, +120 ms, quieter).
- Reload = 3 staged one-shots across the 2.2 s reload: mag out @ 0.3 s,
  mag in @ 1.2 s, charging handle @ 1.9 s (see `sounds/game_audio.gd`).
- Steps: concrete/dirt are two takes from the same CC0 subway-footsteps
  set (no per-surface CC0 set found; honest variants, surface routing later).
- Wind: stereo mp3 looped on the Ambient bus in the arena only.

## Derived cues (no new downloads)

- Weapon malfunction: the `sfx_rifle_mech` mechanism voice, pitched down per kind
  (FEED_FAILURE 0.70, STOVEPIPE 0.82, MISFIRE 0.60) — `GameAudio.play_malfunction(kind)`.
- Malfunction cleared: `sfx_reload_charging` rack at pitch 1.15 —
  `GameAudio.play_malfunction_cleared()`.
  Both are wired to `Weapon.weapon_malfunctioned` / `Weapon.malfunction_cleared` in
  `scenes/arena_manager.gd::_track_weapon`.

## Rejected (license, not CC0)

- `foot-walking-step-sounds-on-stone-water-snow-wood-and-dirt` (qubodup) — GPL badge, skipped.
- `cc0-sound-effects` (OwlishMedia) — no verifiable license badge, skipped.
