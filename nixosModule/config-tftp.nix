{
  lib,
  pkgs,
  config,
  netLib,
  ...
}:
let
  cfg = config.my.router;

  # Single source of truth for the HTTP port serving boot files + ISOs --
  # both the Rust-written config.json (http.port, consumed by
  # pxe-boot-prepare to build GRUB entry URLs) and the Nix-generated
  # nginx vhost (listen.port) must agree on this, or GRUB entries would
  # point at a port nginx isn't actually listening on.
  httpPort = 1337;

  iso_folder_path = cfg.pxe-boot.isoFolderPath;

  # Nix-store-sourced ISOs (`cfg.pxe-boot.nixIsos`) are exposed via one
  # `systemd.tmpfiles.rules "L+"` symlink pointing at a `linkFarm` of all
  # of them -- atomic and generation-pinned: removing a package from the
  # list just changes what the farm (and so this whole directory)
  # contains on the next switch, so no per-ISO symlink can be orphaned.
  nix_isos_dir = cfg.pxe-boot.nixIsosDir;
  nix_isos_farm = pkgs.linkFarm "pxe-nix-isos" (
    map (p: {
      name = p.name;
      # `p` is the ISO-builder derivation itself, whose output directory
      # is `$out/iso/<isoName>` (hardcoded by nixpkgs'
      # `make-iso9660-image.nix`/.sh) -- `p` alone points at that
      # directory, not the `.iso` file inside it. `p.name` already equals
      # `isoName` (this module sets `image.fileName = lib.mkForce "...";`,
      # which becomes the derivation's plain `name`), so the real file is
      # always `${p}/iso/${p.name}`.
      #
      # Caveat: this breaks if a `nixIsos` package has `isoImage.compressImage
      # = true` -- the output file becomes `${p.name}.zst` while `p.name`
      # (and this `path`) still points at the uncompressed name.
      # `modules/iso-builder` (this project's own ISO builder, the
      # intended/common source for `nixIsos` entries) asserts against this
      # at evaluation time -- see its `assertions` list. An arbitrary
      # THIRD-PARTY package not built via that module is NOT covered by
      # that guard, since `nixIsos`'s type (`types.listOf types.package`)
      # accepts any package.
      path = "${p}/iso/${p.name}";
    }) cfg.pxe-boot.nixIsos
  );

  # Every directory pxe-boot-prepare should scan for ISOs: the
  # user-managed manual directory, plus the Nix-managed farm above when
  # any nixIsos are actually configured (the farm/symlink only exists in
  # that case -- see the `systemd.tmpfiles.rules` entry below).
  iso_folder_paths = [
    (builtins.toString iso_folder_path)
  ]
  ++ lib.optional (cfg.pxe-boot.nixIsos != [ ]) nix_isos_dir;

  pxe_boot_folder = cfg.tftpServer.root;

  # `dhcp.server.tftpServerRoot` overrides the global root for just that
  # interface; both still get the same `<root>/<id>` subdirectory layout.
  rootFor =
    dhcp_interface_conf:
    if dhcp_interface_conf.dhcp.server.tftpServerRoot != null then
      dhcp_interface_conf.dhcp.server.tftpServerRoot
    else
      pxe_boot_folder;

  # Shell-safe form of `rootFor dhcp_interface_conf}/${id}`, for splicing
  # into bash scripts below. `rootFor`/`tftpServerRoot` are
  # operator-supplied `types.path` values -- a value containing
  # `$(...)`, backticks, or an embedded `"` would otherwise be
  # interpreted by bash despite surrounding double quotes (which only
  # suppress word-splitting/globbing, not command substitution).
  escapedRootFor =
    dhcp_interface_conf:
    lib.escapeShellArg "${rootFor dhcp_interface_conf}/${builtins.toString dhcp_interface_conf.dhcp.server.id}";

  functions-general = import ./functions/general.nix {
    inherit
      pkgs
      lib
      config
      netLib
      ;
  };
  inherit (functions-general)
    cfgSetDhcpServerInterfaceOnlyFilter
    ;

  ipv4_fn = import ./functions/ipv4.nix { inherit lib netLib; };
  inherit (ipv4_fn)
    fromCidrString
    ;

  pxeBootInterfaces = cfgSetDhcpServerInterfaceOnlyFilter (
    dhcp_interface_conf: dhcp_interface_conf.dhcp.server.pxe-boot.enable
  );

  # Opt-in only (`== true`, not `!= false` as below): a standalone interface
  # must not silently inherit the pxe-boot-enabled case's default-on behavior
  # just because `tftpServer` is left unset.
  standaloneTftpInterfaces = cfgSetDhcpServerInterfaceOnlyFilter (
    dhcp_interface_conf:
    !dhcp_interface_conf.dhcp.server.pxe-boot.enable
    && dhcp_interface_conf.dhcp.server.tftpServer == true
  );

  tftpServerInterfaces =
    (lib.lists.filter (
      dhcp_interface_conf: dhcp_interface_conf.dhcp.server.tftpServer != false
    ) pxeBootInterfaces)
    ++ standaloneTftpInterfaces;

  tftpServerOptedOutInterfaces = lib.lists.filter (
    dhcp_interface_conf: dhcp_interface_conf.dhcp.server.tftpServer == false
  ) pxeBootInterfaces;

  # Build the Rust pxe-boot-prepare binary
  pxe-boot-prepare-pkg = pkgs.callPackage ./../packages/pxe-boot-prepare/package.nix { };

  # Generate JSON configuration from NixOS options
  pxe-config = pkgs.writeText "pxe-boot-config.json" (
    builtins.toJSON {
      iso_folder_paths = iso_folder_paths;
      tftp_root = builtins.toString pxe_boot_folder;
      runtime_root = "/run/pxe-boot";

      dhcp_interfaces = lib.forEach pxeBootInterfaces (
        dhcp_interface_conf:
        let
          dhcp_server = dhcp_interface_conf.dhcp.server;
          gateway = (fromCidrString dhcp_server.address).address;
        in
        {
          id = dhcp_server.id;
          name = dhcp_interface_conf.interfaceName;
          gateway = gateway;
          default_iso =
            if dhcp_server.pxe-boot.defaultIso != "" then dhcp_server.pxe-boot.defaultIso else null;
          default_script =
            if dhcp_server.pxe-boot.defaultScriptName != "" then
              dhcp_server.pxe-boot.defaultScriptName
            else
              null;
        }
        // lib.attrsets.optionalAttrs (dhcp_server.tftpServerRoot != null) {
          tftp_root = builtins.toString dhcp_server.tftpServerRoot;
        }
      );

      autoinstall = lib.attrsets.mapAttrs (
        isoName: scripts:
        lib.forEach scripts (script: {
          name = script.scriptName;
          script_path =
            if builtins.isString script.script then
              "${pkgs.writeText script.scriptName script.script}"
            else
              "${script.script}";
        })
      ) cfg.pxe-boot.autoinstall;

      http = {
        port = httpPort;
      };
    }
  );

  main_ipxe_file_fn = (
    pxe_host:
    pkgs.writeText "main-ID.ipxe" ''
      #!ipxe

      set tftp-server ${pxe_host}

      goto ''${platform}


      :pcbios
      echo Booting Legacy Bios (platform: ''${platform})
      chain tftp://''${tftp-server}/grub.pxe
      goto exit


      :efi
      echo Booting UEFI (platform: ''${platform})
      # Boot the Microsoft-signed shim first, NOT grubx64.efi directly:
      # shim is what real Secure-Boot-enabled firmware trusts out of the
      # box (its cert is in every standard UEFI CA db); shim then verifies
      # grubx64.efi against its OWN embedded Canonical cert before
      # chain-loading it. Skipping straight to grubx64.efi (the previous
      # behavior here) would fail entirely on real SB-enabled hardware,
      # since firmware never trusts Canonical's cert directly. Verified by
      # a dedicated Secure-Boot E2E test (see tests/pxe-boot/secure-boot.nix).
      chain tftp://''${tftp-server}/bootx64.efi
      goto exit


      :exit
    ''
  );

  signed-grub = cfg.pxe-boot.shimPackage;
