{
  lib,
  stdenvNoCC,
  src,
  version,
  # Runtime dependencies, derived by grepping every script in upstream `bin/`
  # for the commands it shells out to. Regenerate with:
  #   nix run .#deps-report
  bash,
  coreutils,
  util-linux,
  findutils,
  gnused,
  gnugrep,
  gawk,
  jq,
  gum,
  curl,
  socat,
  systemd,
  glib,
  xdg-utils,
  libnotify,
  # Wayland / Hyprland session
  hyprland,
  hyprpicker,
  hyprsunset,
  hyprlock,
  quickshell,
  wl-clipboard,
  wtype,
  grim,
  slurp,
  # Media / capture
  imagemagick,
  ffmpeg,
  gpu-screen-recorder,
  mpv,
  yt-dlp,
  tesseract,
  zbar,
  qrencode,
  # Hardware controls
  brightnessctl,
  ddcutil,
  pulseaudio,
  # provides `pactl`
  wireplumber,
  # provides `wpctl`
  playerctl,
  bluez,
  # provides `bluetoothctl`
  networkmanager,
  # provides `nmcli`
  # Shell tooling the CLI assumes is present
  fastfetch,
  btop,
  ripgrep,
  fd,
  bat,
  fzf,
  tmux,
  inotify-tools,
  python3,

  # Application tier. These are commands the bins invoke directly, not
  # libraries: omarchy-launch-terminal execs `uwsm-app -- xdg-terminal-exec`,
  # theme-set retints whichever terminals are present, and the menus launch
  # the file manager, browser and editor by name.
  xdg-terminal-exec,
  uwsm,
  foot,
  chromium,
  nautilus,
  neovim,
  mise,
  lazygit,
  lazydocker,
  eza,
  zoxide,
  starship,
  gtk3,
  udiskie,
  git,
  less,
  man-db,
  unzip,
  pamixer,
  alsa-utils,
  imv,
  evince,
  localsend,
  tldr,
  inxi,
  ffmpegthumbnailer,
  vips,
  file,
  libxkbcommon,
  xdg-user-dirs,
  satty,
  wl-screenrec,

  # Branding: this is a NixOS port, so the menu button wears the snowflake.
  nixos-icons,

}:
let
  # Everything the 438 scripts in bin/ invoke. Kept explicit rather than
  # pulled from a generated file: a missing entry should be a readable diff,
  # not a silent PATH lookup that only fails on someone else's machine.
  runtimeDeps = [
    bash
    coreutils
    util-linux
    findutils
    gnused
    gnugrep
    gawk
    jq
    gum
    curl
    socat
    systemd
    glib
    xdg-utils
    libnotify
    hyprland
    hyprpicker
    hyprsunset
    hyprlock
    quickshell
    wl-clipboard
    wtype
    grim
    slurp
    imagemagick
    ffmpeg
    gpu-screen-recorder
    mpv
    yt-dlp
    tesseract
    zbar
    qrencode
    brightnessctl
    ddcutil
    pulseaudio
    wireplumber
    playerctl
    bluez
    networkmanager
    fastfetch
    btop
    ripgrep
    fd
    bat
    fzf
    tmux
    inotify-tools
    python3

    # Application tier. Omitted from the first cut of this list, which is why
    # every terminal launch failed with `Command not found: xdg-terminal-exec`
    # while the bar itself rendered fine -- the utility tier was complete and
    # the application tier was entirely absent.
    #
    # foot is the only terminal in upstream's base.packages, so it is the one
    # xdg-terminal-exec resolves to by default. alacritty, ghostty and kitty
    # are supported by upstream's theming but not installed by it; add them
    # through environment.systemPackages if you want one of those instead.
    xdg-terminal-exec
    uwsm
    foot
    chromium
    nautilus
    neovim
    mise
    lazygit
    lazydocker
    eza
    zoxide
    starship

    # Cross-checked against upstream's own install/omarchy-base.packages
    # rather than against another hand-grep of the bins. That manifest is what
    # Omarchy declares it needs; curating the list by eye is what produced one
    # missing command per boot.
    gtk3 # gtk-launch, used by every omarchy-install-* to start the app
    udiskie # autostart.lua execs this on every login
    git # theme install, update checks
    less
    man-db
    unzip
    pamixer # audio bins
    alsa-utils # amixer/alsamixer
    imv # image viewer the menus open
    evince # PDF viewer
    localsend
    tldr
    inxi # omarchy-debug
    ffmpegthumbnailer # nautilus thumbnails
    vips # omarchy-menu-images, the wallpaper picker, shells out to `vips`

    # Found by auditing the running VM's PATH against what the scripts call,
    # rather than by reading base.packages again.
    file # omarchy-webapp-install: "file: command not found"
    libxkbcommon # xkbcli, for the keyboard-layout widget
    xdg-user-dirs # xdg-user-dirs-update
    satty # screenshot annotation
    wl-screenrec # screen recording
  ];
