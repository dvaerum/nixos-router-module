{ lib
, pkgs
, config
, ...
}: let

  cfg = config.my.router;

  iso_folder_path = cfg.pxe-boot.isoFolderPath;

  pxe_boot_folder = "/srv/pxeboot";

  functions-general = import ./functions/general.nix { inherit pkgs lib config; };
  inherit (functions-general)
    cfgSetDhcpServerInterfaceOnlyFilter
  ;

  ipv4_fn = import ./functions/ipv4.nix { inherit lib pkgs; };
  inherit (ipv4_fn)
    fromCidrString
  ;

  # Build the Rust pxe-boot-prepare binary
  pxe-boot-prepare-pkg = pkgs.callPackage ./../packages/pxe-boot-prepare/package.nix {};

  # Generate JSON configuration from NixOS options
  pxe-config = pkgs.writeText "pxe-boot-config.json" (builtins.toJSON {
    iso_folder_path = builtins.toString iso_folder_path;
    tftp_root = pxe_boot_folder;
    runtime_root = "/run/pxe-boot";

    dhcp_interfaces = lib.forEach
      (cfgSetDhcpServerInterfaceOnlyFilter (
        dhcp_interface_conf: dhcp_interface_conf.dhcp.server.pxe-boot.enable
      ))
      (dhcp_interface_conf: let
        dhcp_server = dhcp_interface_conf.dhcp.server;
        gateway = (fromCidrString dhcp_server.gateway).address;
      in {
        id = dhcp_server.id;
        name = dhcp_interface_conf.interfaceName;
        gateway = gateway;
        default_iso = if dhcp_server.pxe-boot.defaultIso != ""
                      then dhcp_server.pxe-boot.defaultIso
                      else null;
        default_script = if dhcp_server.pxe-boot.defaultScriptName != ""
                         then dhcp_server.pxe-boot.defaultScriptName
                         else null;
      });

    autoinstall = lib.attrsets.mapAttrs
      (isoName: scripts:
        lib.forEach scripts (script: {
          name = script.scriptName;
          script_path =
            if builtins.isString script.script
            then "${pkgs.writeText script.scriptName script.script}"
            else "${script.script}";
        })
      )
      cfg.pxe-boot.autoinstall;

    http = {
      mount_port = 1337;
      iso_port = 1338;
    };
  });

  main_ipxe_file_fn = (
    pxe_host: pkgs.writeText "main-ID.ipxe" ''
      #!ipxe

      set tftp-server ${pxe_host}

      goto ''${platform}


      :pcbios
      echo Booting Legacy Bios (platform: ''${platform})
      chain tftp://''${tftp-server}/grub.pxe
      goto exit


      :efi
      echo Booting UEFI (platform: ''${platform})
      # chain tftp://''${tftp-server}/bootx64.efi
      chain tftp://''${tftp-server}/grubx64.efi
      goto exit


      :exit
    ''
  );

  signed-grub = import ./../packages/pxe-boot-grub-signed/package.nix { inherit pkgs; };

