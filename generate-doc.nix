# Just run this nix program with: nix-build generate-doc.nix

{ pkgs ? import <nixpkgs>{}, modulesPath ? null, ... }@args: let
    inherit (pkgs)
      lib
      nixosOptionsDoc
      runCommand
    ;

    modulesPath = if builtins.hasAttr "modulesPath" args then modulesPath else <nixpkgs>;

    # evaluate our options
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
in
    # create a derivation for capturing the markdown output
    runCommand "options-doc.md" {} ''
        cat ${optionsDoc.optionsCommonMark} >> $out
    ''

