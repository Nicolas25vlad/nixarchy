# Every app Omarchy's Install menu offers, mapped to how NixOS installs it.
#
# The ids and labels come from upstream's own
# default/omarchy/omarchy-menu.jsonc; the right-hand side is the curated part
# and is the only place in this repo that needs a human when upstream adds an
# app. CI compares this file against that menu and fails on anything unmapped,
# so the list cannot rot silently.
#
# Per-app fields:
#   label      Shown in the generated template and the menu.
#   category   Groups rows in the template; matches the menu's own grouping.
#   attr       nixpkgs attribute, for apps that are only a package.
#   option     NixOS option path for apps that are a module rather than a
#              package. `settings` is merged HERE, which is what makes
#              `apps.tailscale.settings.useRoutingFeatures` land in the right
#              place. An app with an `option` must NOT also set `attr`: the
#              module owns installing its own package.
#   unfree     Needs nixpkgs.config.allowUnfree; surfaced as a template note
#              rather than a build failure nobody can read.
#   note       Anything a reader would otherwise have to discover the hard way.
#   arch       Upstream's Arch package name. Kept solely so the CI cross-check
#              can match rows; nothing at runtime reads it.
{
  # ── Browsers ────────────────────────────────────────────────────────────
  brave = {
    label = "Brave";
    category = "Browser";
    attr = "brave";
    arch = "brave-bin";
  };
  chrome = {
    label = "Chrome";
    category = "Browser";
    attr = "google-chrome";
    unfree = true;
    arch = "google-chrome";
  };
  edge = {
    label = "Edge";
    category = "Browser";
    attr = "microsoft-edge";
    unfree = true;
    arch = "microsoft-edge-stable-bin";
  };
  firefox = {
    label = "Firefox";
    category = "Browser";
    option = [
      "programs"
      "firefox"
    ];
    arch = "firefox";
    note = "A NixOS module, so policies and extensions are declarative too.";
  };

  # ── Editors ─────────────────────────────────────────────────────────────
  vscode = {
    label = "VSCode";
    category = "Editor";
    attr = "vscode";
    unfree = true;
    arch = "visual-studio-code-bin";
  };
  cursor = {
    label = "Cursor";
    category = "Editor";
    attr = "code-cursor";
    unfree = true;
    arch = "cursor-bin";
  };
  zed = {
    label = "Zed";
    category = "Editor";
    attr = "zed-editor";
    arch = "zed";
  };
  helix = {
    label = "Helix";
    category = "Editor";
    attr = "helix";
    arch = "helix";
  };
  emacs = {
    label = "Emacs";
    category = "Editor";
    attr = "emacs";
    arch = "omarchy-emacs";
  };
  vim = {
    label = "Vim";
    category = "Editor";
    attr = "vim";
    arch = "vim";
  };
  sublime = {
    label = "Sublime Text";
    category = "Editor";
    attr = "sublime4";
    unfree = true;
    arch = "sublime-text-4";
  };

  # ── Terminals ───────────────────────────────────────────────────────────
  # foot ships in the base session already; the rest are opt-in.
  alacritty = {
    label = "Alacritty";
    category = "Terminal";
    attr = "alacritty";
    arch = "alacritty";
  };
  ghostty = {
    label = "Ghostty";
    category = "Terminal";
    attr = "ghostty";
    arch = "ghostty";
  };
  kitty = {
    label = "Kitty";
    category = "Terminal";
    attr = "kitty";
    arch = "kitty";
  };

  # ── Services ────────────────────────────────────────────────────────────
  tailscale = {
    label = "Tailscale";
    category = "Service";
    option = [
      "services"
      "tailscale"
    ];
    arch = "tailscale";
    note = "A daemon. `settings.useRoutingFeatures = \"client\"` for exit nodes.";
  };
  _1password = {
    label = "1Password";
    category = "Service";
    option = [
      "programs"
      "_1password-gui"
    ];
    arch = "1password";
    unfree = true;
    note = ''
      Needs the module, not the package: unlocking requires a setuid helper
      that only programs._1password-gui installs. Set
      `settings.polkitPolicyOwners = [ "yourname" ]`.
    '';
  };
  dropbox = {
    label = "Dropbox";
    category = "Service";
    # A package, not a module: nixpkgs has no services.dropbox option, despite
    # dropbox being a daemon on other distros.
    attr = "dropbox";
    unfree = true;
    arch = "dropbox";
  };
  signal = {
    label = "Signal";
    category = "Service";
    attr = "signal-desktop";
    arch = "signal-desktop";
  };
  spotify = {
    label = "Spotify";
    category = "Service";
    attr = "spotify";
    unfree = true;
    arch = "spotify";
  };
  bitwarden = {
    label = "Bitwarden";
    category = "Service";
    attr = "bitwarden-desktop";
    arch = "bitwarden";
  };
  nordvpn = {
    label = "NordVPN";
    category = "Service";
    attr = "nordvpn";
    unfree = true;
    arch = "nordvpn-bin";
  };

  # ── Gaming ──────────────────────────────────────────────────────────────
  steam = {
    label = "Steam";
    category = "Gaming";
    option = [
      "programs"
      "steam"
    ];
    unfree = true;
    arch = "steam";
    note = "A module, not a package: Steam needs an FHS wrapper to run at all.";
  };
  lutris = {
    label = "Lutris";
    category = "Gaming";
    attr = "lutris";
    arch = "lutris";
  };
  heroic = {
    label = "Heroic (Epic Games)";
    category = "Gaming";
    attr = "heroic";
    arch = "heroic-games-launcher-bin";
  };
  retroarch = {
    label = "RetroArch";
    category = "Gaming";
    attr = "retroarch";
    arch = "retroarch";
  };
  xbox-controllers = {
    label = "Xbox Controllers";
    category = "Gaming";
    option = [
      "hardware"
      "xpadneo"
    ];
    arch = "xpadneo-dkms";
    note = "A kernel driver, so it is a hardware option rather than a package.";
  };

  # ── AI ──────────────────────────────────────────────────────────────────
  lm-studio = {
    label = "LM Studio";
    category = "AI";
    attr = "lmstudio";
    unfree = true;
    arch = "lmstudio-bin";
  };

  # ── Development ─────────────────────────────────────────────────────────
  php = {
    label = "PHP";
    category = "Development";
    attr = "php";
    arch = "php";
  };
  symfony = {
    label = "Symfony";
    category = "Development";
    attr = "symfony-cli";
    unfree = true;
    arch = "symfony-cli";
  };

  # ── No nixpkgs equivalent ───────────────────────────────────────────────
  # Listed so the CI cross-check stays honest and so the menu can say WHY a
  # row is gone rather than silently dropping it. `unavailable` entries
  # generate no option and no template row.
  minecraft = {
    label = "Minecraft";
    category = "Gaming";
    unavailable = "Use prismlauncher, which nixpkgs packages and maintains.";
    arch = "minecraft-launcher";
  };
  zen = {
    label = "Zen";
    category = "Browser";
    unavailable = "Not in nixpkgs; upstream ships a flake at github:0xc000022070/zen-browser-flake.";
    arch = "zen-browser-bin";
  };
  brave-origin = {
    label = "Brave Origin";
    category = "Browser";
    unavailable = "AUR-only build of Brave; use apps.brave.";
    arch = "brave-origin-bin";
  };
  chatgpt = {
    label = "ChatGPT Desktop";
    category = "AI";
    unavailable = "AUR-only; use the Web App menu entry instead.";
    arch = "openai-codex-desktop";
  };
  dictation = {
    label = "Dictation";
    category = "AI";
    unavailable = "voxtype is AUR-only and not yet packaged for nixpkgs.";
    arch = "voxtype-bin";
  };
  grok-bot = {
    label = "Grok Bot";
    category = "AI";
    unavailable = "AUR-only; use the Web App menu entry instead.";
    arch = "grok-bot";
  };
  t3-code = {
    label = "T3 Code";
    category = "AI";
    unavailable = "AUR-only, no nixpkgs package.";
    arch = "t3code-bin";
  };
  once = {
    label = "ONCE";
    category = "Service";
    unavailable = "AUR-only, no nixpkgs package.";
    arch = "once-bin";
  };
}
