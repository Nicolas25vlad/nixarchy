inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  aiCfg = cfg.localAi;

  # Which Ollama to build against, decided from what this machine has ALREADY
  # declared about its GPU rather than by probing for one.
  #
  # Nix evaluates before the machine runs, so there is no hardware to look at --
  # but there is no need to look. A machine with an NVIDIA card has said so, in
  # hardware.nvidia (whose `enabled` is a read-only option computed from exactly
  # that), and an AMD one in hardware.amdgpu. Deriving from the configuration is
  # both the only thing that works here and the right answer anyway: rebuild on
  # a different machine and it follows.
  #
  # There is no `acceleration` option on services.ollama any more -- it was
  # removed, and the package is what chooses now. Every model still writes it;
  # see the nixos-ai skill.
  detected =
    if config.hardware.nvidia.enabled then
      "cuda"
    else if config.hardware.amdgpu.opencl.enable then
      "rocm"
    else
      "cpu";

  acceleration = if aiCfg.acceleration == "auto" then detected else aiCfg.acceleration;

  ollamaPackage =
    {
      cuda = pkgs.ollama-cuda;
      rocm = pkgs.ollama-rocm;
      vulkan = pkgs.ollama-vulkan;
      cpu = pkgs.ollama-cpu;
    }
    .${acceleration};

  # Read by modules/home.nix, which writes the agents' provider files: only it
  # knows where a user's home is. Exposed rather than recomputed there so the
  # address the server binds and the address the agents dial cannot drift.
  endpoint = "http://${aiCfg.host}:${toString aiCfg.port}/v1";

