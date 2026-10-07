# Just run this nix program with: nix-build generate-doc.nix

{
  pkgs ? import <nixpkgs> { },
  modulesPath ? null,
  ...
}@args:
let
  inherit (pkgs)
    lib
    nixosOptionsDoc
    runCommand
    ;

  modulesPath = if builtins.hasAttr "modulesPath" args then modulesPath else <nixpkgs>;

  # evaluate our router options
  eval = lib.evalModules {
    modules = [
      #            { _module.check = false; }
      #            "${modulesPath}/nixos/modules/system/boot/systemd.nix"
      ./nixosModule/options.nix
    ];
  };
  # generate our docs
  optionsDoc = nixosOptionsDoc {
    inherit (eval) options;
  };

  # `modules/iso-builder` declares options under its own `pxe-boot-iso.*`
  # namespace (e.g. `networkDownloadTmpfsSize`/`networkDownloadStallTimeoutSec`)
  # but, unlike `nixosModule/options.nix`, its `config` section depends on
  # the full NixOS module set (isoImage, fileSystems, boot, ...) -- a bare
  # `lib.evalModules [ ./modules/iso-builder ]` fails with "the option X
  # does not exist" for every base-NixOS option it sets. `pkgs.nixos {}`
  # brings in that full module set (same approach this project's own
  # pure-eval tests already use); `transformOptions`-equivalent filtering
  # (selecting just `.pxe-boot-iso`) keeps the generated doc scoped to
  # this project's own options instead of dumping every NixOS option.
  isoBuilderEval = pkgs.nixos { imports = [ ./modules/iso-builder ]; };
  isoBuilderOptionsDoc = nixosOptionsDoc {
    options = {
      inherit (isoBuilderEval.options) pxe-boot-iso;
    };
  };
in
# create a derivation for capturing the markdown output
runCommand "options-doc.md" { } ''
  cat ${optionsDoc.optionsCommonMark} >> $out
  echo "" >> $out
  echo "## pxe-boot-iso (modules/iso-builder)" >> $out
  echo "" >> $out
  cat ${isoBuilderOptionsDoc.optionsCommonMark} >> $out
''
