{ lib
, pkgs
, config
, ...
}: let

  cfg = config.my.router;

  iso_folder_path = cfg.pxe-boot.isoFolderPath;

  pxe_boot_folder = "/srv/pxeboot";

  json_path = pkgs.writeText "boot-environments.json" (builtins.toJSON (
    lib.attrsets.mapAttrs
    ( isoName: autoinstalls:
      lib.lists.forEach
      autoinstalls
      ( autoinstall: {
        inherit (autoinstall) scriptName;
        scriptFilePath =
          if builtins.isString autoinstall.script
          then "${pkgs.writeText autoinstall.scriptName autoinstall.script}"
          else "${autoinstall.script}"
        ;
      }
    )

#     lib.attrsets.mapAttrs'
#     ( name: value: lib.attrsets.nameValuePair
#       ()
#       {
#         inherit (value) isoName type;
#         kStartScriptPath = (
#           if builtins.isNull value.kStartScript
#           then ""
#           else if builtins.isString value.kStartScript
#           then "${pkgs.writeText "${value.type}-script.kstart" value.kStartScript}"
#           else "${value.kStartScript}"
#         );
#       }
#     )
    )
    cfg.pxe-boot.autoinstall
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

  signed-grub = import ./../packages/pxe-boot-grub-signed.nix { inherit pkgs; };

in (
  lib.mkIf cfg.pxe-boot.enable {

    systemd.services = {
      "pxe-boot-main-script" = {
        enable = true;
        description = "PXE Boot - Prepare";
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
              rsync -a "${signed-grub}/." "$IPXE_BOOT_FOLDER_PATH/." &
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

        path = with pkgs; [curl diffutils jq rsync util-linux gawk];
        script = ''
          PATH="$PATH:/run/wrappers/bin"
          set -eu
          set -x

          ROOT_FOLDER_PATH=/run/pxe-boot
          ISO_MOUNT_FOLDER_PATH="$ROOT_FOLDER_PATH/iso-mountpoint"
          ISO_UNATTENTED_INSTALL_FOLDER_PATH="$ROOT_FOLDER_PATH/unattented-install"

          ISO_FOLDER_PATH="${iso_folder_path}"
          JSON_PATH="${json_path}"
          TFTP_ROOT_FOLDER_PATH="${pxe_boot_folder}"

          function menuentry {
            menu_title="$1"
            linux="$2"
            initrd="$3"

            echo 'menuentry "'"$menu_title"'" {'
            echo '    set gfxpayload=keep'
            echo "    linux  $linux"
            echo "    initrd $initrd"
            echo '}'

            if [[ ! -f "/tmp/MENU_ENTRY" ]]; then
              echo -n "0" > /tmp/MENU_ENTRY
            else
              tmp_value="$(cat /tmp/MENU_ENTRY | tr -d '\n')"
              echo -n "$(( $tmp_value + 1 ))" > /tmp/MENU_ENTRY
            fi
          }

          find "$ISO_FOLDER_PATH" -iname "*.iso" | while read -r absolute_iso_path; do
            # k_start_script_path="$(jq -r ".[\"$name\"].kStartScriptPath" "$JSON_PATH")"
            # iso_unattented_install_folder_path="$ISO_UNATTENTED_INSTALL_FOLDER_PATH/$name"

            iso_file_name="$(basename "$absolute_iso_path")"
            mount_folder_path="$ISO_MOUNT_FOLDER_PATH/$iso_file_name"

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
          done

        ''
        +
        ( lib.strings.concatStringsSep "\n" (
          lib.lists.forEach
          ( cfgSetDhcpServerInterfaceOnlyFilter (
            dhcp_interface_conf: dhcp_interface_conf.dhcp.server.pxe-boot.enable
          ))
          ( dhcp_interface_conf: let
              dhcp_server = dhcp_interface_conf.dhcp.server;
              dhcp_id_as_str = builtins.toString dhcp_server.id;
              gateway = ( fromCidrString dhcp_server.gateway ).address;
            in ''
              rm -f /tmp/MENU_ENTRY

              ### Grub Menu (dhcp id: ${dhcp_id_as_str}): Begin
              grup_source_base="(http,${gateway}:1337)"
              grup_source_iso_mountpoint="$grup_source_base/iso-mountpoint"
              url_iso_folder="http://${gateway}:1338"
              tftp_dhcp_env_folder_path="$TFTP_ROOT_FOLDER_PATH/${dhcp_id_as_str}"

              mkdir -p "$tftp_dhcp_env_folder_path/grub"
              (
              echo 'if [ x$feature_timeout_style = xy ] ; then'
              echo '  # set timeout_style=menu'
              echo '  # set timeout=5'
              echo 'else'
              echo '  # set timeout=5'
              echo 'fi'
              echo
              echo '# set default='
              echo
              ) > "$tftp_dhcp_env_folder_path/grub/grub.cfg"

              find "$ISO_FOLDER_PATH" -iname "*.iso" | sort | while read -r absolute_iso_path; do
                iso_file_name="$(basename "$absolute_iso_path")"
                mount_folder_path="$ISO_MOUNT_FOLDER_PATH/$iso_file_name"
                grup_source_mounted_iso="$grup_source_iso_mountpoint/$iso_file_name"
                url_mounted_iso="http://${gateway}:1337/iso-mountpoint/$iso_file_name"
                url_unattented_install="http://${gateway}:1337/unattented-install/$iso_file_name"

                squashfs_file_name="$(basename "$(
                  find "$mount_folder_path" '(' -name 'RPM-GPG-KEY-redhat-release' -or -iname '*.squashfs' ')' \
                  | head -1 | tr -d '\n'
                )")"
                case "$squashfs_file_name" in
                  nix-store.squashfs)
                      linux_file_path="$(cd "$mount_folder_path" && find boot -iname "bzImage")"
                      initrd_file_path="$(cd "$mount_folder_path" && find boot -iname "initrd")"
                      iso_file_path="$url_iso_folder/$iso_file_name"

                      menuentry \
                        "$iso_file_name" \
                        "$grup_source_mounted_iso/$linux_file_path findiso=$iso_file_path root=LABEL=nixos-minimal-25.05-x86_64 boot.shell_on_fail nohibernate loglevel=4 lsm=landlock,yama,bpf" \
                        "$grup_source_mounted_iso/$initrd_file_path" \
                        >> "$tftp_dhcp_env_folder_path/grub/grub.cfg"
                    ;;

                  ubuntu-server-minimal.squashfs)
                      linux_file_path="$(cd "$mount_folder_path" && find casper -iname "vmlinuz")"
                      initrd_file_path="$(cd "$mount_folder_path" && find casper -iname "initrd")"
                      iso_file_path="$url_iso_folder/$iso_file_name"

                      menuentry \
                        "$iso_file_name" \
                        "$grup_source_mounted_iso/$linux_file_path ip=dhcp url=$iso_file_path" \
                        "$grup_source_mounted_iso/$initrd_file_path" \
                        >> "$tftp_dhcp_env_folder_path/grub/grub.cfg"
                    ;;

                  RPM-GPG-KEY-redhat-release)
                      linux_file_path="$(cd "$mount_folder_path" && find images/pxeboot -iname "vmlinuz")"
                      initrd_file_path="$(cd "$mount_folder_path" && find images/pxeboot -iname "initrd.img")"
                      iso_file_path="$url_iso_folder/$iso_file_name"


                      menuentry \
                        "$iso_file_name" \
                        "$grup_source_mounted_iso/$linux_file_path initrd=initrd.img inst.repo=$url_mounted_iso" \
                        "$grup_source_mounted_iso/$initrd_file_path" \
                        >> "$tftp_dhcp_env_folder_path/grub/grub.cfg"

                      jq -cr ".[\"$iso_file_name\"] | if . == null then \"\" else .[] end" "$JSON_PATH" | while read -r json_obj; do
                        [[ -z "$json_obj" ]] && continue

                        script_file_path="$(jq -r ".scriptFilePath" <<<"$json_obj")"
                        script_name="$(jq -r ".scriptName" <<<"$json_obj")"
                        iso_unattented_install_folder_path="$ISO_UNATTENTED_INSTALL_FOLDER_PATH/$iso_file_name"
                        script_url="$url_unattented_install/$script_name"

                        mkdir -p "$iso_unattented_install_folder_path"
                        rsync "$script_file_path" "$iso_unattented_install_folder_path/$script_name"

                        menuentry \
                          "$iso_file_name ($script_name)" \
                          "$grup_source_mounted_iso/$linux_file_path initrd=initrd.img inst.repo=$url_mounted_iso inst.ks=$script_url" \
                          "$grup_source_mounted_iso/$initrd_file_path" \
                          >> "$tftp_dhcp_env_folder_path/grub/grub.cfg"

                        if [[ "$iso_file_name" == "${dhcp_server.pxe-boot.defaultIso}" ]]; then
                          if [[ "$script_name" == "${dhcp_server.pxe-boot.defaultScriptName}" ]]; then
                            sed -i 's/^# set default=/set default='"$(cat /tmp/MENU_ENTRY | tr -d '\n')"'/' \
                              "$tftp_dhcp_env_folder_path/grub/grub.cfg"
                            sed -i 's/^  # set timeout/  set timeout/' \
                              "$tftp_dhcp_env_folder_path/grub/grub.cfg"
                          fi
                        fi
                      done
                    ;;

                  *)
                    echo "ERROR: Unable to detect boot ISO, cause the squashfs filename is unknown: $squashfs_file_name"
                    ;;
                esac
              done

              echo 'menuentry "Reload Grub" {' >> "$tftp_dhcp_env_folder_path/grub/grub.cfg"
              echo '    configfile /grub/grub.cfg' >> "$tftp_dhcp_env_folder_path/grub/grub.cfg"
              echo '}' >> "$tftp_dhcp_env_folder_path/grub/grub.cfg"
              ### Grub Menu (dhcp id: ${dhcp_id_as_str}): End
            ''
          )
        ));
      };

      "pxe-boot-http-server" = {
        enable = true;
        description = "PXE Boot - HTTP Server";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        path = with pkgs; [darkhttpd];
        serviceConfig = {
          RuntimeDirectory="pxe-boot";
          DynamicUser=true;
  #         ExecStart=''${lib.getExe pkgs.darkhttpd} ${iso_folder_path} --port 1337'';
          ExecStart=''${lib.getExe pkgs.darkhttpd} /run/pxe-boot --port 1337'';
  #         ExecStop=''/run/wrappers/bin/umount --recursive /run/pxe-boot'';
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
  #         ExecStart=''${lib.getExe pkgs.darkhttpd} /run/pxe-boot --port 1337'';
  #         ExecStop=''/run/wrappers/bin/umount --recursive /run/pxe-boot'';
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
              after = [ "network.target" ];
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

                exec ${pkgs.atftp}/sbin/atftpd \
                  --daemon \
                  --no-fork \
                  --bind-address "$ip_address" \
                  "${pxe_boot_folder}/${builtins.toString dhcp_interface_conf.dhcp.server.id}"
              '';
            };
          }
        )
      )
    );
  }
)