in (
  lib.mkIf cfg.pxe-boot.enable {

    systemd.services = {
      "pxe-boot-main-script" = {
        enable = true;
        description = "PXE Boot - Copy GRUB Binaries";
        after = [
          "network.target"
          "pxe-boot-prepare.service"
        ];
        path = with pkgs; [rsync];
        script = ''
          set -eu
          set -x
        ''
        +
        lib.strings.concatMapStrings
        ( dhcp_interface_conf: let
            dhcp_server = dhcp_interface_conf.dhcp.server;
            gateway = ( fromCidrString dhcp_server.gateway ).address;

          in
            ''
              IPXE_BOOT_FOLDER_PATH="${pxe_boot_folder}/${builtins.toString dhcp_server.id}"
              mkdir -p "$IPXE_BOOT_FOLDER_PATH"
              rsync "${main_ipxe_file_fn gateway}" "$IPXE_BOOT_FOLDER_PATH/main.ipxe" &
              # `--chmod=Du+w` keeps the destination directories owner-writable.
              # Without it, `rsync -a` mirrors the read-only nix-store mode onto
              # "$IPXE_BOOT_FOLDER_PATH", and pxe-boot-prepare (which runs with a
              # CapabilityBoundingSet of only CAP_SYS_ADMIN, i.e. no CAP_DAC_OVERRIDE)
              # can then no longer create the "grub/" subdirectory for grub.cfg.
              rsync -a --chmod=Du+w --checksum "${signed-grub}/." "$IPXE_BOOT_FOLDER_PATH/." &
            ''
        )
        ( cfgSetDhcpServerInterfaceOnlyFilter (
            dhcp_interface_conf: dhcp_interface_conf.dhcp.server.pxe-boot.enable
        ))
        +
        ''
          wait
        ''
        ;
        wantedBy = [ "multi-user.target" ];
      };

      "pxe-boot-prepare" = {
        enable = true;
        description = "PXE Boot - Prepare";
        after = [
          "network.target"
          "pxe-boot-http-server.service"
        ];
        wantedBy = [ "multi-user.target" ];

        # Add mount utilities to PATH
        path = with pkgs; [ util-linux ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pxe-boot-prepare-pkg}/bin/pxe-boot-prepare --config ${pxe-config} prepare";
          ExecStop = "${pxe-boot-prepare-pkg}/bin/pxe-boot-prepare --config ${pxe-config} cleanup";

          # Allow ISO mounting with loop devices
          AmbientCapabilities = [ "CAP_SYS_ADMIN" ];
          CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];

          # Disable systemd security features that interfere with mounting
          PrivateDevices = false;  # Allow access to /dev/loop*
          ProtectKernelModules = false;  # Allow kernel module operations
          NoNewPrivileges = false;  # Allow privilege escalation for mount
        };
      };

      "pxe-boot-http-server" = {
        enable = true;
        description = "PXE Boot - HTTP Server";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        path = with pkgs; [darkhttpd];
        serviceConfig = {
          DynamicUser=true;
          ExecStart=''${lib.getExe pkgs.darkhttpd} /run/pxe-boot --port 1337'';
        };
      };

      "pxe-boot-http-server2" = {
        enable = true;
        description = "PXE Boot - HTTP Server2";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        path = with pkgs; [darkhttpd];
        serviceConfig = {
          DynamicUser=true;
          ExecStart=''${lib.getExe pkgs.darkhttpd} ${iso_folder_path} --port 1338'';
        };
      };

    }
    //
    (
      builtins.listToAttrs (
        lib.lists.forEach
        ( cfgSetDhcpServerInterfaceOnlyFilter (
          dhcp_interface_conf: dhcp_interface_conf.dhcp.server.pxe-boot.enable
        ))
        ( dhcp_interface_conf: {
            name = "pxe-boot-tftp-server-for-interface-${dhcp_interface_conf.interfaceName}";
            value = {
              enable = true;

              description = "TFTP Server";
              after = [ "network.target" "network-online.target" ];
              wants = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];
              # runs as nobody
              script = ''
                set -eu
                set -x

                ip_address="$(
                  ${pkgs.iproute2}/bin/ip --json addr show dev ${dhcp_interface_conf.interfaceName} \
                  | ${pkgs.jq}/bin/jq -r '.[].addr_info.[] | select(.family == "inet") | .local' \
                  | head -1
                )"

                if [[ -z "$ip_address" ]]; then
                  echo "No IP Address was found on the interface - \$ip_address: $ip_address"
                  exit 1
                fi

                exec ${pkgs.atftp}/sbin/atftpd \
                  --daemon \
                  --no-fork \
                  --bind-address "$ip_address" \
                  "${pxe_boot_folder}/${builtins.toString dhcp_interface_conf.dhcp.server.id}"
              '';

              serviceConfig = {
                Restart = "always";
                RestartSec = "10s";
              };
            };
          }
        )
      )
    );
  }
)
