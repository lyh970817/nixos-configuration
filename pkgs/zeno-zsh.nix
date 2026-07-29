{
  lib,
  fetchFromGitHub,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "zeno-zsh";
  version = "unstable-2026-04-05";

  src = fetchFromGitHub {
    owner = "yuki-yano";
    repo = "zeno.zsh";
    rev = "2e8fbecce0fc3692a5fcc9033ecca7ab35263e56";
    hash = "sha256-05+w1WP/SHKp97JTGsvO3csI123U7py+fVSKnAWiUNY=";
  };

  dontBuild = true;

  postPatch = ''
    while IFS= read -r -d "" file; do
      substituteInPlace "$file" \
        --replace-fail --node-modules-dir=auto --node-modules-dir=none
    done < <(grep -rlZ -- --node-modules-dir=auto .)

    # Zsh locals are dynamically scoped: this widget's scalar `options`
    # otherwise shadows zsh-syntax-highlighting's associative `$options`.
    substituteInPlace shells/zsh/widgets/zeno-completion \
      --replace-fail \
        'local callback callback_kind callback_zero cmdline expect_key options source_command source_id fzf_command tmux_opts_str' \
        'local callback callback_kind callback_zero cmdline expect_key fzf_options source_command source_id fzf_command tmux_opts_str' \
      --replace-fail 'options=$out[3]' 'fzf_options=$out[3]' \
      --replace-fail \
        'options="''${tmux_opts_str}''${options}"' \
        'fzf_options="''${tmux_opts_str}''${fzf_options}"' \
      --replace-fail \
        'cmdline="''${source_command} | ''${fzf_command} ''${options}"' \
        'cmdline="''${source_command} | ''${fzf_command} ''${fzf_options}"' \
      --replace-fail \
        'option_words=(''${(z)options})' \
        'option_words=(''${(z)fzf_options})'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/zeno.zsh"
    cp -R . "$out/share/zeno.zsh"
    runHook postInstall
  '';

  meta = {
    description = "Zsh fuzzy completion and utility plugin with Deno";
    homepage = "https://github.com/yuki-yano/zeno.zsh";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
