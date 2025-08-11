{ lib
, pkgs
, config
, ...
}: let

  cfg = config.my.router;

  iso_folder_path = cfg.ipxe-boot.isoFolderPath;

  ipxe_boot_folder = "${config.services.atftpd.root}/ipxe-boot";

  json_path = pkgs.writeText "boot-environments.json" (builtins.toJSON (
    lib.attrsets.mapAttrs
    ( name: value: {
        inherit (value) isoName type;
        kStartScriptPath = (
          if builtins.isNull value.kStartScript
          then ""
          else if builtins.isString value.kStartScript
          then "${pkgs.writeText "${value.type}-script.kstart" value.kStartScript}"
          else "${value.kStartScript}"
        );
      }
    )
    cfg.ipxe-boot.environments
  ));

  functions-general = import ./functions/general.nix { inherit pkgs lib config; };
  inherit (functions-general)
    cfgSetDhcpServerInterfaceOnlyFilter
  ;

  ipv4_fn = import ./functions/ipv4.nix { inherit lib pkgs; };
  inherit (ipv4_fn)
    fromCidrString
  ;

  main_ipxe_file_fn = (
    pxe_host: pkgs.writeText "main-ID.ipxe" ''
      #!ipxe

      route

      set name RHEL9.6
      set base_url http://${pxe_host}:1337
      set repo ''${base_url}/iso-mountpoint/''${name}
      set kstart ''${base_url}/unattented-install/''${name}/kickstart.cfg

      kernel ''${repo}/images/pxeboot/vmlinuz initrd=initrd.img inst.repo=''${repo} inst.ks=''${kstart}
      initrd ''${repo}/images/pxeboot/initrd.img
      boot
    ''
  );

  signed-grub = import ./../packages/pxe-boot-grub-signed.nix { inherit pkgs; };

