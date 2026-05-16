{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
with lib; let
  cfg = config.pxe-boot-iso;
in {
  imports = [(modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")];

  options.pxe-boot-iso = {
    enable = mkEnableOption "PXE-bootable ISO configuration";

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages to include in the ISO";
      example = literalExpression "[ pkgs.vim pkgs.git ]";
    };

    includeNetworkTools = mkOption {
      type = types.bool;
      default = true;
      description = "Include network troubleshooting tools (tcpdump, nmap, etc.)";
    };

    includeDiskTools = mkOption {
      type = types.bool;
      default = true;
      description = "Include disk utilities (parted, gparted, etc.)";
    };

    includeHardwareTools = mkOption {
      type = types.bool;
      default = true;
      description = "Include hardware testing tools (lshw, hwinfo, etc.)";
    };

    sshAuthorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "SSH authorized keys for the nixos user";
      example = ["ssh-ed25519 AAAAC3Nz... user@host"];
    };

    kernelPackage = mkOption {
      type = types.raw; # Accept linuxPackages attrset
      default = pkgs.linuxPackages_latest;
      description = "Kernel packages to use (linuxPackages_* attrset)";
      example = literalExpression "pkgs.linuxPackages_6_12";
    };

    enableNetworkDownload = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable downloading ISO via network during initrd.
        This allows using findiso=http://... kernel parameter to download the ISO over network.
      '';
    };

    # User configuration options
    users = {
      nixos = {
        password = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Plain text password for the nixos user.
            - null: Empty password (login without password) - DEFAULT
            - "somepassword": Sets this password
            Cannot be used together with hashedPassword.
          '';
        };

        hashedPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Hashed password for the nixos user (e.g., from mkpasswd).
            Cannot be used together with password.
          '';
        };

        allowSudoWithoutPassword = mkOption {
          type = types.bool;
          default = true;
          description = "Allow nixos user to use sudo without password";
        };
      };

      root = {
        password = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Plain text password for the root user.
            - null: Empty password (login without password) - DEFAULT
            - "somepassword": Sets this password
            Cannot be used together with hashedPassword.
          '';
        };

        hashedPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Hashed password for the root user (e.g., from mkpasswd).
            Cannot be used together with password.
          '';
        };
      };
    };

    # SSH configuration options
    ssh = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable SSH server";
      };

      passwordAuthentication = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Whether to allow SSH password authentication.
          - null: Automatically set to false if sshAuthorizedKeys is provided, true otherwise - DEFAULT
          - true: Allow password authentication
          - false: Disable password authentication (keys only)
        '';
      };

      permitRootLogin = mkOption {
        type = types.enum ["yes" "no" "prohibit-password" "forced-commands-only"];
        default = "yes";
        description = "Whether to allow root login via SSH";
      };
    };
  };

  config = mkIf cfg.enable {
    # Assertions for conflicting password options
    assertions = [
      {
        assertion = !(cfg.users.nixos.password != null && cfg.users.nixos.hashedPassword != null);
        message = "pxe-boot-iso.users.nixos: Cannot set both 'password' and 'hashedPassword'. Please choose one.";
      }
      {
        assertion = !(cfg.users.root.password != null && cfg.users.root.hashedPassword != null);
        message = "pxe-boot-iso.users.root: Cannot set both 'password' and 'hashedPassword'. Please choose one.";
      }
    ];

    # Enable flakes for modern Nix workflow
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Package selection based on options
    environment.systemPackages = with pkgs;
      [
        # Essential tools
        git
        neovim
        fish
        rsync
        jq
        fzf
        file
        tmux
        htop
        disko
      ]
      ++ optionals cfg.includeNetworkTools [
        # Network troubleshooting
        tcpdump
        nmap
        iperf3
        ethtool
        netcat
        wget
        curl
        traceroute
        mtr
        bind.dnsutils # dig, nslookup
      ]
      ++ optionals cfg.includeDiskTools [
        # Disk utilities
        parted
        gparted
        testdisk
        smartmontools
        hdparm
        nvme-cli
      ]
      ++ optionals cfg.includeHardwareTools [
        # Hardware testing
        lshw
        hwinfo
        pciutils
        usbutils
        dmidecode
        libva-utils
        stress-ng
      ]
      ++ cfg.extraPackages;

    # Disable man pages to reduce size
    documentation.man.enable = false;

    # Boot configuration
    boot = {
      # ZFS support for advanced storage setups
      supportedFilesystems = ["zfs"];
      zfs.devNodes = "/dev/disk/by-partuuid";
      kernelPackages = cfg.kernelPackage;
      loader.timeout = mkForce 5;

      # Include common network drivers in initrd for PXE boot
      initrd.availableKernelModules = [
        # VirtIO (for VMs and QEMU)
        "virtio_net"
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "virtio_balloon"
        "virtio_console"
        # Intel NICs
        "e1000"
        "e1000e"
        "igb"
        "igc"
        # Realtek NICs
        "r8169"
        # Atheros NICs
        "atl1c"
        "atlantic"
      ];

      # Enable network in initrd for PXE boot
      initrd.network.enable = true;
      initrd.network.udhcpc.enable = true;

      # Add wget to initrd for ISO download
      initrd.extraUtilsCommands = mkIf cfg.enableNetworkDownload ''
        copy_bin_and_libs ${pkgs.wget}/bin/wget
      '';

      # Support downloading ISO via network using postDeviceCommands
      # This is the correct hook for network-based ISO downloads
      initrd.postDeviceCommands = mkIf cfg.enableNetworkDownload ''
        download_iso_file="$(grep -Eo 'findiso=http(s)?://[^ ]+' /proc/cmdline | cut -d= -f2-)"
        if [ -n "$download_iso_file" ]; then
          isoPath=""
          mkdir -p "/findiso"
          # Mount tmpfs with enough space for the ISO (2GB)
          mount -t tmpfs -o size=2G tmpfs /findiso
          wget -O "/findiso/nixos_live.iso" "$download_iso_file"
          ln -sf "/findiso/nixos_live.iso" "/dev/root"
        fi
      '';

      # Fix stage2 init path for proper boot
      initrd.postMountCommands = mkIf cfg.enableNetworkDownload ''
        if [ "$stage2Init" == "/init" ]; then
          echo "DEBUG: '$stage2Init' == '/init'"
          echo "DEBUG: 'targetRoot=$targetRoot'"
          find "$targetRoot/nix/store" -name '*-nixos-system-nixos-*' | while read -r absolute_init_file_path; do
            echo "DEBUG: 'absolute_init_file_path='$absolute_init_file_path'"
            init_file_path="''${absolute_init_file_path#$targetRoot/}"
            echo "DEBUG: 'init_file_path='$init_file_path'"
            echo "DEBUG: test -f '$targetRoot/$init_file_path/init'"
            if [ -f "$targetRoot/$init_file_path/init" ]; then
              ln -v -s "$init_file_path/init" "$targetRoot/init"
              stage2Init="/$init_file_path/init"
              echo "DEBUG: 'stage2Init='$stage2Init'"
              break
            fi
          done
        fi
      '';
    };

    # Networking configuration
    networking = {
      dhcpcd.enable = false;
      wireless.enable = mkImageMediaOverride false;
      networkmanager.enable = true;
      firewall.enable = false;
    };

    # Ensure NetworkManager auto-connects to wired networks immediately
    # This is critical for PXE boot scenarios where network must come up automatically
    systemd.services.NetworkManager-wait-online.enable = true;

    # Configure NetworkManager to manage all ethernet devices automatically
    networking.networkmanager = {
      # Ensure unmanaged devices are empty (manage all by default)
      unmanaged = [];
      # Plugins that may help with automatic connection
      plugins = mkDefault [];
    };

    # Create a default NetworkManager connection profile for auto-connecting to any wired network
    # This matches ANY ethernet interface and automatically connects via DHCP
    # Note: Omitting interface-name makes it match ANY interface
    environment.etc."NetworkManager/system-connections/Wired-Auto.nmconnection" = {
      text = ''
        [connection]
        id=Wired-Auto
        type=ethernet
        autoconnect=true
        autoconnect-priority=999

        [ethernet]

        [ipv4]
        method=auto
        may-fail=false

        [ipv6]
        method=auto
        may-fail=true

        [proxy]
      '';
      mode = "0600";
    };

    # Enable fish shell
    programs.fish.enable = true;

    # Default user configuration
    users.users."nixos" = mkMerge [
      {
        uid = 1000;
        group = "nixos";
        extraGroups = [
          "users"
          "networkmanager"
          "wheel"
        ];
        shell = pkgs.fish;
        openssh.authorizedKeys.keys = cfg.sshAuthorizedKeys;
      }
      # Password configuration (initialPassword for ISO first boot)
      (mkIf (cfg.users.nixos.password != null) {
        initialPassword = cfg.users.nixos.password;
      })
      (mkIf (cfg.users.nixos.hashedPassword != null) {
        initialHashedPassword = cfg.users.nixos.hashedPassword;
      })
    ];

    users.groups."nixos" = {
      gid = 1000;
    };

    # Root user configuration
    users.users."root" = mkMerge [
      {
        openssh.authorizedKeys.keys = cfg.sshAuthorizedKeys;
      }
      # Password configuration (initialPassword for ISO first boot)
      (mkIf (cfg.users.root.password != null) {
        initialPassword = cfg.users.root.password;
      })
      (mkIf (cfg.users.root.hashedPassword != null) {
        initialHashedPassword = cfg.users.root.hashedPassword;
      })
    ];

    # Sudo configuration for nixos user
    security.sudo.extraRules = mkIf cfg.users.nixos.allowSudoWithoutPassword [
      {
        users = ["nixos"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];

    # SSH configuration
    services.openssh = mkIf cfg.ssh.enable {
      enable = true;
      settings = {
        PermitRootLogin = cfg.ssh.permitRootLogin;
        # Auto-disable password auth if SSH keys are provided, unless explicitly overridden
        PasswordAuthentication =
          if cfg.ssh.passwordAuthentication != null
          then cfg.ssh.passwordAuthentication
          else (cfg.sshAuthorizedKeys == []);
      };
    };

    # Auto-track current NixOS release so consumers don't need to set it
    system.stateVersion = lib.trivial.release;
  };
}
