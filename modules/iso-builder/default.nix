{
  config,
  lib,
  pkgs,
  modulesPath,
  utils,
  ...
}:
with lib;
let
  cfg = config.pxe-boot-iso;
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  options.pxe-boot-iso = {
    enable = mkEnableOption "PXE-bootable ISO configuration";

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
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
      default = [ ];
      description = "SSH authorized keys for the nixos user";
      example = [ "ssh-ed25519 AAAAC3Nz... user@host" ];
    };

    kernelPackage = mkOption {
      type = types.raw; # Accept linuxPackages attrset
      default = pkgs.linuxPackages_latest;
      # Without this, `nixosOptionsDoc` tries to deeply evaluate the
      # default VALUE itself (the whole linuxPackages_latest attrset) to
      # render it as markdown -- which pulls in unrelated, unmaintained
      # packages elsewhere in that attrset that may simply not evaluate
      # on a given nixpkgs revision (confirmed: `amdgpu-pro was removed
      # due to lack of maintenance` surfaced this way, nothing to do with
      # this option itself).
      defaultText = literalExpression "pkgs.linuxPackages_latest";
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

    networkDownloadTmpfsSize = mkOption {
      type = types.str;
      default = "2G";
      example = "4G";
      description = ''
        Size of the tmpfs used to stage the network-downloaded ISO during
        initrd (passed as `mount -t tmpfs -o size=...`). Must be large
        enough to hold the whole ISO in RAM.
      '';
    };

    networkDownloadStallTimeoutSec = mkOption {
      type = types.int;
      default = 60;
      example = 120;
      description = ''
        Abort the network ISO download if no data has been received for
        this many seconds (passed to wget as `--read-timeout`). This is a
        STALL timeout, not a total-duration cap: it resets on every byte
        received, so a large ISO on a slow-but-working link can take as
        long as it needs -- only genuine inactivity triggers it.

        Design note: the systemd stage-1 `findiso-download.service` unit
        itself has no total-duration timeout either (no
        `JobRunningTimeoutSec=`) -- this STALL timeout is the only
        safety net against an unbounded hang. On expiry, wget exits
        non-zero, which the service's `OnFailure=emergency.target`
        catches, rather than leaving the boot waiting forever for a
        download that will never finish.
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
        type = types.enum [
          "yes"
          "no"
          "prohibit-password"
          "forced-commands-only"
        ];
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
      {
        # The legacy (scripted) stage-1 `findiso=` download path was
        # removed (confirmed via NixOS Discourse: nixpkgs already
        # defaults `boot.initrd.systemd.enable` to true, with the
        # non-systemd stage-1 on a deprecation path) -- this module's
        # network-download ISO boot now only has a systemd-stage-1
        # implementation. Fail loudly instead of silently producing an
        # ISO whose `findiso=` boot simply does nothing.
        assertion = !cfg.enableNetworkDownload || config.boot.initrd.systemd.enable;
        message = "pxe-boot-iso.enableNetworkDownload requires boot.initrd.systemd.enable = true (the legacy scripted-stage-1 findiso= download path has been removed).";
      }
    ];

    # Enable flakes for modern Nix workflow
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Package selection based on options
    environment.systemPackages =
      with pkgs;
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
      supportedFilesystems = [ "zfs" ];
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

      # DHCP needs an explicit match rule -- systemd-networkd applies no
      # implicit "DHCP on any interface" default the way the (now-removed)
      # legacy scripted stage-1's `udhcpc.enable` did.
      initrd.systemd.network.networks."40-findiso-dhcp" = mkIf cfg.enableNetworkDownload {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "yes";
      };

      # `pkgs.util-linux` and the systemd package here (for `losetup`,
      # `udevadm`, and `systemd-cat`, each referenced by full store path in
      # the service script below) is a DIFFERENT mechanism than the
      # earlier `path = [...]` attempt that conflicted (that one
      # merges packages into a shared bin dir via systemd's PATH
      # construction, which is what collided with the base cd-dvd
      # module's own util-linux variant there -- two derivations both
      # providing bin/setarch). `storePaths` instead just copies each
      # listed closure's real files into the initrd verbatim, no
      # merging, so it doesn't hit that conflict.
      initrd.systemd.storePaths = mkIf cfg.enableNetworkDownload [
        "${pkgs.wget}/bin/wget"
        "${pkgs.util-linux}/bin/losetup"
        "${pkgs.util-linux}/bin/mount"
        "${config.boot.initrd.systemd.package}/bin/udevadm"
        "${config.boot.initrd.systemd.package}/bin/systemctl"
        "${config.boot.initrd.systemd.package}/bin/systemd-cat"
      ];

      # NixOS's own ISO module finds the ISO via udev by-label
      # (`/dev/disk/by-label/<volumeID>`, see iso-image.nix), so this
      # attaches the downloaded ISO as a loop device and lets udev assign
      # it the same label, making it indistinguishable from a real
      # labeled ISO device to everything else NixOS's base cd-dvd module
      # already does for a normal (non-network) boot.
      initrd.systemd.services.findiso-download = mkIf cfg.enableNetworkDownload {
        description = "Download ISO over network (findiso=http(s)://...) and expose it as a labeled loop device";
        # NOT initrd-root-device.target: under systemd stage-1, nixpkgs'
        # own cd-dvd module (iso-image.nix) makes `/` plain tmpfs (no
        # backing device at all) and instead mounts the ISO itself at
        # `/iso` as a regular `neededForBoot` filesystem -- which
        # `nixos/modules/tasks/filesystems.nix` turns into an
        # `x-initrd.mount` fstab entry, i.e. a `sysroot-iso.mount` unit
        # pulled in (via Requires=) by `initrd-fs.target`, NOT by
        # `initrd-root-device.target` (that target is for an actual
        # root block device, which this boot design never has).
        wantedBy = [ "sysroot-iso.mount" ];
        before = [ "sysroot-iso.mount" ];
        after = [
          "systemd-udevd.service"
          "systemd-networkd-wait-online.service"
        ];
        wants = [ "systemd-networkd-wait-online.service" ];
        unitConfig = {
          DefaultDependencies = false;
          # The real stall/retry protection lives in wget's own
          # `--read-timeout` (see script below) -- it self-terminates
          # in a bounded, calculable worst case (wget's default
          # `--tries=20`) rather than needing an external time-based
          # cap here. This just makes that definitive failure actually
          # DO something: without it, nothing tells the device-wait
          # job (`sysroot-iso.mount` waiting on the by-label `.device`
          # unit below) that this service already gave up for good --
          # it would otherwise wait forever for a device that will
          # never appear. `emergency.target` matches the same failure
          # target `sysroot-iso.mount` itself already cascades into on
          # a device-wait timeout (see the comment on that `.device`
          # unit drop-in further below).
          OnFailure = [ "emergency.target" ];
        };
        # `StandardError = "tty"` (not `journal+console`, the systemd
        # default): wget writes its progress bar AND all other status
        # messages to stderr. `journal`-family output is an AF_UNIX
        # stream socket read by journald, which only splits log
        # records on newlines/NUL (or a 48K byte safety cutoff) --
        # wget's bare `\r`-redraw progress updates would NOT render
        # live through that, only as an occasional large blob
        # (verified against systemd-journald's own stream-logging
        # docs). A real tty fd (this setting) is the only way to get
        # a genuinely live-updating bar on the physical console.
        # `StandardOutput` stays on `journal+console` so the script's
        # own informative `echo` lines (loop device attach message,
        # etc.) still land in the journal -- systemd's
        # `StandardOutput=`/`StandardError=` are independent settings,
        # so this doesn't lose that.
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardOutput = "journal+console";
          StandardError = "tty";
          TTYPath = "/dev/console";
        };
        # `losetup`/`udevadm`/`systemd-cat` are invoked by full store
        # path (see the storePaths comment above) rather than added to
        # `path`, since they're not actually reachable on PATH here.
        path = [
          pkgs.wget
          pkgs.gnugrep
          pkgs.coreutils
        ];
        script = ''
          download_iso_file="$(grep -Eo 'findiso=http(s)?://[^ ]+' /proc/cmdline | cut -d= -f2-)"
          if [ -n "$download_iso_file" ]; then
            mkdir -p /run/findiso
            # D36: idempotent -- without this guard, a second
            # invocation of this script (e.g. a manual
            # `systemctl restart findiso-download.service`) would
            # mount a SECOND tmpfs layer on top of the first,
            # shadowing (not deleting, but making inaccessible) any
            # partial download the first layer held -- silently
            # defeating wget's `--continue` resume below. Checking
            # `/proc/mounts` (not `mountpoint`, which isn't in this
            # unit's `path`) for an EXACT "/run/findiso" mountpoint
            # field (space-anchored on both sides) before mounting
            # again.
            if ! grep -q ' /run/findiso ' /proc/mounts; then
              # Explicit sized tmpfs (not bare ambient /run): bare
              # /run is itself already tmpfs but uncapped, so a
              # malicious or oversized download could fill it. Full
              # store path (not bare `mount`): this unit's
              # `path = [...]` deliberately excludes `pkgs.util-linux`
              # (see the `storePaths` comment above -- colliding
              # `bin/setarch` providers), so `mount` is only
              # reachable this way.
              ${pkgs.util-linux}/bin/mount -t tmpfs -o size=${cfg.networkDownloadTmpfsSize} tmpfs /run/findiso
            fi
            wget \
              --continue \
              --read-timeout=${toString cfg.networkDownloadStallTimeoutSec} \
              --progress=bar:force:noscroll \
              -O /run/findiso/nixos_live.iso "$download_iso_file" \
              || {
                # One deliberate, synchronous log line on definitive
                # failure -- not a live tee of the whole stream (that
                # was investigated and rejected: real but avoidable
                # extra failure surface in the hardest-to-debug boot
                # stage, for low payoff over this one line).
                echo "findiso-download: wget failed with exit $?" \
                  | ${config.boot.initrd.systemd.package}/bin/systemd-cat -t findiso-download -p err
                exit 1
              }
            loop_device="$(${pkgs.util-linux}/bin/losetup -f --show /run/findiso/nixos_live.iso)"
            echo "findiso-download: attached loop device: $loop_device"
            # losetup's own "add" uevent doesn't reliably trigger udev's
            # blkid-based filesystem-label probing for a freshly attached
            # loop device -- plain `udevadm settle` only waits for
            # already-queued events, it doesn't request a fresh scan, so
            # /dev/disk/by-label/<volumeID> never appears without an
            # explicit re-trigger first. `--name-match="$loop_device"`
            # alone didn't make systemd create the by-label .device unit;
            # `--subsystem-match=block` (re-triggering every block
            # device, cheap this early in boot) is what actually worked.
            ${config.boot.initrd.systemd.package}/bin/udevadm trigger --action=add --subsystem-match=block --settle
            ${config.boot.initrd.systemd.package}/bin/udevadm settle
          fi
        '';
      };

      # `sysroot-iso.mount` (generated by systemd-fstab-generator from
      # `fileSystems."/iso"` below) waits for its backing by-label device
      # using systemd's DEFAULT 90s device timeout. findiso-download above
      # legitimately needs longer than that -- DHCP/network-online first,
      # then a multi-hundred-MB-to-multi-GB HTTP download of the whole ISO
      # -- so without this, the device-wait job times out, cascades
      # (sysroot-iso.mount -> initrd-fs.target -> OnFailure=) into
      # `emergency.target` with the real boot CANCELED, well before
      # findiso-download actually finishes (it keeps running and does
      # succeed, just too late to matter: confirmed via `systemd.log_level
      # =debug` on the console showing "Timed out waiting for device
      # /dev/disk/by-label/<volumeID>" immediately followed by "Dependency
      # failed for /sysroot/iso" at exactly the 90s mark, in every run
      # where the real download took longer than that).
    };

    # NOT `fileSystems."/iso".options` (tried first, silently had zero
    # effect, confirmed via a minimal `lib.evalModules` repro): this repo's
    # `installation-cd-minimal.nix` import chain sets the ENTIRE
    # `fileSystems` option -- not per-key -- via `fileSystems = lib.
    # mkImageMediaOverride config.lib.isoFileSystems;` in nixpkgs' own
    # `installation-cd-base.nix` (`mkImageMediaOverride` = `mkOverride 60`
    # on the WHOLE attrset of all mountpoints). Once ANY module provides a
    # submodule-typed option as one priority-wrapped whole value like that,
    # NixOS's module system drops EVERY sibling module's contribution to
    # that option wholesale (confirmed: even a brand-new, non-conflicting
    # fileSystems key from a separate module silently vanished). Matching
    # or beating that priority would mean duplicating iso-image.nix's
    # entire fileSystems attrset (fragile against upstream changes) just to
    # tweak one mount option.
    #
    # ALSO NOT `boot.initrd.systemd.mounts` + `mountConfig.TimeoutSec`
    # (tried second, built and evaluated cleanly, but had NO effect on the
    # actual hang either -- confirmed via the real E2E test, same 90s
    # timeout). Root-caused by reading systemd's own fstab-generator source
    # (`generator_write_device_timeout` in src/shared/generator.c):
    # `TimeoutSec=` in a `[Mount]` section bounds how long the `mount(8)`
    # COMMAND itself may run, not how long to wait for the backing device
    # to show up first -- a completely different wait, controlled by
    # `JobRunningTimeoutSec=` in the `[Unit]` section of the DEVICE unit
    # (not the mount unit). `x-systemd.device-timeout=` in fstab is just
    # sugar that writes exactly that device-unit drop-in for you; since
    # `fileSystems` is unavailable to us (see above), we write the
    # equivalent drop-in ourselves, directly, at the same unit the real
    # option would have targeted.
    #
    # Set to "infinity", not a larger finite number: device units are the
    # ONE kind of unit where `JobRunningTimeoutSec=`'s own default isn't
    # "infinity" like everywhere else, it's `DefaultDeviceTimeoutSec=`
    # (systemd's compiled-in 90s) -- simply deleting this drop-in would
    # silently revert to that same 90s default and reintroduce the
    # original bug, not remove the cap. A time-based cap here was the
    # wrong tool anyway: it can't distinguish "stalled" from "slow but
    # legitimately still downloading", which is exactly the distinction
    # wget's own `--read-timeout` (networkDownloadStallTimeoutSec, above)
    # makes correctly. Removing the cap here is safe specifically because
    # `findiso-download.service`'s `OnFailure=` (above) now handles the
    # "this will never succeed" case directly and promptly the moment
    # wget's own bounded retry budget is exhausted -- this unit no longer
    # needs its own guess at how long is "too long".
    boot.initrd.systemd.units."${utils.escapeSystemdPath "/dev/disk/by-label/${config.isoImage.volumeID}"}.device" =
      mkIf cfg.enableNetworkDownload {
        overrideStrategy = "asDropinIfExists";
        text = ''
          [Unit]
          JobRunningTimeoutSec=infinity
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
      unmanaged = [ ];
      # Plugins that may help with automatic connection
      plugins = mkDefault [ ];
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
        users = [ "nixos" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
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
          if cfg.ssh.passwordAuthentication != null then
            cfg.ssh.passwordAuthentication
          else
            (cfg.sshAuthorizedKeys == [ ]);
      };
    };

    # Auto-track current NixOS release so consumers don't need to set it
    system.stateVersion = lib.trivial.release;
  };
}