in (
  lib.mkIf cfg.ipxe-boot.enable {

    systemd.services."ipxe-boot-main-script" = {
      enable = true;
      description = "iPXE Boot - Prepare";
      after = [
        "network.target"
        "ipxe-boot-prepare.service"
      ];
      path = with pkgs; [rsync];
      script = ''
        set -eu
        set -x

        IPXE_BOOT_FOLDER_PATH="${ipxe_boot_folder}"

        mkdir -p "$IPXE_BOOT_FOLDER_PATH"
      ''
      +
      lib.strings.concatMapStrings
      ( dhcp_interface_conf: let

          dhcp_server = dhcp_interface_conf.dhcp.server;
          gateway = ( fromCidrString dhcp_server.gateway ).address;

        in
          ''
            rsync "${main_ipxe_file_fn gateway}" "$IPXE_BOOT_FOLDER_PATH/main-${builtins.toString dhcp_server.id}.ipxe"
          ''
      )
      ( cfgSetDhcpServerInterfaceOnlyFilter (
          dhcp_interface_conf: dhcp_interface_conf.dhcp.server.ipxe-boot.enable
      ))
      ;
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services."ipxe-boot-prepare" = {
      enable = true;
      description = "iPXE Boot - Prepare";
      after = [
        "network.target"
        "ipxe-boot-http-server.service"
      ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [curl diffutils jq rsync util-linux gawk];
      script = ''
        PATH="$PATH:/run/wrappers/bin"
        set -eu
        set -x

        TFTP_ROOT_FOLDER_PATH="${config.services.atftpd.root}"

        ROOT_FOLDER_PATH=/run/ipxe-boot
        ISO_MOUNT_FOLDER_PATH="$ROOT_FOLDER_PATH/iso-mountpoint"
        ISO_UNATTENTED_INSTALL_FOLDER_PATH="$ROOT_FOLDER_PATH/unattented-install"

        ISO_FOLDER_PATH="${iso_folder_path}"
        JSON_PATH="${json_path}"
        IPXE_BOOT_FOLDER_PATH="${ipxe_boot_folder}"

        ### Grub Boot: Begin
        url_base="(http,${"192.168.1.129"}:1337)"
        url_iso_mountpoint="$url_base/iso-mountpoint"
        url_iso_folder="http://${"192.168.1.129"}:1338"

        rsync -a "${signed-grub}/." "$TFTP_ROOT_FOLDER_PATH/."
        mkdir -p "$TFTP_ROOT_FOLDER_PATH/grub"
        echo "" > "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"

        find "$ISO_FOLDER_PATH" -iname "*.iso" | while read -r absolute_iso_path; do
          # k_start_script_path="$(jq -r ".[\"$name\"].kStartScriptPath" "$JSON_PATH")"
          # iso_unattented_install_folder_path="$ISO_UNATTENTED_INSTALL_FOLDER_PATH/$name"
          iso_file_name="$(basename "$absolute_iso_path")"
          url_mounted_iso="$url_iso_mountpoint/$iso_file_name"

          mount_folder_path="$ISO_MOUNT_FOLDER_PATH/$(basename "$absolute_iso_path")"

          if ! [[ -d "$mount_folder_path" ]]; then
            mkdir -p "$mount_folder_path"
          fi
          if mountpoint -q "$mount_folder_path"; then
            if ! mount | awk '$3=="'"$mount_folder_path"'"' | grep "^$absolute_iso_path"; then
              umount "$mount_folder_path"
            fi
          fi
          if ! mountpoint -q "$mount_folder_path"; then
            mount -t iso9660 "$absolute_iso_path" "$mount_folder_path" -o loop,ro
          fi

          squashfs_file_name="$(basename "$(find "$mount_folder_path" -iname '*.squashfs' | head -1 | tr -d '\n')")"
          case "$squashfs_file_name" in
            nix-store.squashfs)
                linux_file_path="$(cd "$mount_folder_path" && find boot -iname "bzImage")"
                initrd_file_path="$(cd "$mount_folder_path" && find boot -iname "initrd")"
                iso_file_path="$url_iso_folder/$iso_file_name"

                echo 'menuentry "'"$iso_file_name"'" {' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
                echo '    set gfxpayload=keep' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
                echo "    linux  $url_mounted_iso/$linux_file_path findiso=$iso_file_path root=LABEL=nixos-minimal-25.05-x86_64 boot.shell_on_fail nohibernate loglevel=4 lsm=landlock,yama,bpf" >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
                echo "    initrd $url_mounted_iso/$initrd_file_path" >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
                echo '}' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
              ;;

            *)
              echo "ERROR: Unable to detect boot ISO, cause the squashfs filename is unknown: $squashfs_file_name"
              ;;
          esac
        done

        echo 'menuentry "Reload Grub" {' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
        echo '    configfile /grub/grub.cfg' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
        echo '}' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"

        find "$ISO_FOLDER_PATH" -iname "*.iso" | while read -r absolute_iso_path; do
            iso_path="''${absolute_iso_path#$ISO_FOLDER_PATH/}"

            echo 'menuentry "'"$iso_path"'" {' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
            echo '    set gfxpayload=keep' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
            echo "    linux   /linux/linux ignore_uuid iso-url=http://${"192.168.1.129"}:1337/$iso_path ip=dhcp ---" >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
            echo '    initrd  /linux/initrd' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
            echo '}' >> "$TFTP_ROOT_FOLDER_PATH/grub/grub.cfg"
        done
        ### Grub Boot: End

        mkdir -p "$IPXE_BOOT_FOLDER_PATH"
        (
          mkdir -p "/tmp/ipxe-boot"
          cd "/tmp/ipxe-boot"
          ! [[ -f "ipxe.efi"     ]] && curl -SsOL "https://boot.ipxe.org/ipxe.efi"
          ! [[ -f "undionly.kpxe" ]] && curl -SsOL "https://boot.ipxe.org/undionly.kpxe"
          if ! cmp "ipxe.efi" "$IPXE_BOOT_FOLDER_PATH/ipxe.efi"; then
            cp "ipxe.efi" "$IPXE_BOOT_FOLDER_PATH/ipxe.efi"
          fi
          if ! cmp "undionly.kpxe" "$IPXE_BOOT_FOLDER_PATH/undionly.kpxe"; then
            cp "undionly.kpxe" "$IPXE_BOOT_FOLDER_PATH/undionly.kpxe"
          fi
        )

        jq -r '. | keys | .[]' "$JSON_PATH" | while read -r name; do
          iso_file_path="$ISO_FOLDER_PATH/$(jq -r ".[\"$name\"].isoName" "$JSON_PATH")"
          k_start_script_path="$(jq -r ".[\"$name\"].kStartScriptPath" "$JSON_PATH")"
          iso_unattented_install_folder_path="$ISO_UNATTENTED_INSTALL_FOLDER_PATH/$name"

          mount_folder_path="$ISO_MOUNT_FOLDER_PATH/$name"
          mount_folder_images_path="$mount_folder_path/images"

          ipxe_boot_folder_path="$IPXE_BOOT_FOLDER_PATH/$name"
          ipxe_boot_images_folder_path="$ipxe_boot_folder_path/images"

          if ! [[ -d "$mount_folder_path" ]]; then
            mkdir -p "$mount_folder_path"
          fi
          if mountpoint "$mount_folder_path"; then
            if ! mount | awk '$3=="'"$mount_folder_path"'"' | grep "^$iso_file_path"; then
              umount "$mount_folder_path"
            fi
          fi
          if ! mountpoint "$mount_folder_path"; then
            mount -t iso9660 "$iso_file_path" "$mount_folder_path" -o loop,ro
          fi

          if ! [[ -d "$iso_unattented_install_folder_path" ]]; then
            mkdir -p "$iso_unattented_install_folder_path"
          fi
          rsync "$k_start_script_path" "$iso_unattented_install_folder_path/kickstart.cfg"
        done
      '';
    };

    systemd.services."ipxe-boot-http-server" = {
      enable = true;
      description = "iPXE Boot - HTTP Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [darkhttpd];
      serviceConfig = {
        RuntimeDirectory="ipxe-boot";
        DynamicUser=true;
#         ExecStart=''${lib.getExe pkgs.darkhttpd} ${iso_folder_path} --port 1337'';
        ExecStart=''${lib.getExe pkgs.darkhttpd} /run/ipxe-boot --port 1337'';
#         ExecStop=''/run/wrappers/bin/umount --recursive /run/ipxe-boot'';
      };
    };

    systemd.services."ipxe-boot-http-server2" = {
      enable = true;
      description = "iPXE Boot - HTTP Server2";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [darkhttpd];
      serviceConfig = {
        DynamicUser=true;
        ExecStart=''${lib.getExe pkgs.darkhttpd} ${iso_folder_path} --port 1338'';
#         ExecStart=''${lib.getExe pkgs.darkhttpd} /run/ipxe-boot --port 1337'';
#         ExecStop=''/run/wrappers/bin/umount --recursive /run/ipxe-boot'';
      };
    };


    systemd.tmpfiles.settings = {
      "10-atftpd-root-folder"."${config.services.atftpd.root}".d = {
        mode = "0755";
        user = "nobody";
        group = "nogroup";
      };

      "10-atftpd-ipxe-boot-folder"."${ipxe_boot_folder}".d = {
        mode = "0755";
        user = "nobody";
        group = "nogroup";
      };
    };

    services.atftpd = {
      enable = true;
    };
  }
)

