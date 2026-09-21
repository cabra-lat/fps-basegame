# Local tiny-model survey — decision models & Godot inference

Objetivo: achar um modelo **minúsculo, local, offline** para o papel de "julgamento"
(oráculo de teste e cérebro tático de bot), como alternativa/fecho do Jev (que exige
rede + crédito). Pesquisa de 2026-09-21.

## TL;DR

**Existe, e chama-se Laya.** É a **reprodução aberta do Jev** (Apache 2.0, by Convai
Innovations): mesmo protocolo de perguntas tipadas, mesma arquitetura de decisão
(não-autoregressivo, sem gerar texto), roda local, e é **6-7x mais rápido** que o Jev.

## Laya — o decision model local

| | |
|---|---|
| Params | **421M** (ModernBERT-large) · multilíngue 322M (mmBERT-base) |
| Contexto | 512 (en) / **1024** (multilingual, typed-decisions) |
| Forma | **um forward pass** — `choice` / `score` / `noul` sobre texto OU **JSON document** |
| Saída | valores tipados + probabilidades **calibradas** + confiança. Sem geração, sem alucinação |
| Latência | **32.8ms** (T4, 1 pergunta) · 7.2ms/pergunta em lote · **193-464ms em CPU** (com preload) |
| Pesos | **Apache 2.0**, no HF (`convaiinnovations/laya`, subfolders `/multilingual`, `/typed-decisions`) |
| GGUF | **sim** — `mys/laya-GGUF`, `laya-multilingual-GGUF`, `laya-typed-decisions-GGUF` |
| Tamanhos GGUF | F16 ~811MB · Q8_0 ~434MB · **UD_Q4_K_M ~404MB** |
| Runtime | binário `laya` (ggmlc) com `serve` (HTTP + Decision Studio) e `daemon` (JSON-RPC stdin/stdout) |

### Atenção: os GGUF do Laya NÃO são de llama.cpp

São produzidos pelo **ggmlc** (compilador de redes: PyTorch/JAX/Flax/Keras → GGML).
"Loading them in llama.cpp will fail." O runtime é o binário `laya` do ggmlc.

### As ressalvas honestas (do próprio README deles)

1. **Os checkpoints base são quase chance zero-shot** nos workflows de typed-decisions
   (0.362 e 0.342 contra baseline de maioria 0.461). Os 0.766 vêm de um checkpoint
   **fine-tunado**. Nas palavras deles: *"Treat Laya as a fast base to specialise, not
   as a zero-shot decision engine."*
2. **Fine-tuning é o valor** — notebook para Kaggle (2xT4 grátis), ~**4-5h** para 4
   épocas sobre ~30k perguntas, com RLCD (regras de pontuação próprias).
3. **Calibração**: vem over-confident; ajuste de temperatura move o ECE de 0.466 → 0.081.
4. **>20 opções degrada** (orçamento de tokens por label). Mantenha os `choice` enxutos.
5. **Multilíngue**: `laya` (inglês) colapsa fora do inglês **mantendo confiança alta**
   (khmer: 0.000 de acurácia com 95.2% de confiança!). Use o `Router` ou escolha o
   checkpoint certo.

### Viabilidade NESTA máquina (verificado)

- Releases Linux do `laya` são **CUDA-only**: `cuda-sm80` (A100), `sm86` (RTX30),
  `sm89` (RTX40). Não há build CPU-only para Linux.
- A GPU local é **GeForce 940MX (Maxwell, sm50)** com driver **470** → **CUDA não
  atende** (nem a arquitetura, nem o driver).
- Portanto o caminho local nesta máquina é: **fallback CPU do binário CUDA** (a
  confirmar) ou o pacote **`pip install laya`** (arrasta PyTorch — pesado, mas CPU
  confiável). O WebGPU demo roda no navegador como alternativa de avaliação.

## Alternativas de modelo local (para contexto)

