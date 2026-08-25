# Every app Omarchy's Install menu offers, mapped to how NixOS installs it.
#
# The ids and labels come from upstream's own
# default/omarchy/omarchy-menu.jsonc; the right-hand side is the curated part
# and is the only place in this repo that needs a human when upstream adds an
# app. build.yml and omarchy.yml both compare this file against that menu and
# fail on anything unmapped, so the list cannot rot silently.
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
    menuId = "install.browser.brave";
    label = "Brave";
    category = "Browser";
    attr = "brave";
    arch = "brave-bin";
  };
  chrome = {
    menuId = "install.browser.chrome";
    label = "Chrome";
    category = "Browser";
    attr = "google-chrome";
    unfree = true;
    arch = "google-chrome";
  };
  edge = {
    menuId = "install.browser.edge";
    label = "Edge";
    category = "Browser";
    attr = "microsoft-edge";
    unfree = true;
    arch = "microsoft-edge-stable-bin";
  };
  firefox = {
    menuId = "install.browser.firefox";
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
    menuId = "install.editor.vscode";
    label = "VSCode";
    category = "Editor";
    attr = "vscode";
    unfree = true;
    arch = "visual-studio-code-bin";
  };
  cursor = {
    menuId = "install.editor.cursor";
    label = "Cursor";
    category = "Editor";
    attr = "code-cursor";
    unfree = true;
    arch = "cursor-bin";
  };
  zed = {
    menuId = "install.editor.zed";
    label = "Zed";
    category = "Editor";
    attr = "zed-editor";
    arch = "zed";
  };
  helix = {
    menuId = "install.editor.helix";
    label = "Helix";
    category = "Editor";
    attr = "helix";
    arch = "helix";
  };
  emacs = {
    menuId = "install.editor.emacs";
    label = "Emacs";
    category = "Editor";
    attr = "emacs";
    arch = "omarchy-emacs";
  };
  vim = {
    menuId = "install.editor.vim";
    label = "Vim";
    category = "Editor";
    attr = "vim";
    arch = "vim";
  };
  sublime = {
    menuId = "install.editor.sublime";
    label = "Sublime Text";
    category = "Editor";
    # nixpkgs marks sublimetext4 broken -- "Packages, including core ones, do
    # not run without plug-in host depending on insecure OpenSSL" -- and
    # enabling it aborts the whole rebuild rather than failing on its own.
    unavailable = "nixpkgs marks sublimetext4 broken over an insecure OpenSSL dependency; enabling it fails the rebuild.";
    arch = "sublime-text-4";
  };

  # ── Terminals ───────────────────────────────────────────────────────────
  # foot already ships in the base session, but its Install row still exists
  # upstream and has to be mapped or it stays wired to pacman. Enabling it is
  # harmless: systemPackages is a set.
  foot = {
    menuId = "install.terminal.foot";
    label = "Foot";
    category = "Terminal";
    attr = "foot";
    arch = "foot";
  };
  alacritty = {
    menuId = "install.terminal.alacritty";
    label = "Alacritty";
    category = "Terminal";
    attr = "alacritty";
    arch = "alacritty";
  };
  ghostty = {
    menuId = "install.terminal.ghostty";
    label = "Ghostty";
    category = "Terminal";
    attr = "ghostty";
    arch = "ghostty";
  };
  kitty = {
    menuId = "install.terminal.kitty";
    label = "Kitty";
    category = "Terminal";
    attr = "kitty";
    arch = "kitty";
  };

  # ── Services ────────────────────────────────────────────────────────────
  tailscale = {
    menuId = "install.service.tailscale";
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
    menuId = "install.service.1password";
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
    menuId = "install.service.dropbox";
    label = "Dropbox";
    category = "Service";
    # A package, not a module: nixpkgs has no services.dropbox option, despite
    # dropbox being a daemon on other distros.
    attr = "dropbox";
    unfree = true;
    arch = "dropbox";
  };
  signal = {
    menuId = "install.service.signal";
    label = "Signal";
    category = "Service";
    attr = "signal-desktop";
    arch = "signal-desktop";
  };
  spotify = {
    menuId = "install.service.spotify";
    label = "Spotify";
    category = "Service";
    attr = "spotify";
    unfree = true;
    arch = "spotify";
  };
  bitwarden = {
    menuId = "install.service.bitwarden";
    label = "Bitwarden";
    category = "Service";
    attr = "bitwarden-desktop";
    arch = "bitwarden";
  };
  nordvpn = {
    menuId = "install.service.nordvpn";
    label = "NordVPN";
    category = "Service";
    attr = "nordvpn";
    unfree = true;
    arch = "nordvpn-bin";
  };

  # ── Gaming ──────────────────────────────────────────────────────────────
  steam = {
    menuId = "install.gaming.steam";
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
    menuId = "install.gaming.lutris";
    label = "Lutris";
    category = "Gaming";
    attr = "lutris";
    arch = "lutris";
  };
  heroic = {
    menuId = "install.gaming.heroic";
    label = "Heroic (Epic Games)";
    category = "Gaming";
    attr = "heroic";
    arch = "heroic-games-launcher-bin";
  };
  retroarch = {
    menuId = "install.gaming.retroarch";
    label = "RetroArch";
    category = "Gaming";
    attr = "retroarch";
    arch = "retroarch";
  };
  xbox-controllers = {
    menuId = "install.gaming.xbox-controllers";
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
    menuId = "install.ai.lm-studio";
    label = "LM Studio";
    category = "AI";
    attr = "lmstudio";
    unfree = true;
    arch = "lmstudio-bin";
  };

  # ── Development ─────────────────────────────────────────────────────────
  php = {
    menuId = "install.development.php.php";
    label = "PHP";
    category = "Development";
    attr = "php";
    arch = "php";
  };
  symfony = {
    menuId = "install.development.php.symfony";
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
    menuId = "install.gaming.minecraft";
    label = "Minecraft";
    category = "Gaming";
    # nixpkgs removed `minecraft` as broken and its own error message says
    # to use prismlauncher, so this is nixpkgs' recommendation rather than a
    # substitution invented here.
    attr = "prismlauncher";
    arch = "minecraft-launcher";
  };
  zen = {
    menuId = "install.browser.zen";
    label = "Zen";
    category = "Browser";
    # Upstream's own flake, not a derivation here: it tracks Zen's releases
    # far more closely than we could.
    attr = "zen-browser";
    ours = true;
    arch = "zen-browser-bin";
  };
  brave-origin = {
    menuId = "install.browser.brave-origin";
    label = "Brave Origin";
    category = "Browser";
    unavailable = "Brave's managed build is AUR-only with no published source; enable apps.brave and put policies in /etc/brave/policies/managed, which stock Brave honours identically.";
    arch = "brave-origin-bin";
  };
  chatgpt = {
    menuId = "install.ai.chatgpt";
    label = "ChatGPT Desktop";
    category = "AI";
    attr = "chatgpt";
    unfree = true;
    arch = "openai-codex-desktop";
  };
  dictation = {
    menuId = "install.ai.dictation";
    label = "Dictation";
    category = "AI";
    attr = "voxtype";
    arch = "voxtype-bin";
  };
  grok-bot = {
    menuId = "install.ai.grok-bot";
    label = "Grok Bot";
    category = "AI";
    attr = "grok-bot";
    ours = true;
    unfree = true;
    arch = "grok-bot";
  };
  t3-code = {
    # No menuId: Omarchy v4.0.1 has no install.ai.t3-code row -- it was added
    # upstream after the tag this flake pins. The package is still available
    # as programs.nixarchy.apps.t3-code; the menu row returns when the omarchy
    # input is bumped. The generator fails on a menuId upstream does not
    # ship, which is how this was caught.
    label = "T3 Code";
    category = "AI";
    attr = "t3code";
    arch = "t3code-bin";
  };
  once = {
    menuId = "install.service.once";
    label = "ONCE";
    category = "Service";
    attr = "once";
    ours = true;
    arch = "once-bin";
  };
}
