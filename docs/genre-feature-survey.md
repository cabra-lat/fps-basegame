# Genre feature survey × framework gap matrix

Fonte: espelho local da wiki (`../tarkov-wiki`, 4902 páginas) + auditoria do código.
Objetivo: framework para **immersive sim / extraction shooter** estilo Tarkov.

> **Nota de cobertura:** o espelho foi scraped por *categorias de item* ("Weapons",
> "Ammunition", "Armor vests", "Quests"...). As páginas de **mecânica/sistema**
> (`Scavs`, `Raids`, `Insurance`, `Extraction points`, `Flea Market`, `Sound`,
> `Visibility`, `Movement`, `Stamina`, páginas de item médico) **não estão no
> espelho** — foram reconstruídas por referências cruzadas. Ação: estender o
> scraper para as páginas de sistema (ver "Lacuna de dados").

## O loop que define o gênero

`preparar → raid → lootear → extrair (ou morrer) → resolver → persistir`

O framework hoje tem **combate** (tiro, balística, dano, bot) mas **não tem o loop**:
não existe extração, nem raid state, nem stash, nem persistência. É a lacuna central.

---

## 1. Raid loop e extração — **AUSENTE** (identidade do gênero)

| Feature Tarkov | Números/regras | Status no framework |
|---|---|---|
| Timer de raid por mapa | Customs 35min/10-12 players; Factory 20-25min/5-8; Lab 30/8-10 | `GameMode.time_limit` em construção (range) |
| Extração: facção | Scav-only / PMC-only / All (Customs ~25 pontos) | ausente |
| Co-op extract | PMC+Scav ambos presentes | ausente |
| V-Ex (veículo pago) | ~20.000 ₽/player, máx 4, single-use | ausente |
| Flare extract | sinalizador verde no céu na área | ausente |
| Lever/switch extract | ativar alavanca (ZB-013) | ausente |
| Extract por nota (code-word) | precisa item de nota | ausente |
| Timed extract (trem) | Reserve: chega 16-12min do fim, fica 7min | ausente |
| Descontos | Charisma −0,1%/nível (−5% elite); Mark of the Unheard −50% | ausente |
| Run Through | extrair com <200 EXP de loot/kill **E** <7 min | ausente |
| MIA / KIA / Survivor | timer, morte, desconexão | ausente |

**Esforço:** moderado. Dados triviais; a lógica (flare, alavanca, co-op gate,
single-use, modificador de taxa) é código real. → **Fase 1 (agora).**

## 2. Persistência / meta — **AUSENTE** (segunda metade do gênero)

| Feature | Números/regras | Status |
|---|---|---|
| Stash (níveis) | 10x30 → 10x40 → 10x50 → 10x68 | ausente (backpack/container existem como item) |
| Save/load de perfil | — | só `settings_store.gd` |
| Seguro (insurance) | Prapor/Therapist/Jaeger; retorno −20% com Intelligence Center L2; sem retorno em Lab/Labyrinth/Icebreaker | ausente |
| Moeda | ₽ / $ / € / GP coin | ausente (`Item.cost` existe, sem moeda) |
| Hideout | 26 módulos, DAG, timers de construção até 106h, produção, gerador+combustível 12min38s por recurso | ausente |
| Scav/PMC (dois perfis) | Scav karma = reputação Fence; cooldown reduzido pelo Hideout | ausente |
| Karma / reputação | Fence LL4 = rep 6.00; karma −5 = BTR recusa | ausente |

**Esforço:** stash + save/load + moeda = moderado (**Fase 2**). Hideout = pesado
(DAG + simulação de tempo). Seguro = moderado. Scav/PMC = moderado.

## 3. Economia — **AUSENTE**

| Feature | Números | Status |
|---|---|---|
| Traders / loyalty | Prapor LL2 lvl6/rep0.70 → LL4 lvl36/rep7.90; 9 traders | ausente |
| Barter | item-por-item, limitado por reset | ausente |
| Flea market | nivel 15 p/ postar; taxa `VO·Ti·4^PO·Q + VR·Tr·4^PR·Q`; −30% IC3; +0,01 rep/50k ₽ | ausente |
| Reparo (durabilidade máx cai) | cerâmica quebra em ~2 reparos; UHMWPE aguenta muitos | ausente |

**Esforço:** traders/barter = moderado (tabelas + gates). Flea = pesado (listings,
taxa, escrow, rep). → Traders na **Fase 3**; flea adiado.

