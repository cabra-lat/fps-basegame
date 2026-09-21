# Medical & provision items (Fase 1 survival)

Data provenance: values mirror the local wiki mirror infoboxes
(`../tarkov-wiki/pages_wikitext/<Item>.wikitext` — CC-BY-SA). The mirror is a
reference-only repo and gets re-scraped, so the mapping lives here instead of
being written back into it. Effects are implemented by
`addons/cabra.lat_shooters/src/core/health/medical_item.gd` (applied after
`use_time` seconds by `PlayerController.start_use()`).

| Resource (`resources/medical/`) | Wiki page | mass | grid | use time | effect used |
|---|---|---|---|---|---|
| `army_bandage.tres` | Army_bandage | 0.043 kg | 1x1 | 2 s | stops light bleeding |
| `cat_hemostatic_tourniquet.tres` | CAT_hemostatic_tourniquet | 0.08 kg | 1x1 | 3 s | stops heavy bleeding, leaves a fresh wound |
| `aluminium_splint.tres` | Aluminum_splint | 0.22 kg | 1x1 | 3 s | fixes fracture |
| `analgin_painkillers.tres` | Analgin_painkillers | 0.01 kg | 1x1 | 3 s | pain relief 120 s |
| `cms_surgical_kit.tres` | CMS_surgical_kit | 0.4 kg | 2x1 | 16 s | restores one destroyed part, HP penalty 35% |
| `salewa_first_aid_kit.tres` | Salewa_first_aid_kit | 0.6 kg | 1x2 | 3 s | heals 85 HP/use (2 uses), stops light+heavy bleeding |
| `ai2_medkit.tres` | AI-2_medkit | 0.135 kg | 1x1 | 2 s | heals 50 HP |
| `can_of_condensed_milk.tres` | Can_of_condensed_milk | 0.44 kg | 1x1 | 4 s | +75 energy, -65 hydration |
| `bottle_of_water.tres` | Bottle_of_water_(0.6L) | 0.65 kg | 1x2 | 3 s | +60 hydration |

Not modelled (no wiki page in the mirror, out of Fase 1): stims, antibiotics,
hydration tablets, radiation. `Surv12` (fracture + 1 destroyed part) is a direct
extension of `cms_surgical_kit` if needed.

## Survival numbers

`PlayerSurvival` (`addons/cabra.lat_shooters/src/player/survival.gd`) owns
stamina / energy / hydration / encumbrance. Reference points: overweight starts
at 24 kg (survey §6 says Tarkov ~22-25 kg), Endurance gives +1 %/level stamina
and Strength -1 %/level jump cost (`endurance_level` / `strength_level` hooks —
the skills system itself is Fase 3/4). Stamina pool 100, sprint drain 9/s
scaled by weight, jump cost 18, regen 14/s after a 1.2 s delay, sprint blocked
below 15 and while exhausted. Energy drains 0.05/s and hydration 0.07/s
(x3 while sprinting); empty pools cause attrition damage.
