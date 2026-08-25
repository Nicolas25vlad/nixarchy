# Builds a passthru.updateScript for a package pinned to a GitHub release.
#
# The script asks GitHub for the latest release tag, and if it differs from
# what is pinned, prefetches every artefact and rewrites the version and
# hashes in the derivation. `nix-update` is not used because these packages
# pin several artefacts from one release (voxtype pins seven), which it does
# not handle.
#
# Every rewrite is proved by a build before it can be committed -- see
# .github/workflows/update.yml. A build is not proof the app still *works*,
# which is why those PRs are for a human to merge rather than automerged.
{
  lib,
  writeShellApplication,
  curl,
  jq,
  gnused,
  nix,
  coreutils,
  gnugrep,
}:
{
  pname, # attribute in this flake, e.g. "voxtype"
  file, # derivation to rewrite, relative to the repo root
  repo, # "owner/name" on GitHub
  # Maps each pinned artefact to the URL it comes from, with @version@ where
  # the version goes. The key must match the Nix attribute holding its hash.
  artefacts,
  versionPrefix ? "v",
}:
writeShellApplication {
  name = "update-${pname}";
  runtimeInputs = [
    curl
    jq
    gnused
    nix
    coreutils
    gnugrep
  ];
  text = ''
    file="''${1:-${file}}"
    [ -f "$file" ] || { echo "no $file (run from the repo root)" >&2; exit 1; }

    current=$(sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$file" | head -1)
    latest=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
      | jq -r '.tag_name' | sed 's/^${versionPrefix}//')

    if [ -z "$latest" ] || [ "$latest" = "null" ]; then
      echo "${pname}: could not read a release tag from GitHub" >&2
      exit 1
    fi
    if [ "$current" = "$latest" ]; then
      echo "${pname}: already at $latest"
      exit 0
    fi
    echo "${pname}: $current -> $latest"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (key: urlTemplate: ''
        url="${urlTemplate}"
        url="''${url//@version@/$latest}"
        echo "  prefetching ${key}"
        # --type sha256 keeps the plain hex the derivations already use, so
        # the diff is one hash per line rather than a format change.
        hash=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null | tail -1)
        if [ -z "$hash" ]; then
          echo "${pname}: could not fetch $url" >&2
          exit 1
        fi
        hex=$(nix hash to-base16 --type sha256 "$hash" 2>/dev/null || echo "$hash")
        # The key may be written quoted ("x86_64-linux" = ...) or bare
        # (appimage = ...), so both forms are accepted.
        before=$(grep -c "$hex" "$file" || true)
        sed -i -E "s|(\"?${key}\"?[[:space:]]*=[[:space:]]*)\"[0-9a-f]{64}\"|\1\"$hex\"|" "$file"
        after=$(grep -c "$hex" "$file" || true)
        if [ "$before" = "$after" ]; then
          # Nothing was rewritten. Bumping the version while leaving a stale
          # hash produces a file that reports success and then fails to build,
          # so refuse rather than hand that to a reviewer.
          echo "${pname}: could not rewrite the hash for '${key}' in $file" >&2
          echo "  expected a line matching: ${key} = \"<64 hex chars>\";" >&2
          exit 1
        fi
      '') artefacts
    )}

    sed -i -E "0,/version = \"[^\"]*\"/s//version = \"$latest\"/" "$file"
    echo "${pname}: rewrote $file to $latest"
  '';
}