## 4. Quests — **AUSENTE**

Tipos de objetivo: localizar, obter N, entregar, eliminar (com modificadores de
distância/parte do corpo/arma/mapa), marcar (MS2000), instalar câmera, plantar item,
sobreviver+extrair, extrair por ponto específico, usar transit, moddar arma.
Diárias no nível 5, semanais no 15. Run Through não conta. Itens de quest somem se
não extrair.

**Esforço:** moderado-pesado. Schema data-driven + **barramento de eventos**
(kill/loot/extract) é o caminho. → **Fase 3**, mas o event bus deve nascer na Fase 1.

## 5. Skills — **AUSENTE**

51 níveis (Elite), 10 pts → nível 1, +10/nível (cap 100), curva `0.6^(n−1)`,
modificador reseta após 200s sem ponto. 4 categorias (Physical/Combat/Practical/Mental).
Exemplos com números: Strength +0,6%/nível de peso carregável (elite 100kg);
Endurance +1%/nível stamina; Vitality −1,2%/nível chance de sangrar.

**Esforço:** moderado (container genérico de XP + hooks). → **Fase 3/4**.

## 6. Dano e corpo — **PARCIAL (o mais adiantado)**

| Feature | Regra Tarkov | Status |
|---|---|---|
| Health por zona | Head 35 / Thorax 85 / Stomach 70 / Arms 60 / Legs 65 (PMC, total 440) | **TEM** — 16 BodyParts com pools |
| Dano é da munição, não da arma | confirmado | **TEM** |
| Múltiplas partes num tiro | bala atravessa e danifica várias | **PARCIAL** (impacto por camada existe) |
| Blunt damage (armadura segura) | % do dano vaza por "blunt throughput" | **PARCIAL** (health.gd tem caminho blunt) |
| Membro preto / overkill | dano transborda; perder membro pode matar; cirurgia (CMS/Surv12) restaura | **AUSENTE** |
| Sangramento leve/pesado | Vitality elite: auto-estanca em 20s/30s | **PARCIAL** (Wound BLEEDING + dps; sem item de tratamento) |
| Fratura | splint; Gym falha = 10% fratura | **PARCIAL** (Wound FRACTURE; sem splint, sem efeito de movimento) |
| Dor / tremor | analgésico/morfina; tremor afeta mira | **PARCIAL** (`pain_level` existe) |
| Energia / hidratação | dreno, comida/água (leite condensado +75 energy/−65 hydration) | **AUSENTE** |
| Stamina | pool, regen, dreno por peso; sprint infinito hoje | **AUSENTE** |
| Peso / encumbrance | overweight ~22-25kg; afeta stamina e movimento | **NÃO APLICADO** (`get_total_mass`/`get_movement_penalty`/`max_weight` já existem, ociosos) |
| Frio / frostbite | −20 stamina máx, −1/s regen, dano em membros | ausente |

**Esforço:** stamina + peso aplicados = **barato e altíssimo impacto** (código já
existe, só não está ligado). Médicos = dados + máquina de condições. → **Fase 1.**

## 7. Armadura — **BOM (falta camadas e reparo)**

Tarkov: classes **GOST BR1-6** (não NIJ in-game); ângulo **não** afeta penetração;
dano pós-penetração reduzido em 0-40%; durabilidade efetiva = dur / destrutibilidade
(cerâmica 0,6 → 60/0,6 = 100); mínimo 1 de dano de durabilidade por hit (até por
pellet); placas redefinem cobertura sobre o soft armor; capacetes ricocheteiam
(janela de ângulo por capacete).

| Status | Detalhe |
|---|---|
| **TEM** | cert tables (GOST/NIJ/VPAM), durabilidade, cobertura por zona, "cert decide + física é fall-through" (espelha "classe gate → pen chance") |
| **AUSENTE** | placas em camadas, tabela de destrutibilidade por material, reparo, tabela de ricochete por capacete |
| **AUSENTE** | zonas finas (axila desprotegida, face/orelhas/nuca/queixo/pescoço) |

→ **Fase 2** (ballistics): placas + destrutibilidade + reparo.

## 8. Munição — **BOM (calibrado, faltam bleeds/malfunction)**

