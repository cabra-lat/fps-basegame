{
  description = "fps-basegame — Godot 4.7 FPS/extraction-shooter framework dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ── Laya: local System-1 decision model (open reproduction of Jev) ──────
        # Upstream ships CUDA-only prebuilt binaries built with GGML_NATIVE=ON
        # (-march=native), which SIGILL on CPUs without AVX-512 (e.g. Kaby Lake).
        # We build the CPU-only target with GGML_NATIVE=OFF so it runs anywhere.
        # Weights are NOT built here; fetch a GGUF separately (see README below).
        ggmlc-src = pkgs.fetchFromGitHub {
          owner = "monatis";
          repo = "ggmlc";
          rev = "v0.9.1";
          hash = "sha256-Mx2qDejn8M5KToMj+VZUjINWMe0U2pNxHW3U527QhBQ=";
        };

        laya-cpu = pkgs.stdenv.mkDerivation {
          pname = "laya-cpu";
          version = "0.9.1";
          src = ggmlc-src;
          nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
          cmakeFlags = [
            "-DCMAKE_BUILD_TYPE=Release"
            "-DGGML_NATIVE=OFF"        # portable CPU flags, no AVX-512 assumptions
            "-DGGMLC_ENABLE_CUDA=OFF"  # CPU-only build
            "-DGGMLC_ENABLE_METAL=OFF"
            "-DGGMLC_BUILD_EXAMPLES=ON"
            "-DGGML_BUILD_TESTS=OFF"
            "-DGGML_BUILD_EXAMPLES=OFF"
          ];
          buildPhase = "cmake --build build --target laya -j$NIX_BUILD_CORES";
          installPhase = ''
            mkdir -p $out/bin
            cp build/examples/laya/laya $out/bin/laya
          '';
        };

        # Helper: fetch a Laya GGUF into ./laya-models (gitignored, ~400 MB).
        fetchLayaModel = pkgs.writeShellApplication {
          name = "fetch-laya-model";
          runtimeInputs = [ pkgs.curl ];
          text = ''
            set -euo pipefail
            dir="''${1:-laya-models}"
            file="''${2:-laya_typed_decisions_ud_q4_k_m.gguf}"
            mkdir -p "$dir"
            url="https://huggingface.co/mys/laya-typed-decisions-GGUF/resolve/main/$file"
            echo "fetching $file -> $dir/"
            curl -fL --progress-bar -o "$dir/$file" "$url"
            ls -la "$dir/$file"
          '';
        };
      in {
        packages = {
          inherit laya-cpu;
          default = laya-cpu;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            # Godot + capture toolchain (see AGENTS.md golden commands)
            pkgs.godot_4
            # export templates: without these `--export-release` fails with
            # "No export template found at the expected path". Version-matched to
            # the engine above (4.7.1.stable); the devShell links them into
            # ~/.local/share/godot/export_templates so the CLI finds them.
            pkgs.godot_4-export-templates-bin
            pkgs.virtualgl
            pkgs.xorg-server       # Xvfb
            pkgs.ffmpeg
            pkgs.imagemagick
            # local AI / build toolchain
            laya-cpu
            pkgs.cmake
            pkgs.ninja
            pkgs.gcc
            pkgs.python3
            pkgs.uv
            fetchLayaModel
          ];

          shellHook = ''
            export GODOT_BIN="$(command -v godot)"
            # Export templates ship outside the engine's data dir; Godot looks in
            # ~/.local/share/godot/export_templates/<version>/. Link them once so
            # `godot --export-release` works straight from the devShell.
            _tmpl_src="${pkgs.godot_4-export-templates-bin}/share/godot/export_templates"
            _tmpl_dst="$HOME/.local/share/godot/export_templates"
            if [ -d "$_tmpl_src" ]; then
              for _v in "$_tmpl_src"/*; do
                _name="$(basename "$_v")"
                if [ ! -e "$_tmpl_dst/$_name" ]; then
                  mkdir -p "$_tmpl_dst"
                  ln -sfn "$_v" "$_tmpl_dst/$_name" 2>/dev/null || true
                fi
              done
            fi
            echo "fps-basegame dev shell"
            echo "  godot   : $GODOT_BIN"
            echo "  laya    : $(command -v laya)   (CPU build, portable flags)"
            echo "  export  : templates linked into $_tmpl_dst"
            echo ""
            echo "local decision model (Laya):"
            echo "  fetch-laya-model                 # ~404 MB -> ./laya-models/"
            echo "  laya decide laya-models/laya_typed_decisions_ud_q4_k_m.gguf \\"
            echo "    --family typed-decisions --state-file state.json \\"
            echo "    --questions-file questions.json --device cpu --json"
            echo ""
            echo "headless GPU run (awesomewm-safe):"
            echo "  Xvfb :99 & DISPLAY=:99 vglrun -d :0 godot --path . <scene>"
            echo ""
            echo "NOTE: Laya base checkpoints are ~chance zero-shot outside their"
            echo "      own training workflows; domain value requires fine-tuning."
          '';
        };
      });
}