| Modelo | Params | Forma | Quando usar |
|---|---|---|---|
| **Laya** | 421M / 322M | decisão tipada, 1 pass | **o encaixe para bot/oráculo** |
| SmolLM2 | 135M / 360M / 1.7B | LLM (gera texto) | diálogo, texto livre |
| Qwen2.5 | 0.5B / 1.5B | LLM | diálogo, raciocínio curto |
| LFM2 (Liquid) | 350M-1.2B | LLM | edge, baixa latência |
| Llama 3.2 | 1B / 3B | LLM | diálogo geral |
| Gemma 3 | 270M / 1B | LLM | diálogo leve |
| **MLP próprio (nosso)** | ~10k-1M | classificador | **decisão por frame** (ver abaixo) |

Nota de arquitetura: para **decisão por frame** (movimento, mira, cobertura) um LLM
ou mesmo o Laya são ferramenta errada — o certo é um **MLP pequeno** treinado por
imitation learning a partir das nossas behavior trees, exportado ONNX (poucos KB,
inferência em microssegundos). Laya/Jev servem para **decisão tática de ~1Hz**
("avanço, seguro, fujo ou saqueio?") e para o **oráculo de teste**.

## Como rodar dentro do Godot

Godot não tem inferência nativa. Opções, da mais simples à mais profunda:

| Caminho | O que é | Custo |
|---|---|---|
| **Sidecar HTTP** (`laya serve`) | processo separado; o jogo/ferramenta fala HTTP | simples; +400MB e um processo externo |
| [godot_onnx_extension](https://github.com/joemarshall/godot_onnx_extension) | GDExtension que roda ONNX no processo | médio; precisa exportar ONNX |
| [Godot Native RL](https://godotengine.org/asset-library/asset/5358) | **ncnn** estático em C++, sem runtime externo; treina com godot-rl | médio; é para **políticas RL**, não para Laya |
| [MLGodotKit](https://godotengine.org/asset-library/asset/4060) | treino + inferência de modelos simples in-engine | para modelos minúsculos |
| GDExtension com llama.cpp / ORT / TFLite | controle total | maior esforço |

**Recomendação de arquitetura (um interface, dois backends):** o cliente de oráculo que
já construímos (`test/jev/`) fala um protocolo de perguntas tipadas. O Laya expõe
exatamente a mesma forma (`choice`/`score`/`noul`). Logo: **mesma interface, backend
Jev (Zen, nuvem) OU Laya (local, offline, $0)** — escolhido por configuração, com
fallback local determinístico. Isso destrava o oráculo **sem crédito**.

## Plano proposto

1. **Agora (testkit):** abstrair o oráculo em "backend" e adicionar o backend Laya
   (sidecar `laya serve` ou `pip laya`), mantendo o Jev. Sonda de viabilidade CPU nesta
   máquina. Sem inventar resultado; reportar o gate de download (~430MB) para o humano.
2. **Fase seguinte:** fine-tunar o Laya no **nosso domínio** (estados do jogo: HUD/corpo/
   arma/alvo/bot) com o notebook de Kaggle (2xT4, ~4-5h). Isso é o que transforma
   "quase chance" em acerto de ~0.77 — o mesmo truque do checkpoint typed-decisions.
3. **Depois (no jogo):** MLP minúsculo por frame (ONNX/ncnn) para movimento/combate, com
   o Laya/Jev por cima para decisão tática.

## VERIFICADO NESTA MÁQUINA (2026-09-21, i5-7200U / Kaby Lake, AVX2 sem AVX-512)

Tudo abaixo foi executado de fato, não estimado.

### O binário oficial NÃO roda aqui
`laya-linux-x86_64-cuda-sm80.tar.gz` (71MB) exige `libcudart.so.12` + `libcublas.so.12`
+ `libcuda.so.1` no load (link duro contra CUDA). Fornecendo as libs CUDA 12.9 do nixpkgs
`-lib` e o driver em `/run/opengl-driver/lib`, ele **carrega** e cai para CPU
(`ggml_cuda_init: failed ... driver version is insufficient`), mas o `decide` morre com
**SIGILL (exit 132)**: o binário foi compilado com **`GGML_NATIVE=ON`** (o default do
ggmlc é `-march=native`) no CI deles, que tem AVX-512. Esta CPU tem AVX2 e **não** AVX-512.

### Compilar da fonte resolve (2,5 MB, sem CUDA)
```
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=OFF -DGGMLC_ENABLE_CUDA=OFF -DGGMLC_BUILD_EXAMPLES=ON \
  -DGGML_BUILD_TESTS=OFF -DGGML_BUILD_EXAMPLES=OFF
cmake --build build --target laya -j4
```
→ `build/examples/laya/laya`, **2,5 MB**, CPU-only, **zero deps de CUDA**. Build ~2 min.
Empacotado no `flake.nix` do repo como `.#laya-cpu` (`nix build .#laya-cpu`).

### Roda de verdade: decisões sobre o NOSSO domínio (jogo)
GGUF `laya_typed_decisions_ud_q4_k_m.gguf` (**423MB**, Q4_K_M, max_len 1024, max_opts 16).
Estado de teste: **deliberadamente quebrado** (HUD mostra 10, pente tem 7).

| Pergunta | Resposta | Veredito |
|---|---|---|
| `noul` HUD bate com o pente? | — | — |
| `choice` bug_class | **"none"**, confiança **0,03** | ❌ errou (era `hud_desync`) |
| distribuição | none .33 / hud_desync .16 / self_hit .30 / stale_rig .20 | quase uniforme = **ruído** |
| `score` coerência | **1,69/2** com p(2)=0,72 | ❌ achou "quase coerente" |

**Latência: 30,0 s para 4 perguntas em CPU** (i5-7200U, 4 threads) = 7,5 s/pergunta.
(`usage.input_tokens: 530` — note que 530 tokens é metade do contexto de 1024.)

### Conclusões honestas

1. ✅ **A plumbing funciona**: local, offline, $0, sem CUDA, binário de 2,5 MB, API
   compatível com TypeSafe (`/v1/systemone`) — o nosso cliente Jev aponta para ele
   trocando só a URL.
2. ❌ **O modelo base é inútil no nosso domínio** sem fine-tuning. Exatamente o que a
   doc avisa: ~chance fora dos workflows de treino. O argmax foi ruído.
3. ⚠️ **CPU é lenta demais para jogo**: 7,5 s/pergunta. Dá para oráculo de CI (lento mas
   viável); **não dá** para decisão de bot em tempo real a 1Hz.
4. → **O valor real está no fine-tuning** no nosso domínio (notebook Kaggle 2xT4, ~4-5h),
   que é o que leva 0.36 → 0.766 no benchmark deles. Sem isso, local não compensa.

### Recomendação revisada

- **Curto prazo (oráculo de teste):** Jev no Zen (rápido, calibrado, ~250ms) se houver
  crédito; senão aceitar o Laya local lento (~7,5s/pergunta) como oráculo de CI, sabendo
  que sem fine-tune o veredito dele é ruído — ou seja, **para checagem determinística
  continue usando código** (o harness exato), não o modelo.
- **Médio prazo (bot tático):** fine-tunar o Laya com estados do nosso jogo. É o único
  caminho para o modelo valer algo.
- **Frame-a-frame (movimento/mira):** MLP minúsculo nosso (ONNX/ncnn), não Laya/Jev.

## Fontes

- Laya: <https://github.com/NandhaKishorM/laya> · HF `convaiinnovations/laya` · PyPI `laya`
- GGUF (ggmlc, não-llama.cpp): <https://huggingface.co/mys/laya-typed-decisions-GGUF>
- Runtime/binários: <https://github.com/monatis/ggmlc> (releases v0.9.1, `laya-*`)
- Jev no OpenCode Zen: <https://opencode.ai/docs/zen/#jev> (`jev-1.13`, `jev-1.13-free`)
- Benchmark do Jev (terceiros): referenciado no BENCHMARKS.md do Laya