in
lib.mkMerge [
  (lib.mkIf cfg.pxe-boot.enable {
    # Previously unreachable on any deployed router's own PATH -- an
    # operator debugging PXE boot (checking `list`/`status` output, or
    # running `prepare`/`cleanup` manually) had no way to invoke it
    # without knowing its Nix store path.
    environment.systemPackages = [ pxe-boot-prepare-pkg ];

    # Explicit rather than relying on on-demand module auto-loading at
    # mount time -- cheap insurance, and avoids a dependency on udev's
    # module-alias auto-load path working correctly this early in boot.
    # Consumers don't have to remember this themselves.
    boot.kernelModules = [
      "iso9660"
      "loop"
    ];

    # Re-run pxe-boot-prepare whenever the manually-managed ISO directory
    # changes, instead of requiring an operator to manually restart the
    # service (or wait for the next switch) after copying in a new ISO.
    # `PathChanged=` fires only on IN_CLOSE_WRITE (a writer closing the
    # file after finishing), not on every write -- an in-progress
    # multi-GB copy doesn't trigger a premature, partial run. No extra
    # debounce layer on top: `prepare()`'s own steps are all idempotent,
    # so a batch of simultaneous file changes causing a few redundant
    # re-runs is harmless, not worth the complexity of building a real
    # debounce mechanism to avoid.
    systemd.paths.pxe-boot-prepare-auto-refresh = {
      wantedBy = [ "paths.target" ];
      pathConfig = {
        Unit = "pxe-boot-prepare.service";
        PathChanged = [ iso_folder_path ] ++ lib.optional (cfg.pxe-boot.nixIsos != [ ]) nix_isos_dir;
      };
    };

    assertions = [
      {
        assertion = lib.lists.allUnique (map (p: p.name) cfg.pxe-boot.nixIsos);
        message = ''
          my.router.pxe-boot.nixIsos: two or more packages share the same
          `name` -- `nix_isos_farm`'s `linkFarm` entries are keyed by
          name, so one would silently shadow the other instead of both
          being served. Give each package a distinct `image.fileName`.
        '';
      }
    ];

    warnings =
      lib.forEach
        (lib.lists.filter (
          dhcp_interface_conf: !dhcp_interface_conf.dhcp.server.pxe-boot.disableTftpServerWarning
        ) tftpServerOptedOutInterfaces)
        (dhcp_interface_conf: ''
          my.router: dhcp.server.tftpServer = false for interface
          "${dhcp_interface_conf.interfaceName}" -- this router will NOT run its
          own TFTP server for that subnet. The grub/iPXE files are still staged
          at "${rootFor dhcp_interface_conf}/${builtins.toString dhcp_interface_conf.dhcp.server.id}";
          you are responsible for serving that directory over TFTP yourself.
        '');

    systemd.services = {
      "pxe-boot-main-script" = {
        enable = true;
        description = "PXE Boot - Copy GRUB Binaries";
        after = [
          "network.target"
          "pxe-boot-prepare.service"
        ];
        path = with pkgs; [ rsync ];
        script = ''
          set -eu
          set -x

          pids=()
          failed=0
        ''
        + lib.strings.concatMapStrings (
          dhcp_interface_conf:
          let
            dhcp_server = dhcp_interface_conf.dhcp.server;
            gateway = (fromCidrString dhcp_server.address).address;
          in
          ''
            # `lib.escapeShellArg`: `rootFor`/`tftpServerRoot` are
            # operator-supplied `types.path` values spliced directly into
            # this script -- a value containing `$(...)`, backticks, or
            # an embedded `"` would otherwise be interpreted by bash
            # despite the surrounding double quotes (which only suppress
            # word-splitting/globbing, not command substitution).
            IPXE_BOOT_FOLDER_PATH=${escapedRootFor dhcp_interface_conf}
            mkdir -p "$IPXE_BOOT_FOLDER_PATH"
            rsync "${main_ipxe_file_fn gateway}" "$IPXE_BOOT_FOLDER_PATH/main.ipxe" &
            pids+=("$!")
            # `--chmod=Du+w` keeps the destination directories owner-writable.
            # Without it, `rsync -a` mirrors the read-only nix-store mode onto
            # "$IPXE_BOOT_FOLDER_PATH", and pxe-boot-prepare (which runs with a
            # CapabilityBoundingSet of only CAP_SYS_ADMIN, i.e. no CAP_DAC_OVERRIDE)
            # can then no longer create the "grub/" subdirectory for grub.cfg.
            rsync -a --chmod=Du+w --checksum "${signed-grub}/." "$IPXE_BOOT_FOLDER_PATH/." &
            pids+=("$!")
          ''
        ) pxeBootInterfaces
        + ''
          # A bare `wait` with no args returns only the LAST job's exit
          # status -- an earlier interface's failed rsync would be
          # silently swallowed even under `set -e`. Wait on every
          # backgrounded job explicitly instead, and fail if any did.
          for pid in "''${pids[@]}"; do
            wait "$pid" || failed=1
          done
          if [ "$failed" -ne 0 ]; then
            echo "pxe-boot-main-script: one or more rsync jobs failed" >&2
            exit 1
          fi
        '';
        wantedBy = [ "multi-user.target" ];
        # C23: unlike pxe-boot-prepare.service (which can't use
        # ProtectKernelModules/a private mount namespace -- see that
        # unit's own comment -- because it calls mount() itself and
        # needs the result visible to OTHER processes), this unit does
        # a plain `mkdir -p` + `rsync` into possibly-operator-configured
        # paths and never mounts anything, so it can safely take the
        # full standard hardening set with no mount-namespace conflict.
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          ProtectSystem = "strict";
          ProtectHome = true;
          # `ReadWritePaths` must cover every path `rootFor`
          # (`rsync`'s own destination) can resolve to across ALL
          # pxeBootInterfaces -- the global default plus every
          # per-interface `tftpServerRoot` override.
          ReadWritePaths = lib.lists.unique (
            map (dhcp_interface_conf: rootFor dhcp_interface_conf) pxeBootInterfaces
          );
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          # No network needed at all: this unit only rsyncs from the
          # local Nix store to local disk.
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
          NoNewPrivileges = true;
          SystemCallFilter = [ "@system-service" ];
          SystemCallArchitectures = "native";
        };
      };

      "pxe-boot-prepare" = {
        enable = true;
        description = "PXE Boot - Prepare";
        after = [
          "network.target"
        ];
        # nginx must not start accepting connections (and serving a
        # stale/empty /run/pxe-boot) before this has populated it.
        # `Before=` alone is sufficient here -- systemd automatically
        # mirrors it as an implicit `After=` on nginx.service, and both
        # units already reach multi-user.target independently via their
        # own `wantedBy`, so this only fixes relative ordering, not
        # whether either one starts.
        before = [ "nginx.service" ];
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

          # `PrivateDevices=false` stays -- mounting a loop device
          # genuinely needs access to /dev/loop*, there's no narrower
          # systemd knob for "allow /dev/loop* specifically".
          PrivateDevices = false;

          # `ProtectKernelModules=true` was tried and rolled back:
          # confirmed empirically (real E2E run) that it makes
          # `/run/pxe-boot/iso-mountpoint/<iso>` appear EMPTY to every
          # OTHER process on the host (nginx, this test's own shell),
          # even though pxe-boot-prepare's own `mount()` call itself
          # reports success. Root cause: making `/usr/lib/modules`
          # inaccessible (this option's whole purpose) requires setting
          # up a file system namespace for the unit -- which means this
          # service's own `mount(2)` calls land in a PRIVATE mount
          # namespace, never propagating to the host's root namespace at
          # all. That's a fundamental incompatibility, not something
          # preloading kernel modules can work around: this service's
          # entire job is to create mounts other processes must see.
          ProtectKernelModules = false;

          # The capability this service actually needs
          # (CAP_SYS_ADMIN, granted via Ambient/CapabilityBoundingSet
          # above) is inherited across exec() without requiring any
          # setuid/file-capability binary -- there is nothing here that
          # needs privilege ESCALATION beyond what's already granted.
          NoNewPrivileges = true;

          # This service runs as root (no User=/DynamicUser=) with no
          # explicit permissions set on the directories it creates under
          # `/run/pxe-boot` -- without this, their mode is whatever the
          # host's ambient umask happens to resolve to (typically 0755,
          # but never actually guaranteed in code). nginx's fixed-user
          # (not DynamicUser) serving process depends on being able to
          # read that tree; this makes the requirement explicit instead
          # of incidental.
          UMask = "0022";

          # C24: every OTHER systemd sandboxing knob with "Protect"/
          # "Private"/"Restrict[Namespaces|...]" in its name that
          # implies setting up a private mount namespace for the unit
          # hits the exact same incompatibility `ProtectKernelModules`
          # above already hit (and is deliberately left `false` with a
          # full explanation) -- this service's own mount() calls MUST
          # land in the host's root mount namespace, visible to nginx
          # and everything else. Only knobs confirmed namespace-
          # independent (pure seccomp/process-attribute restrictions,
          # not mount-based) are added here.
          #
          # No network code anywhere in this binary (confirmed: no
          # TcpStream/UdpSocket/HTTP client) -- AF_UNIX is still allowed
          # for local IPC/NSS lookups, not because this service uses
          # sockets itself.
          RestrictAddressFamilies = [ "AF_UNIX" ];
          # `@system-service` is systemd's own curated baseline, but it
          # explicitly EXCLUDES the `@mount` syscall group (mount/umount2/
          # pivot_root/...) -- re-added explicitly since this service's
          # entire purpose is calling mount()/umount().
          SystemCallFilter = [
            "@system-service"
            "@mount"
          ];
          SystemCallArchitectures = "native";
          # Blocks the unit from creating NEW namespaces itself
          # (unshare/setns/clone with namespace flags) -- unrelated to
          # whether ITS OWN mount()/umount() calls propagate normally
          # (that's governed by the ABSENCE of a namespace being set up
          # FOR this unit, which none of the knobs here create).
          RestrictNamespaces = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
        };
      };
    };

    # Single nginx vhost serving everything under `/run/pxe-boot`:
    # the GRUB/kernel/initrd tree at the root, loop-mounted ISO
    # contents under `iso-mountpoint/`, autoinstall seeds under
    # `unattented-install/`, and raw whole-ISO downloads under
    # `isos/` (`iso::ServeTree`'s canonical symlink tree) -- all
    # already nested under the same `runtime_root`, so one `root`
    # covers every case with no per-path `alias` needed. Replaces the
    # previous two separate `darkhttpd` instances (ports 1337/1338),
    # which existed only because darkhttpd serves exactly one root
    # per process; nginx supports multiple/nested roots natively.
    services.nginx = {
      enable = true;
      virtualHosts."pxe-boot" = {
        # One `listen` entry per PXE-enabled interface's own gateway
        # address -- never `0.0.0.0` -- same per-interface-binding
        # pattern `services.unbound` already uses in config-dns.nix, so
        # this vhost is never reachable from a non-PXE-enabled interface
        # (e.g. a WAN-facing one).
        listen = lib.forEach pxeBootInterfaces (dhcp_interface_conf: {
          addr = (fromCidrString dhcp_interface_conf.dhcp.server.address).address;
          port = httpPort;
        });
        # Inherited by every location below, so `/isos/` -- served by a
        # more specific location purely to attach a rate limit -- still
        # resolves against the same canonical tree.
        root = "/run/pxe-boot";
        locations."/" = { };
        # Raw whole-ISO downloads (potentially 1GB+, e.g. a client's own
        # `findiso=` fetch, or an operator/this-project's-own-E2E-test
        # manually downloading one) can run concurrently with OTHER
        # clients' latency-sensitive GRUB kernel/initrd fetches on this
        # same vhost -- confirmed via the real E2E test: GRUB's legacy
        # BIOS/SeaBIOS PXE network driver (unlike the more robust UEFI/OVMF
        # stack) failed to even send its `initrd` request
        # (`grub_pxe_send: couldn't send network packet`) while a bulk
        # ISO transfer was in flight on the same nginx worker, reproducible
        # across multiple runs and unaffected by `keepalive_timeout`/
        # `sendfile` tuning (ruled out as the cause). Capping the bulk
        # path's rate keeps it from starving the small, latency-sensitive
        # requests sharing the same process -- separate darkhttpd
        # processes (what this replaced) had this isolation for free by
        # being on entirely different processes; this is the equivalent
        # protection within one process. `isoDownloadRateLimit` defaults
        # to `null` (unlimited): real routers typically have enough
        # cores that this never actually contends -- only this project's
        # own single-vCPU E2E test needs it set.
        locations."/isos/" = lib.mkIf (cfg.pxe-boot.isoDownloadRateLimit != null) {
          extraConfig = ''
            limit_rate ${cfg.pxe-boot.isoDownloadRateLimit};
          '';
        };
        # Route the access log to the journal via nginx's native syslog
        # log target (NOT a `/dev/stdout`/`/proc/self/fd/1` reopen of
        # nginx's own stdout -- confirmed via the real E2E test that
        # BOTH fail identically with `open() ... failed (6: No such
        # device or address)`: systemd's own docs state a journal-backed
        # stdout "will be an AF_UNIX stream socket, and not a pipe or
        # FIFO that can be reopened" -- nginx's `open()` on any path
        # resolving to that socket can never succeed, regardless of
        # `PrivateDevices`/sandboxing; this is a hard systemd+journald
        # architectural constraint, not a permissions problem). `/dev/log`
        # is systemd-journald's own classic syslog-compatible socket,
        # reachable the normal way nginx already knows how to log to one.
        extraConfig = ''
          access_log syslog:server=unix:/dev/log,tag=nginx_pxe_boot;
        '';
      };
    };

    # `L+`: atomic, generation-pinned symlink -- see `nix_isos_farm`
    # above. Only created when at least one nixIsos package is
    # configured; `iso_folder_paths` only references this directory in
    # that same case (see above), so pxe-boot-prepare's own hard
    # existence-check on every listed source directory never trips over
    # a path that was never meant to exist.
    #
    # `tftp_root`/`runtime_root` below are unconditional: pxe-boot-prepare's
    # `validate()` hard-checks both for existence before doing any work
    # (fail-fast against a genuinely missing custom mount, not "please
    # auto-create a fresh directory for me" -- see validation.rs). Until
    # now, nothing deterministically created them -- `/srv/pxeboot` only
    # ever existed by the ACCIDENTAL timing of some unrelated service's
    # own `mkdir -p` side effect finishing first (confirmed: moving
    # pxe-boot-prepare.service earlier via the nginx-ordering fix above
    # exposed exactly this latent race, where it previously happened to
    # start late enough -- waiting on nginx -- to not matter). `d` entries
    # run via systemd-tmpfiles-setup.service, ordered well before
    # multi-user.target, making both paths exist deterministically
    # regardless of service start order.
    systemd.tmpfiles.rules = [
      "d ${builtins.toString pxe_boot_folder} 0755 root root -"
      "d /run/pxe-boot 0755 root root -"
    ]
    ++ lib.optional (cfg.pxe-boot.nixIsos != [ ]) "L+ ${nix_isos_dir} - - - - ${nix_isos_farm}"
    # Same rationale as the unconditional `pxe_boot_folder` rule above,
    # but for PER-INTERFACE `tftpServerRoot` overrides: those were
    # previously only ever created by pxe-boot-main-script.service's own
    # `mkdir -p`, which runs AFTER pxe-boot-prepare.service (see that
    # unit's `after` below) -- so a custom override path never existed
    # yet by the time pxe-boot-prepare's own validate() hard-checks it
    # (added alongside the global check; see validation.rs), failing the
    # unit on every boot. Reproduced directly: the E2E test's eth5
    # fixture (tftpServerRoot override) failed exactly this way.
    ++ lib.lists.map (
      dhcp_interface_conf:
      "d ${builtins.toString dhcp_interface_conf.dhcp.server.tftpServerRoot} 0755 root root -"
    ) (lib.lists.filter (d: d.dhcp.server.tftpServerRoot != null) pxeBootInterfaces);
  })

  # A separate mkMerge entry, not folded into the block above: standalone
  # TFTP must come up even when `cfg.pxe-boot.enable` (the whole block
  # above's gate) is false.
  (lib.mkIf (tftpServerInterfaces != [ ]) {
    systemd.services = builtins.listToAttrs (
      lib.lists.forEach tftpServerInterfaces (dhcp_interface_conf: {
        name = "pxe-boot-tftp-server-for-interface-${dhcp_interface_conf.interfaceName}";
        value = {
          enable = true;

          description = "TFTP Server";
          after = [
            "network.target"
            "network-online.target"
          ]
          # Only for interfaces pxe-boot-main-script.service actually
          # stages content for (pxeBootInterfaces, not purely-standalone
          # tftpServer=true ones) -- same ordering-race class of bug
          # already fixed for pxe-boot-prepare.service/nginx.service:
          # without this, atftpd can start serving a subnet's TFTP root
          # before rsync has copied grub.pxe/bootx64.efi/etc. into it,
          # and a PXE client requesting those files microseconds after
          # power-on gets a plain "file not found" with no useful
          # correlation in the journal. `After=` on a service that
          # doesn't exist in the standalone-only case is a harmless
          # no-op for systemd, but we only add it where it's meaningful.
          ++ lib.optional dhcp_interface_conf.dhcp.server.pxe-boot.enable "pxe-boot-main-script.service";
          wants = [
            "network-online.target"
          ]
          ++ lib.optional dhcp_interface_conf.dhcp.server.pxe-boot.enable "pxe-boot-main-script.service";
          wantedBy = [ "multi-user.target" ];
          # runs as nobody
          script = ''
            set -eu
            set -x

            # Standalone use (no pxe-boot on this interface) never runs
            # pxe-boot-main-script, which would otherwise create this.
            mkdir -p ${escapedRootFor dhcp_interface_conf}

            ip_addr_json="$(${pkgs.iproute2}/bin/ip --json addr show dev ${dhcp_interface_conf.interfaceName})"
            ip_address="$(
              printf '%s\n' "$ip_addr_json" \
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
              ${escapedRootFor dhcp_interface_conf}
          '';

          serviceConfig = {
            Restart = "always";
            RestartSec = "10s";
          };
        };
      })
    );
  })
]