Campos Tarkov: damage, penetration power, armor DMG %, accuracy, recoil,
**light bleed %**, **heavy bleed %**, speed, ricochet %, **durability burn**,
**heat**, **feedfailure**, **misfire**, projectiles, fragmentation %.
Ricochete: 5.45 BS 38% · 7.62x39 BP 31,5% · M995 36% · 9x19 RIP 0,2% · 8.5mm buck 0%.
Fragmentação: 9x18 PRS 30% · 7.62x25 AKBS 25% · 5.56 MK255 3%; RIP = 0.
Escala de efetividade vs classe 0-6 (0 = pointless 20+ tiros, 6 = ignora ~80%).

| Status | Detalhe |
|---|---|
| **TEM** | 46 munições calibradas (danos/pen/vel/BC/ricochete) |
| **FALTA** | bleed % (campo `bleeding_chance` existe, zerado), feed failure/misfire, durabilidade burn, multi-projétil integrado (buckshot), escala 0-6 vs classe |

→ **Fase 2** (ballistics), quase tudo dado.

## 9. Armas — **BOM (attachments) / faltam malfunctions**

| Feature | Tarkov | Status |
|---|---|---|
| Attachments / mod graph | compatibilidade por node-ID; cada mod dá Recoil %/Ergo/Accuracy/Velocity/Durability Burn/Heat/Cooling | **TEM** (attach_points bitmask + modifiers) |
| Recoil vert/horiz + ergonomia | M4: recoil V78/H224, ergo 55, MOA 1.82, RoF 800 | **PARCIAL** (recoil procedural; sem ergo) |
| Durabilidade da arma / wear | Weapon Maintenance −0,5%/nível | **AUSENTE** |
| Malfunctions | causas: magazine / durabilidade / cartucho; Troubleshooting +25% velocidade de conserto | **AUSENTE** (assinatura do jogo) |
| Heat / cooling | campos por mod | ausente |

→ **Fase 3** (player-rig/range): malfunctions + ergonomia + wear.

## 10. Som e furtividade — **BÁSICO**

| Feature | Tarkov | Status |
|---|---|---|
| Passos por superfície/andar | Covert Movement: −60% elite; arma/equipamento −60% | **PARCIAL** (2 passos concreto/terra) |
| Supressor / subsônico | redução qualitativa (sem número na wiki) | **TEM** dado no attachment (`sound_suppression`) |
| Redução de som do capacete | None/Low/Medium/High | campo existe no Armor (`sound_reduction`) |
| Audição da IA / propagação | (sem números na wiki) | **AUSENTE** |
| Visibilidade / stealth | (sem números na wiki) | **AUSENTE** |

→ **Fase 2** (npc-body): percepção (cone de visão + audição) — o que dá o "imersive"
de verdade. Os números terão de ser **nossos** (a wiki não tem).

## 11. IA — **v1**

Bots: patrulha, persegue com LOS, ataca, morre (+ times/waves em andamento).
Falta: squad tactics, cover, hearing, sight cone/FOV, loot-seeking, bosses,
dificuldade escalonada real.

→ **Fase 2** (npc-body).

---

## Decisão de prioridade

1. **Fase 1 — o loop (identidade do gênero)**: raid state machine + extraction
   points (facção/paga/flare/alavanca/co-op) + outcomes (Survived/Run Through/MIA/KIA)
   + event bus de raid. // stamina + peso aplicados (código ocioso) + itens médicos
   e condições (sangramento/fratura/dor) + membro preto/cirurgia.
2. **Fase 2 — persistência e sobrevivência**: stash + save/load de perfil + moeda;
   seguro; placas em camadas + destrutibilidade + reparo; bleed%/malfunction da
   munição; percepção da IA (visão+audição); malfunctions de arma.
3. **Fase 3 — meta**: traders/loyalty/barter, quests (schema + event bus), skills.
4. **Fase 4 — pesado/opcional**: hideout, flea market, scav/PMC, bosses, clima/frio.

## Lacuna de dados (ação imediata)

Estender `tarkov-wiki/tools/scrape-tarkov-wiki.mjs` para buscar as **páginas de
sistema** que faltam: `Scavs`, `Raids`, `Insurance`, `Extraction points`, `Flea Market`,
`Found in raid`, `Skills`, `Health` (modelo de dano), `Movement`, `Stamina`, `Sound`,
`Visibility`, `Weapon malfunctions`, `Crafting`, `Barter`, e as páginas de **item
médico** (Salewa, Grizzly, IFAK, CALOK-B, splints, stims, tourniquets). Sem elas,
vários sistemas acima ficam sem números de referência.
