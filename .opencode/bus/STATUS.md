# Bus STATUS — board

Fonte de verdade para **claims** e para o **estado atual**. Histórico vive no AMQ, não aqui.
Agentes: `coordinator`, `ballistics`, `player-rig`, `range`, `npc-body`, `meta`, `testkit`, `spotter`, `qa`.
Protocolo: AGENTS.md regra 7 (drenar → claim → **responder ao remetente** → relato em 5 partes).

## EM VOO (claimed)

| Item | Dono | Estado |
|---|---|---|
| **Commit da lane range** (gunsmith UI + hook + `mod_weapon`) | range | **CLAIMED by range 2026-09-21T16:04Z** — em curso |
| **Facção como DADO** (supersede o rename PMC/SCAV: `resources` + registry, `PlayerProfile.faction` = String id, `ExtractionPoint.allowed_factions`) | range | **CLAIMED by range 2026-09-21T16:04Z** — supersede a ordem de rename do coordinator (msg `2026-09-21T15-53-08`); depende de 1 linha em `src/meta/meta_profile.gd` (lane meta) + clear do dir `resources/meta/factions/` |
| Fila player-rig: stealth (ruído → audição da IA), sway por ergonomia | player-rig | fila |
| **Mercado alcançável** (ligação mínima na arena: ponto de compra/venda + `offer_line()` no HUD) | meta → range | **DONE (range) 2026-09-21** — re-verificado por meta **15/15**; **spotter VERIFICOU 2026-09-21T14:30Z** (claim D na arena real: interact→painel→`offer_line()`→buy/sell→reload, 23/23 + captura `spot_market_panel.png`); evidência `/tmp/shooter/spot_arena_verify.txt` |
| **Flea market** (listings + taxa + escrow + expiração por contador de raids) | meta | DONE self 35/35; **pré-condição do guardrail 1 satisfeita** — **spotter VERIFICOU 2026-09-21T14:30Z** (HEAD `7d8b7b0`): atomicidade+quarentena (28 SIGKILL no meio da escrita, save sempre íntegro), escrow por **massa real**, economia exata (fee/piso, fair-price, barter, stock reset, seguro); 50/50 lógica + 28 SIGKILL; evidência `/tmp/shooter/spot_meta_verify.txt`, `spot_kill_verify.txt` |
| **Commit da lane do meta** (destrava CI) | meta | **DONE 2026-09-21T14:04Z** — HEAD **`50ab5ce`**: `src/meta` (52, validators + `.uid` + MetaService), `resources/meta` (7), `resources/medical` (9, dependência dos gates market/flea) e **só** a linha `Meta` autoload em `project.godot` (`MCPBridge` NÃO entrou). `c091a74` foi resetada pela própria lane que a criou (`84db948`). Gates: persistence 38/38 · progression 34/34 · market 45/45 · flea 35/35. Achado ao testkit: `.godot/` compartilhado + `godot --import`/harness concorrente gera **falso-FAIL** (uid cache stale, 7/45); serializar o CI |
| `tools/verify-all` (ponto único: import + harnesses + gate de qualidade, com exit code) | testkit | **DONE — RED honesto**: `uid_tracking` checa **HEAD** (clone limpo), não o index: **32 scripts do addon sem `.uid` commitado** (os `.uid` existem no disco, mas foram UNSTAGED). Fecha quando forem commitados. Risco (b) **FECHADO** (`inventory-ux` commitou o harness `7d12d0f`, 62/62). **BLOQUEIO ESTRUTURAL (do `meta`, confirmado por mim)**: o HEAD do jogo não tem gitlink nenhum, então um clone limpo NÃO tem `addons/` e o verify-all não roda — agora falha com um PREFLIGHT claro (`f7a8730`) em vez de "Can't load script". Fix = infra (commit dos gitlinks ou CI clonando cada addon). Commits meus: `3e98608` (addon), `36d0fe7`+`45e276b`+`5961118`+`f5b54f4`+`7d8b7b0`+`55aa423`+`f7a8730`+`70e455a` (jogo) |
| Re-validar QA-001/QA-002 + auto-limpeza dos achados manuais no gate | qa | DONE 2026-09-21T11:17Z — QA-001/QA-002 RESOLVED (probes próprios em `tools/qa/probes/`); `--verify-manual` + `ignore.json`; matcher corrigido (3 classes morto-real/consumidor-pendente/falso-positivo); baseline v2.1.0, `--check` exit 0 (0 BLOCKER / 99 MAJOR) |
| **Audit pass pós-fixes: tool gating + baseline** | qa | **DONE 2026-09-21T13:59Z** — `debug-print` agora ignora prints sob `if OS.is_debug_build():` (falso-positivo que mantinha `arena_manager`/`debug_range` como MINOR); confirmados 6 itens do range (4 LIGAR com consumidor real, 2 campos mortos removidos) e os 2 BLOCKER do ballistics; baseline v2.1.0 re-snapshot deliberado **0/57/44/16**; `--check` exit 0 e import gate exit 0 (2 runs). Re-verificados 9 manuais do player-rig (QA-005 e **falso-positivo** confirmado; QA-008/009/014/015/016/017/018/024 resolved) -> atual **0/55/38/15**; QA-003 reatribuido player-rig -> ballistics e RESOLVED (addon `ea41124`: early-return `if freeze` antes das forcas -> regra 5); QA-010 RESOLVED (tree), QA-020/021 RESOLVED (addon `cf68d56`) -> atual **0/54/38/15**; spin-out cosmético QA-025 (ballistics, 6 headers) RESOLVED addon `ef4ebda` + QA-026 (player-rig, 3) RESOLVED (tree) -> ledger manual **27/27 resolved, 0 abertos**; baseline **0/51/37/14** mantido (nao aceitei o +1). range dedup: `_tick_footsteps` e o bloco de 20 linhas cairam, MAS o refactor de `_resolve_shot` expoz 2 duplicacoes reais (`arena_manager.gd:616===debug_range.gd:110` e `:629===:121`) -> range fechou a dedup arena<->debug_range: `ShotResolver.resolve` + `ShotResolver.apply_hit` (HitFlash.spawn/range_hit/audio/loot) compartilhados; `duplication` 2 -> 1 (so `cartridges_3d.gd:198===:219`) -> MAJOR 50, `--check` exit 0; baseline re-snapshotado **0/50/37/14**. `cartridges_3d.gd` (orfao, 1007 linhas) **DELETADO (range, autorizado)** -> `duplication` 0, god-object 3->2 -> MAJOR 48; baseline re-snapshotado **0/48/36/14**, `--check` exit 0. **Lane qa COMMITADA 94c42a5 + fbdcab1** (`tools/qa/*` + `docs/qa-baseline.json`) sob autorizacao do usuario -> gate 8 nao falha mais rc=3 em clone limpo; `fbdcab1` corrige o baseline p/ guardar o **vocabulario de 39 regras** (antes guardava so as que disparavam, o que perdoava regressao de MAJOR como 'taxonomy change') |
| Dívida de qualidade roteada pelo `qa` (por dono) | todos | em curso |
| **Dívida QA do player-rig** (QA-005/008/009/014/015/016/017/018/024/026 + ip-tarkov + icon default) | player-rig | **fix aplicado, RE-VERIFICADO pelo `qa` (ledger manual 0 abertos, 26/26 resolved)** — QA-008/009/014/015/016/017/018/024/026 + ip-tarkov corrigidos; + default de `Item.icon` trocado de `res://icon.svg` (logo Godot) para o placeholder gerado (`item.gd:10`, pedido do `inventory-ux`); **QA-005 = falso positivo** (`.mass` já faz dispatch p/ `get_mass()`, coberto por INV-06; QA-009 virou INV-11, commit `53f178c`); QA-003 fechado pelo `ballistics` (`ea41124`); **working tree do player-rig NÃO commitado** — aguarda o coordinator liberar o commit da leva |
| ~~**BLOQUEIO cross-lane: gate `uid_tracking`**~~ | coordinator (dono do .uid) | **RESOLVIDO 2026-09-21T14:2xZ** — a lacuna do índice fechou: `git ls-files` do addon agora cobre 109 scripts / 110 `.uid` (**0 sem `.uid`**; 36 `.uid` de outras lanes stageados). A lane player-rig (`src/core/inventory/**` + `src/core/item.gd`, 7 `.uid`) saiu primeiro. Nota: a linha do `testkit` (#15) ainda dizia 32 — ficou defasada |
| **Hook gunsmith (inventário → "Modificar" → UI)** | player-rig + inventory-ux + range | **DONE end-to-end 2026-09-21T15:45Z** — `PlayerController`: `signal weapon_modify_requested` + `func request_weapon_modify()`; `inventory-ux`: "Modificar" id 105 → `main.gd` → `player.request_weapon_modify` (parse 149/0); **`range` VERIFICADO**: arena `close_inventory()` → `open_for_weapon` (5/5 PASS, import 0, arena+debug_range bootam). Não commitado (leva do player-rig) |
| Verificação: pitch (#2), IA (#3), quests/skills no caminho REAL (#4) | spotter | **#2 DONE**, **#4 strength RESOLVIDO 2026-09-21T14:43Z** — `Input.action_press` no caminho REAL (arena_blockout) dirige o player: 5/5 runs, 5.1–6.0 m, strength xp 0→1 (casa com 0.2 xp/m), persiste no readback. **Achado:** o "não anda" anterior era **bot congelado no caminho** (`Bot3`, `test_move blocked=true`), não o método de input — remover a colisão dos bots, não só parar o physics. Evidência `/tmp/shooter/spot_strength_verify.txt`. **#3 (profundidade de IA) pendente** |
| Verificação PITCH da câmera (#2) | spotter | DONE 2026-09-21T11:09Z — 7/7 PASS (pitch -3/+3, clamp ±90, yaw ok; POI nivel 15m / baixo 4.18m / alto 10.14m; dot 0px a ±35°; ray segue o forward, resolve no Ground a 1.62m em -89°, não no corpo; lean 0.45m). Evidence /tmp/shooter/spotpitch*, report_pitch.md |
| `validate_invariants.gd` (**16** invariantes/checks cruzados permanentes) | testkit | **DONE, +INV-11 14:2x, +INV-12/13/14/15 14:4x** — **16/16 PASS** headless; gate 9 do verify-all. Prova de sabotagem INV-07 (exit 1); INV-11 (QA-009) a pedido do `qa`; INV-12/13/14/15 (save atomicity+quarantine, escrow por **MASSA**, expiry pelo raid counter, piso da fee) promovidos do probe do `meta` — sabotagem do INV-13 provada (escrow sem `take_from_stash` mantém 3.5 em vez de 0.0). Commits `3e98608`+`53f178c`+`b795351` (addon) + `36d0fe7` (jogo) |
| Ícones gerados dos modelos + UI/UX tetris do inventário | inventory-ux | **DONE 2026-09-21T12:43Z** — game: gerador+assets `f2dbfa4`, wiring dos 118 `.tres` `ea7967f`; addon: núcleo tetris (rotate/swap/stacking) + `tooltip.gd` + harness `7d12d0f` (62/62, gate `inventory_ux` fecha em clone limpo). 61 ícones reais + 57 placeholder documentado, 0 logo do Godot; `qa_audit` BLOCKER=0. UI: rotação/swap/stacking/aninhamento/quick-move/peso-tooltip + item **"Modificar"** no context menu da arma → `player.request_weapon_modify` (gunsmith do `range`), GPU frame OK. Pendente p/ coordinator: UI em tela (`src/ui/inventory/{container,main,slot,item,base}.gd` + `equipment.tscn`) e os `.uid` restantes (`uid_tracking`) |
| **Commit ballistics lane + .uid fix** | ballistics | **DONE 2026-09-21T13:52Z** — addon `9496847` (track .uid + ammo test arity fix), game `b8f1f5f` (ammo/armor UID repoint + 12ga); assets 123/123, ballistics 40/40 |
| **QA-003** (held weapon recoil, rule 5) | ballistics | **DONE 2026-09-21T14:11Z** — addon `ea41124`: `_apply_recoil` early-returns when `freeze` (held body); casing ejection untouched; `weapon_3d.gd.uid` tracked; other lane's uncommitted changes preserved via targeted stash; `check_scripts.gd` exit 0 (working tree) |
| **QA-020/021 NITs** | ballistics | **DONE 2026-09-21T14:17Z** — addon `cf68d56`: `##` docstrings in `item_3d.gd:78` + `cartridge_3d.gd:9/14`, corrected `calculator.gd:1` header; tracked both world `.uid`; parse gate 145 scripts / 0 failures |
| **QA-025 NITs** (6 stale addon headers) | ballistics | **DONE 2026-09-21T14:21Z** — addon `ef4ebda`: fixed headers in attatchments/firemode/reservoir/ammo_feed/utils/caliber_parser; tracked 4 untracked `.uid`; `attatchments.gd` isolated via targeted stash; parse gate 145 scripts / 0 failures |
| **Commit player-rig lane + .uid fix** | player-rig | **DONE 2026-09-21T13:56Z** — addon `ce68fda` (ViewmodelRig frozen-body gun pose, PlayerSurvival, body visibility/near-clip, remove `*.uid` from `.gitignore` + track 14 player `.uid`); verify-all --quick PASS (0 parse errors, 143 scripts, 123 assets) |
| **BLOQUEIO: HEAD tinha 15 weapons que não carregavam** (paths de script antigos + `ammofeed`) | ballistics (fix) + inventory-ux (icones) | **RESOLVIDO 2026-09-21T14:50Z, verificado por meta 14:51Z** — game repo `c35c780`: 15 `.tres` repontados para `src/core/weapon/weapon.gd` / `src/core/ammo/ammo_feed.gd` + `ammofeed` -> `ammo_feed`; split "worktree − icon" via `/tmp/shooter/strip_icon.awk`, icons da inventory-ux ficaram no working tree (não commitados); weapon_mechanics PASS, assets 123/123; **meta copiou o HEAD pós-commit e mediu CHK_SUMMARY checked=15 load_null=0 feed_null=0** |
| **Varredura de paths/typos em `resources/**/*.tres`** | ballistics | **DONE 2026-09-21T14:54Z** — `ea7967f` (inventory-ux) carregou também 15 repoints de `attachment.gd` -> `attachment/attatchments.gd` (conteúdo verificado correto pelo meta); scan de todos os `resources/**/*.tres`: 0 paths `.gd` referenciados ausentes no disco, 0 `ammofeed`/paths antigos de core restantes |

| **Leva do ADDON da `inventory-ux` ainda fora do HEAD** (harness `validate_inventory_ux.gd` + `.uid`, `grid/container/item`, UI `main/container/slot/item`, `equipment.tscn`) | inventory-ux | **ABERTO — inventário exato medido pelo `meta` 2026-09-21T15:02Z**: dos **9** gate scripts que o `verify-all` chama, **este é o único não rastreado** (`tools/verify-all.sh:296`; o `.gd` existe no disco com `.uid`, nenhum dos dois no HEAD do addon) → clone limpo falha o gate. E commitar só o harness **não** fecha: `rotate_item` (`container.gd:98`) e `swap_items` (`:109`) existem **só no working tree** (`git -C addons/... show HEAD:src/core/inventory/container.gd` não tem nenhum). `.uid`: addon HEAD 99 `.gd` / **27 sem `.uid`** (era 35; caindo), jogo 64 `.gd` / 0. Mesma classe do que acabou de fechar: arquivo rastreado dependendo de código não rastreado. Separado do lote de `.tres`+assets (que já é atômico por construção) |

| **BLOQUEIO ESTRUTURAL DE CI: addons não estão commitados como gitlinks** | coordinator / infra | **ABERTO — achado pelo `meta` 2026-09-21T15:0xZ, medido em clone limpo** — `.gitmodules` declara 4 submodules, mas o HEAD **não tem nenhuma entrada de gitlink** (`git ls-tree HEAD \| grep addons` → nada; `git submodule status` → vazio; `git ls-files addons` → 0). Logo o passo do CI `git submodule update --init --recursive --depth 1` é **no-op** e o clone fica **sem `addons/`**: medi com `git clone` real → sem `addons/`, e o próprio script do gate 1 (`addons/cabra.lat_shooters/test/check_scripts.gd`) não existe ⇒ `verify-all` falha antes de qualquer harness. Ou seja: **o job `gates` do CI não tem como passar**, independentemente de token/`.uid`/refs. Duas saídas: (a) commitar os gitlinks (`git submodule add <url> <path>` / `update-index --add --cacheinfo 160000,<sha>,<path>`) — pina SHA do addon e exige commit de bump a cada mudança; (b) trocar o CI para `git clone` de cada addon na ref desejada (com token), sem pin. `src/meta/meta_service.gd` **está** no clone (a lane do meta não é afetada). **PRÉ-REQUISITO adicional medido pelo `meta` 15:1xZ**: **nada de hoje foi pushed** — o addon `cabra.lat_shooters` está **9 commits à frente** do `origin/main` (`7d12d0f` vs `843bb25`) e o **repo do jogo 15 commits à frente**; os outros 3 addons estão em sincronia. Logo a opção (a) **não funciona antes do push do addon** (o SHA pinado não existe no remote → o clone do CI falha no fetch), e a (b) pegaria um addon antigo. Ordem: push do addon → (a) ou (b). Push é do usuário/coordinator (regra 1). `testkit` já tornou a falha honesta com o preflight (`f7a8730`, medido: FATAL + exit 1 em 0s em clone sem addons). |

## VERIFICADO (implementação + verificação independente)

**Movimento** — walk/sprint/crouch/prone/jump/queda; **lean que faz peek de verdade** (câmera translada
0.45 m com clamp de 0.20 m na parede; roll 8° secundário; corpo inclina 10°).

**Câmera / corpo em primeira pessoa** — pitch chegando ao rig da câmera (clamp exato ±90°, yaw
intacto) validado **com POI por inclinação**: nivelado 15 m, para baixo 4.18 m, para cima 10.14 m, com
o raio do resolver casando com o da câmera nos três. Dot a 0.0 px em ±35°. Corpo: **split por OSSO**
(`BodyMeshSplit`, cabeca+pescoco em malha propria na layer 4 = fora da camera FPS, PiP mostra tudo;
buffer de vertices compartilhado, pesos intactos) — sem cabeca/nuca/rosto na vista FPS e sem interior
de cranio, braco+arma visiveis a pitch 0. Cutoff de distancia reduzido a 0.05 (so near plane).
**Limitacao de asset em aberto**: a malha e de 3a pessoa e o TORSO volumoso oclui os pes quando se olha
para baixo — decisao de design do coordinator (aceitar / esconder o tronco tambem / re-autorar).
O tiro **nao** acerta o proprio corpo em pitch extremo (raio ingenuo acertava o `TorsoAttachment` a
0.51 m; com as exclusoes nao). *Nota de cobertura: toda verificacao de mira/POI/ADS deve declarar o
pitch usado — as antigas, todas a pitch 0, eram corretas e incompletas.*

**Gunplay** — 18 armas, 50 munições, 23 armaduras, 15 attachments. **Recht-Ipson** `Er=max(0,Eh−Ebl)`
+ **Poncelet** `P=K·ln(1+E/E1)` + LOS `t/cos θ`. Cert tables decidem o stop, física é fall-through.
Placas em camadas, destrutibilidade por material, mínimo 1 de durabilidade por projétil, reparo que
corta a durabilidade máxima. **Multi-projétil real** (buckshot = N projéteis, cada um rolando
armadura/dano/sangramento). **ADS com POI=POA a 15/30/50 m** (M4 e AK), alinhamento derivado do sight
marker. **Falhas de arma** (feed/stovepipe/misfire por munição × desgaste), limpeza com tempo por tipo
(tecla X), desgaste por tiro, ergonomia no tempo de ADS.

**Sobrevivência** — stamina (dreno por peso, gate de sprint, tremor), peso real (o wrapper não copiava
massa: tudo pesava 0), sangramento leve/pesado que **mata**, fratura persistente (só splint), dor +
analgésico, membro preto + cirurgia, energia/hidratação, HUD de status.

**IA** — percepção (**cone 110°** + **audição 30 m** + estados IDLE→SUSPICIOUS→ENGAGED→SEARCH),
cobertura que escolhe ponto bloqueando LOS, **squad** com blackboard por time, saque de loot (só marca),
**tiers** RECRUIT/REGULAR/VETERAN (reação 30 vs 6 frames), times + waves + friendly-fire, debug visual.

**Modos e loop de raid** — `GameMode` plugável (FFA/TDM, placar e win condition por modo); raid com
timer, **6 tipos de extração** (instantânea, paga V-Ex, flare, alavanca, co-op, timed) com facção,
single-use e item exigido; outcomes **SURVIVED / RUN_THROUGH (<7 min e <200 EXP) / MIA / KIA**;
**raid event bus**.

**Persistência** — stash + perfil com save **versionado e atômico** (temp+rename, quarentena `.corrupt`),
autoload único `Meta` como autoridade. **Verificado cross-process**: extrair com itens sobrevive a
fechar o jogo; **KIA deixa o stash byte-idêntico** e perde o loadout. Extração paga gasta a **carteira
persistente**. "Voltar ao menu" não perde o save.

**Progressão** — skills use-based nos ganchos existentes (`endurance_level`/`strength_level` chegam ao
survival), persistidas; quests data-driven consumindo o bus, com **RUN_THROUGH não contando** objetivo
de extração e recompensa caindo no perfil/stash. **Traders** com loyalty (nível+reputação), barter,
recusas claras, reputação por trade/quest e **seguro** (manifesto, devolução após prazo, exclusões).

**Apresentação** — menu + settings (sensibilidade, volumes por bus, pixelização PS1), inventário com
tooltip e quick-equip, HUD sem crosshair (mira nas ópticas), áudio unificado (12 SFX CC0, buses+pools,
`master.sh`), consistência visual (`shared_env`/`shared_ground_material`/`hud_style`). Perf: HUD 10 Hz,
flash cacheados, ShotRay com rescan fora do per-shot — ~18-21 ms com 3 bots em VGL/940MX.

**Entrega** — `export_presets.cfg` (Linux/X11 + Windows), export headless **funcionando** (Linux ~121 MB,
Windows ~155 MB, smoke exit 0), templates de export no `flake.nix` (devShell linka), CI com job de gates
sempre e export condicional (submódulos privados exigem token). README de framework.

**Qualidade** — `validate_assets` (123), `validate_tarkov_ballistics` (40), `validate_weapon_mechanics`
(41), `validate_meta_persistence` (38), `validate_meta_progression` (34), `validate_meta_market` (42),
`validate_meta_flea` (34);
`tools/qa/audit.mjs` com gate
por severidade; `tools/amq-herdr-bridge.mjs` fechando entrega.

## DÍVIDA CONHECIDA (do `qa`; baseline v2.1.0: **BLOCKER 0** / MAJOR 99 / MINOR 51 / NIT 19)

Gate: `node tools/qa/audit.mjs --check` (exit 1 só com BLOCKER; exit 2 se MAJOR subir do baseline).
**Política de baseline:** o baseline commitado é a referência e o CI compara contra ele — re-baselinar é
ato deliberado (junto com a decisão de aceitar a mudança), nunca automático. Taxonomia em 3 classes:
`morto-real` → dívida/MAJOR · `consumidor-pendente` → informativo com dono · `falso-positivo-de-scan` →
bug da ferramenta (não conta; falso positivo confirmado pelo dono vai em `tools/qa/ignore.json`).

- **rule-5** (`world/weapon_3d.gd:221`) — arma na mão recebe força/torque por tiro: viola AGENTS regra 5
  e duplica o recoil do `ViewmodelRig`. Fix: deletar `_apply_recoil`, uma fonte só.
- **mass divergente** (`core/inventory/container.gd:28/52`) — `total_weight`/`can_add_item` usam
  `item.mass` (0 no wrapper) enquanto `get_total_mass` usa `get_mass()`. Limite de peso cego ao conteúdo.
- **broken-refs** (3) — caminhos `res://` que não existem, em `.tscn`/`.tres`. Erro latente de export
  (o caso `world_ground` já mostrou). Roteados por dono pelo `qa`.
- **HAZARD DE MÉTODO: diff driver externo do repo** — `git diff` puro **não emite** linhas `+`/`-` (imprime o box desenhado), então uma checagem "o diff só tem X" pode sair **vazia** e passar vacuamente (aconteceu com o `meta`: "0 linhas não-ícone" contra um `--stat` de 118 arquivos). Forma segura: `git -c diff.external= diff --no-ext-diff --unified=0 <de> <para> -- <paths> | grep -E '^[+-][^+-]'`. Foi assim que se falsificou o "icon-only" do `ea7967f` (que trazia 15 repoints de `attachment.gd` → `attachment/attatchments.gd` + 7 trocas de fonte de ícone; conteúdo correto, commit não era o que dizia ser).
- ~~**ícones médicos: ext_resource para PNG untracked**~~ — **RESOLVIDO** por `f2dbfa4` (assets) + `ea7967f` (wire dos 118 `.tres`). Verificado pelo `meta` no HEAD de agora: **117 refs de ícone, 0 sem PNG rastreado**; e **33/33 weapons+attachments carregam** (probe com cópia do HEAD para `user://`).
  Achado original (meta 14:44Z): os 9 `resources/medical/*.tres` referenciavam PNG untracked; a pasta tinha
  0 arquivos rastreados e não estava no `.gitignore`. Lição: **nenhum gate local via isso** — `uid_tracking`
  cobre só `.gd`↔`.uid` e o `broken-ref` do qa só dispara quando o alvo **não existe no disco**
  (`audit.mjs:735-750`), e o PNG existia local. Só o clone limpo (CI) pega. **Correção de desenho**: o check
  "barato" de cruzar `path=` com `git ls-files` foi **falsificado pelo testkit** — `ext_resource` resolve por
  **`uid=` primeiro**, então path-only dá falso-positivo (uid válido + path stale CARREGA) e não vê o caso
  inverso; e a declaração de uid mora no `.import`/`.uid`, às vezes no **outro repo** (addon nested). Regra
  correta: para cada `ext_resource`, uid resolve (tracked) **OU** path resolve (tracked), com o mapa de uid vindo
  de `.uid`+`.import` dos **dois** repos. Fatal só quando uid desconhecido **E** path inválido (o caso dos 15
  weapons). Varredura uid-aware do meta: 148 refs vs 507 declarações → 19 sem declaração COMMITADA, todas
  declaradas no disco (`.uid` em voo) e **benignas** (path válido). Insumos em `/tmp/shooter/uidaudit2/`.
- **dead-API (morto-real)** — MAJOR em triagem; `qa` vai dar o breakdown por regra/dono (`unused-func`
  que retorna valor · `unused-field` · `dead-api` só-escrito) para não mandar dono caçar fantasma.
- **god objects** — `arena_manager` ~1147, `controller` ~1178, `cartridges_3d` ~1007. Não bloqueiam.
- ~~**duplicação** arena↔debug_range~~ — **RESOLVIDO (range) 2026-09-21**: `ViewSetup.configure_fps` + `Footsteps.tick` + `ShotResolver.resolve` + `ShotResolver.apply_hit` compartilhados; `ShotRay.GROUP` aliasa `PlayerBodyVisibility.SHOT_EXCLUDE_GROUP`; helpers duplicados removidos (dup arena↔range -> 0). `scenes/cartridges_3d.gd` (demo @tool orfao, 1007 linhas) **deletado** -> dup -> 0. Harness: dedup 6/6 + shot funcional HIT 6m 1793J (bot 560->490); import 0, boots ok. Baseline qa: 0/50/37/14 (deve cair p/ ~48 apos o delete).
- **corpo em primeira pessoa** — pitch/self-hit entregues e verificados; falta o **split de malha por
  osso** (cabeça+pescoço ocultos só da câmera FPS) para "ver os pés" de verdade — o corte por distância
  provou-se errado nos dois valores testados (mostra a nuca ou o próprio rosto).
- Guara scope housing (asset placeholder mal-baked) — parked.
- **meta: persist e do chamador** (`src/meta/*`) — as APIs de `MetaProfile`/`Market`/`FleaMarket` mutam
  estado em memória; persistir é responsabilidade do chamador (`Meta.persist()`; a arena chama em
  `_market_buy`/`_market_sell`). Documentado e **intencional**, verificado (spotter 2026-09-21). Risco:
  quem usar a API direto e esquecer o `persist()` perde a operação ao fechar. Endurecimento opcional
  (auto-persist nos wrappers do `MetaService`) = mudança separada, exige re-verificação. Não é bug.

## PRÓXIMO (não iniciado)

- **Gate uid-aware de `ext_resource` (fatal-only)** — desenho acordado com o `meta` (2026-09-21): para cada
  `ext_resource`, "o uid resolve para arquivo rastreado" OU "o path resolve para arquivo rastreado", com o mapa
  de uid de `.uid` + `uid=` de `.import` dos DOIS repos. O caso fatal e exatamente "uid desconhecido E path
  invalido" (os 15 weapons corrigidos em `c35c780`). NAO e so-path (falso-positivo: uid resolve primeiro) nem
  so-uid. Custo real > 20 linhas e encosta na regra `broken-ref` do qa — nao construido. Insumo do sweep do meta:
  `/tmp/shooter/uidaudit2/` (19 sem declaracao commitada mas declaradas no disco; 0 "nowhere").
- **Segundo mapa** — o teste real da premissa "isto é um framework": montar um nível novo só com as peças
  existentes (env compartilhado, `Raid`, `GameMode`, spawns, extrações, bots).
- **Escolha do `meta`**: hideout (DAG de módulos + timers) · flea market (listings/taxa/escrow) · **segundo papel
  (Contractor/Drifter) — ESCOLHIDO e aprovado pelo coordinator 2026-09-21T15:49Z**: UM save / um `MetaProfile`
  com estado **por papel** (não dois perfis), escolha do papel na **entrada do raid**, extrações via
  `ExtractionPoint.faction` (já existe), karma separado do rep de trader. Levantamento aterrado em
  `docs/meta-second-role-survey.md` (commit `66e10f3`): modelo de estado, fronteira gear/loot entre papéis
  (banco compartilhado + kits separados, swap só em PREP, conservação por massa, kit inicial 1x/papel e
  não-transferível, KIA forfeta só o kit ativo), karma aditivo-only, entrada. **PRÉ-REQUISITO BLOQUEANTE
  achado**: `ProfileStore` quarentena versão desconhecida (não migra) → bump p/ v2 sem migração v1→v2
  **apaga todo save existente**. NÃO iniciado: aguarda `verifier` fechar mercado/flea + liberação do coordinator.
- Guias por sistema em `docs/` (README cobre o "como adicionar"; faltam os "como funciona").
  **meta FEITO 2026-09-21**: `docs/meta-systems.md` (commit `df143cf`) — contrato de persistência, resolução
  de raid por outcome, traders/flea/seguro, skills/quests, como adicionar conteúdo e a dívida do `persist`.
  Faltam os equivalentes de gunplay/IA/apresentação.
- Shaders PSX nos materiais (precisa de julgamento visual), netcode (Fase 4).

Árvores sujas nos dois repos — **commits autorizados nesta rodada** (ordem do usuário via coordinator).
Evidências em `/tmp/shooter/`. testkit: `3e98608` (addon, test toolchain: parse gate + validators +
`validate_invariants` 10/10 + Jev oracle) e `36d0fe7` + `45e276b` (jogo, `tools/verify-all.sh` 10 gates + `.github/workflows/ci.yml`).

**RED atual do gate:** `uid_tracking` (gate 2) — **32** scripts rastreados no addon sem `.uid` commitado (HEAD-based; os `.uid` existem no disco, untracked — precisa `git add` + commit, cross-lane). **Dependências de CI:** `tools/qa/*` + `docs/qa-baseline.json` **FECHADO** (qa `94c42a5`; `--check` exit 0). **BLOQUEIO ESTRUTURAL (meta):** o HEAD do jogo não tem gitlink, então um clone limpo NÃO tem `addons/` — o `verify-all` agora falha com um preflight claro (`f7a8730`) em vez de "Can't load script"; fix = infra (gitlinks ou CI clonando os addons). Verificação em paralelo: `VERIFY_LOG_DIR` próprio (dir por-PID por padrão) + `flock` por-repo (`70e455a`).