in
stdenvNoCC.mkDerivation {
  pname = "omarchy";
  inherit version src;

  strictDeps = true;

  # Not for linking -- this is what patchShebangs resolves against. With
  # strictDeps set it looks interpreters up in $HOST_PATH, which contains only
  # buildInputs; without bash here it finds nothing to rewrite `#!/bin/bash`
  # to and silently leaves all 425 scripts pointing at a path that does not
  # exist on NixOS. The build still succeeds, which is why CI asserts on it.
  buildInputs = [
    bash
    python3
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Upstream resolves everything through $OMARCHY_PATH, so the tree is kept
    # intact under share/ rather than being split across the FHS-ish outputs.
    # See default/hypr/bootstrap.lua, which builds its Lua package.path from it.
    #
    # Copied wholesale minus dev-only directories, rather than as an allowlist
    # of the directories that look important. An allowlist silently drops what
    # upstream adds next -- and already did: the root icon.png/logo.txt that
    # omarchy-show-logo, omarchy-branding-about and omarchy-plymouth-set read,
    # one of which default/chromium/extensions/copy-url symlinks to.
    mkdir -p $out/share/omarchy
    cp -r . $out/share/omarchy/
    rm -rf $out/share/omarchy/{.git,.github,docs,manual,test,plans,agents}

    # bin/ is a symlink farm, NOT wrapProgram'd. `bin/omarchy` discovers its
    # subcommands by grepping the first 80 lines of each sibling for
    # `# omarchy:summary=` metadata; a generated wrapper script has no such
    # comment, so wrapping every bin makes the CLI report zero commands.
    # Runtime deps reach the scripts through the NixOS module's systemPackages
    # instead -- see passthru.runtimeDeps.
    mkdir -p $out/bin
    for script in $out/share/omarchy/bin/*; do
      ln -s "$script" "$out/bin/$(basename "$script")"
    done

    # Upstream installs its bundled icon font to /usr/share/fonts/omarchy.
    # Nothing on NixOS scans $OMARCHY_PATH for fonts, so without this the
    # menu button renders U+E900 as tofu -- a literal empty box in the bar.
    # See default/fonts/omarchy/README.md for the private-use glyph map.
    install -Dm644 default/fonts/omarchy/omarchy.ttf \
      $out/share/fonts/truetype/omarchy.ttf

    # $OMARCHY_THEMES_PATH is a store path, and `cp -r` preserves its modes --
    # including r-xr-xr-x on directories. Upstream copies the chosen theme
    # into ~/.local/state/omarchy/current/theme, so on NixOS that staging
    # directory lands read-only and the NEXT theme switch cannot clean it up:
    #
    #   rm: cannot remove '.../current/theme/backgrounds/0-winding-road.jpg':
    #   Permission denied
    #
    # On Arch the source lives in /usr/share with writable modes, so upstream
    # never has to think about it.
    substituteInPlace $out/share/omarchy/bin/omarchy-theme-set \
      --replace-fail \
        'cp -r "$OMARCHY_THEMES_PATH/$THEME_NAME/"* "$NEXT_THEME_PATH/"' \
        'cp -r --no-preserve=mode "$OMARCHY_THEMES_PATH/$THEME_NAME/"* "$NEXT_THEME_PATH/"'

    # The banner every omarchy-launch-floating-terminal-with-presentation
    # prints. It says NIXARCHY so it is obvious which of the two is running --
    # the letters ARCHY are sliced from upstream's own logo.txt rather than
    # redrawn, so only NIX is new.
    install -Dm444 ${./branding/logo.txt} $out/share/omarchy/logo.txt

    # Omarchy ships wallpapers up to 7680px wide. Anything wider than
    # GL_MAX_TEXTURE_SIZE cannot become a texture, and the background renders
    # black with no error anywhere -- Qt reports the image Ready, the layer
    # surface exists at full size, and nothing is drawn. 4096 is the limit on
    # llvmpipe and on plenty of integrated GPUs, and 5 of the 8 backgrounds in
    # the default theme are over it.
    #
    # sourceSize caps what Qt decodes to. Setting only the width keeps the
    # aspect ratio, and 4096 is wider than any display this would be shown on,
    # so there is no visible loss -- and every machine decodes less. A plain
    # constant rather than anything derived from Screen: Screen is an attached
    # property that does not resolve inside an Image, and a QML error here
    # would take out the whole background rather than just the size hint.
    for prop in displayedBackground oldBackground incomingBackground; do
      substituteInPlace $out/share/omarchy/shell/plugins/background/Background.qml \
        --replace-fail \
          "source: root.imageUrl(root.$prop)" \
          "source: root.imageUrl(root.$prop)
        sourceSize.width: 4096"
    done

    # Replace the bins that drive pacman. These are not reachable through the
    # menu extension: the shell's bar widget and its "Update System"
    # notification call omarchy-update directly from QML, so overriding a menu
    # row would fix one of three entry points.
    #
    # Each replacement keeps its `# omarchy:summary=` line, because bin/omarchy
    # discovers subcommands by grepping siblings for exactly that.
    for replacement in ${./nix-bin}/*; do
      name=$(basename "$replacement")
      target=$out/share/omarchy/bin/$name
      if [ ! -e "$target" ]; then
        echo "nix-bin/$name replaces nothing in this Omarchy version" >&2
        exit 1
      fi
      install -Dm755 "$replacement" "$target"
    done

    # Wear the snowflake.
    substitute ${./menu-bar-widget.qml} \
      $out/share/omarchy/shell/plugins/menu/BarWidget.qml \
      --subst-var-by snowflake \
      "${nixos-icons}/share/icons/hicolor/256x256/apps/nix-snowflake.png"

    runHook postInstall
  '';

  # Upstream ships `#!/bin/bash`, which does not exist on NixOS.
  postFixup = ''
    patchShebangs $out/share/omarchy/bin
  '';

  passthru = {
    inherit runtimeDeps;
  };

  meta = {
    description = "Omarchy desktop environment, vendored for NixOS";
    longDescription = ''
      The upstream basecamp/omarchy tree packaged as-is: 438 shell commands,
      a QuickShell desktop shell, 22 themes, and the Hyprland Lua defaults.
      Vendored rather than reimplemented so that tracking an upstream release
      is a source bump instead of a re-port.
    '';
    homepage = "https://omarchy.org";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omarchy";
  };
}