in
{
  options.programs.nixarchy.localAi = {
    enable = lib.mkEnableOption ''
      a local language model for this machine's own agents.

      Runs Ollama and points the coding agents at it, so the Nixarchy skills --
      which are what let an agent answer about *this* machine rather than about
      Arch -- work with no account, no key and no network.

      Off by default. It is several gigabytes of model weights and a service,
      and neither belongs on a machine whose owner did not ask for it
    '';

    model = lib.mkOption {
      type = lib.types.str;
      default = "qwen3:8b";
      example = "qwen3:4b";
      description = ''
        The Ollama model the agents talk to.

        Only tool-calling-trained models can edit files: opencode will read code
        with anything and silently fail to write with a model that cannot call
        tools, which looks like the agent ignoring you. The Qwen3 family is the
        dependable choice.

        Rough fit, at Q4: `qwen3:4b` is 2.5GB and the only sane pick on CPU or a
        small card, `qwen3:8b` 5.2GB and the usual default, `qwen3:14b` about
        9GB. `qwen3-coder` exists only at 30b and 480b -- the "qwen3-coder:8b"
        that several guides recommend is not a real tag.

        A model larger than the VRAM does not fail, it spills into system memory
        and crawls. `ollama ps` names which happened.
      '';
    };

    acceleration = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "cuda"
        "rocm"
        "vulkan"
        "cpu"
      ];
      default = "auto";
      description = ''
        Which Ollama build to use. `auto` reads it off this machine's own GPU
        configuration: `hardware.nvidia.enabled` means cuda,
        `hardware.amdgpu.opencl.enable` means rocm, and anything else -- a VM
        included -- means cpu.

        Set it by hand only to overrule that, e.g. `vulkan` on a card whose
        vendor stack is not worth the closure.
      '';
    };

    contextWindow = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 65536;
      description = ''
        Context window in tokens, or null to let Ollama decide.

        Null by default, and that is not laziness: Ollama already sizes the
        context from the memory it can see -- its own help says "4k/32k/256k
        based on VRAM" -- so setting this unconditionally replaces a figure
        that adapts with one that cannot.

        Doing exactly that is how this module got the service OOM-killed on an
        8GB machine. The cost is not the weights, it is the KV cache:

          llama_kv_cache: CPU KV buffer size = 3584.00 MiB

        3.5GB of cache at 32k, for a 1.7b model that is itself 1.4GB. Flash
        attention and a q8_0 cache are enabled below and roughly halve that,
        but the honest fix was to stop overriding a number that was already
        right.

        Set it when you know better than the heuristic -- opencode needs at
        least 65536 and will not hold a session below it -- on a machine with
        the memory to pay for it.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address the Ollama server listens on. Loopback by default, and it should
        stay there unless the machine is meant to serve other people: Ollama has
        no authentication whatsoever, so anything that can reach the port can use
        the GPU and read every model.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port the Ollama server listens on.";
    };

    pullModel = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Download the model during activation, rather than on first use.

        Off by default on purpose. A rebuild that silently spends several
        gigabytes of someone's connection is rude, and the setup command
        (`nixarchy local-ai`) pulls it with a progress bar and a size warning
        instead. Turn this on for a machine built unattended, where there is
        nobody to answer that prompt.
      '';
    };

    resolved = lib.mkOption {
      type = lib.types.attrs;
      # Not readOnly: the module system counts a readOnly option's default as a
      # definition, so having both a default (which modules/home.nix needs when
      # this is off) and a computed value (which it needs when it is on) is
      # "set multiple times". internal keeps it out of the manual either way.
      internal = true;
      default = { };
      description = ''
        What `auto` actually resolved to on this machine, for modules/home.nix
        and for `nixos-option programs.nixarchy.localAi.resolved` when someone
        asks why their GPU is not being used.
      '';
    };

    agents = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "opencode"
          "pi"
        ]
      );
      default = [
        "opencode"
        "pi"
      ];
      description = ''
        Which agents get a provider config pointing at the local model.

        Both, by default, because they suit different machines: opencode is the
        better agent and reads the skill directories that are already populated
        for Claude, while pi has no 64k floor and is the one that still works on
        a small card. Installing both costs little and lets someone switch with
        one menu click.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && aiCfg.enable) {
    # The resolved values, for the home module and for anyone debugging why a
    # machine picked the build it did. Read-only: they are computed, not set.
    programs.nixarchy.localAi.resolved = {
      inherit acceleration endpoint;
      package = ollamaPackage;
    };

    services.ollama = {
      enable = true;
      package = ollamaPackage;
      host = aiCfg.host;
      port = aiCfg.port;
      loadModels = lib.optional aiCfg.pullModel aiCfg.model;

      environmentVariables = {
        # Keep the model resident between questions. Reloading it from disk on
        # every prompt is most of what makes a local agent feel slow.
        OLLAMA_KEEP_ALIVE = "30m";

        # Both roughly halve the KV cache, which is the thing that actually
        # decides whether a model fits. Flash attention is the faster kernel and
        # the smaller allocation; q8_0 stores the cache quantised, at a quality
        # difference nobody has been able to show for this kind of work.
        OLLAMA_FLASH_ATTENTION = "1";
        OLLAMA_KV_CACHE_TYPE = "q8_0";
      }
      # Only when asked. Unset, Ollama picks from the memory it can see, which
      # is better than any single number this module could choose.
      // lib.optionalAttrs (aiCfg.contextWindow != null) {
        OLLAMA_CONTEXT_LENGTH = toString aiCfg.contextWindow;
      };
    };

    environment.systemPackages =
      lib.optional (builtins.elem "opencode" aiCfg.agents) pkgs.opencode
      ++ lib.optional (aiCfg.contextWindow != null && aiCfg.contextWindow < 65536 && builtins.elem "opencode" aiCfg.agents) ''
        programs.nixarchy.localAi: opencode needs a context window of at least
        65536 and this is pinned to ${toString aiCfg.contextWindow}, so opencode
        will not hold a session. pi has no such floor.

        Leaving contextWindow null lets Ollama size it from available memory,
        which is the right answer on almost every machine.
      '';
  };
}
