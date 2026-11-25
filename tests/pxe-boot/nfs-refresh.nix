{
  pkgs ? import <nixpkgs> { },
  nixosModule ? ../../.,
}:
###########################################################################
# NFS: adding, changing and removing an ISO must not disturb the others
###########################################################################
#
# A client installing over NFS reads its ISO for many minutes. When another
# ISO is copied into (or removed from) the ISO folder, the router refreshes
# its mounts, exports and menus; that must leave the ISO being read alone.
# Restarting pxe-boot-prepare for it unexported and unmounted every ISO, and
# the client got "Stale file handle".
#
# The router mounts its own export (as nixos-nfs.nix does for the installer
# repo path) and a reader keeps one file of it open and re-reads it every
# 200 ms while the folder changes underneath.
###########################################################################
let
  routerIp = "192.168.90.1";
  isoFolder = "/var/lib/pxe-isos";
  mountRoot = "/run/pxe-boot/iso-mountpoint";

  keepIso = "rhel-9.6-x86_64-dvd.iso";
  newIso = "rhel-9.5-x86_64-dvd.iso";
  otherIso = "rhel-9.4-x86_64-dvd.iso";

  # Mock RHEL ISO with an installer image (so it is served over NFS) whose
  # content names the ISO, and is big enough for real reads.
  mockRhel =
    tag:
    pkgs.runCommand "mock-rhel-${tag}" { nativeBuildInputs = [ pkgs.xorriso ]; } ''
      mkdir -p $out rhel-root/images/pxeboot
      echo "Red Hat GPG Key" > rhel-root/RPM-GPG-KEY-redhat-release
      echo "Mock RHEL kernel" > rhel-root/images/pxeboot/vmlinuz
      echo "Mock RHEL initrd" > rhel-root/images/pxeboot/initrd.img
      { echo "stage2-${tag}"; head -c 4194304 /dev/zero; } > rhel-root/images/install.img
      xorriso -as mkisofs -o $out/${tag}.iso -V "RHEL-${tag}" -r -J rhel-root/
    '';

  isoOf = tag: "${mockRhel tag}/${tag}.iso";

  reader = pkgs.writeScript "nfs-refresh-reader" (
    "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ./nfs-refresh-reader.py
  );
in
{
  vm = pkgs.testers.nixosTest {
    name = "router-pxe-boot-nfs-refresh";
    skipLint = false;

    nodes.router =
      { ... }:
      {
        imports = [ nixosModule.nixosModules.default ];

        virtualisation.vlans = [ 1 ];
        networking.useDHCP = false;

        systemd.tmpfiles.rules = [ "d ${isoFolder} 0755 root root - -" ];

        my.router = {
          enable = true;

          pxe-boot = {
            enable = true;
            isoFolderPath = isoFolder;
            nfs.enable = true;
          };

          configInterface.eth1 = {
            mac = null;
            dhcp.server = {
              id = 400;
              address = "${routerIp}/24";
              firstIP = 10;
              pxe-boot.enable = true;
            };
            forwarding = true;
          };
        };
      };

    testScript = ''
      menu_path = "/srv/pxeboot/400/grub/grub.cfg"
      nfs_repo = lambda iso: f"inst.repo=nfs:${routerIp}:${mountRoot}/{iso}/"


      def nfs_mount(iso, target):
          router.succeed(
              f"mkdir -p {target} && mount -t nfs -o vers=3,nolock,ro "
              f"${routerIp}:${mountRoot}/{iso}/ {target}"
          )


      def content_of(iso, tag_dir):
          nfs_mount(iso, tag_dir)
          try:
              return router.succeed(f"head -n 1 {tag_dir}/images/install.img").strip()
          finally:
              router.succeed(f"umount {tag_dir}")


      def prepare_invocation():
          return router.succeed("systemctl show -p InvocationID --value pxe-boot-prepare.service").strip()


      def mount_id(iso):
          return router.succeed(
              f"awk '$5==\"${mountRoot}/{iso}\"{{print $1}}' /proc/self/mountinfo"
          ).strip()


      def refresh_log():
          return router.succeed("journalctl -u pxe-boot-prepare-refresh.service -o cat --no-pager")


      def reader_is_clean():
          errors = router.succeed("cat /tmp/reader.log 2>/dev/null || true")
          assert errors == "", f"the NFS client saw errors:\n{errors}"


      def reader_rounds():
          return int(router.succeed("cat /tmp/reader.count"))


      router.start()
      router.wait_for_unit("multi-user.target")
      router.wait_for_unit("pxe-boot-prepare.service")
      router.wait_for_unit("nfs-server.service")
      router.wait_for_unit("pxe-boot-nfs-exports.service")

      with subtest("An ISO copied into the folder is mounted, exported and listed"):
          router.succeed("cp ${isoOf "keep"} ${isoFolder}/${keepIso}")
          router.wait_until_succeeds("exportfs -v | grep -q ${keepIso}", timeout=120)
          router.wait_until_succeeds(f"grep -q '${keepIso}' {menu_path}", timeout=60)
          assert content_of("${keepIso}", "/mnt/probe") == "stage2-keep", "wrong ISO content"

      with subtest("A client starts reading the first ISO over NFS"):
          nfs_mount("${keepIso}", "/mnt/keep")
          router.succeed(
              "systemd-run --unit=nfs-reader ${reader} "
              "/mnt/keep/images/install.img stage2-keep /tmp/reader.log /tmp/reader.count"
          )
          router.wait_until_succeeds("test -s /tmp/reader.count")

      keep_mount_id = mount_id("${keepIso}")
      keep_fsid = router.succeed(
          "grep -F '${mountRoot}/${keepIso}' /etc/exports.d/pxe-boot.exports | grep -o -m1 'fsid=[0-9]*'"
      ).strip()
      prepare_before = prepare_invocation()

      with subtest("Adding a second ISO leaves the first one alone"):
          router.succeed("cp ${isoOf "new"} ${isoFolder}/${newIso}")
          router.wait_until_succeeds("exportfs -v | grep -q ${newIso}", timeout=120)
          router.wait_until_succeeds(f"grep -q '${newIso}' {menu_path}", timeout=60)

          # What the installer would notice: its ISO kept answering.
          rounds = reader_rounds()
          router.wait_until_succeeds(f"test $(cat /tmp/reader.count) -gt {rounds}")
          reader_is_clean()

          menu = router.succeed(f"cat {menu_path}")
          assert nfs_repo("${newIso}") in menu, menu
          assert nfs_repo("${keepIso}") in menu, menu
          assert content_of("${newIso}", "/mnt/probe") == "stage2-new", "wrong ISO content"

          # Not restarted, not remounted, not re-exported differently.
          assert prepare_invocation() == prepare_before, "pxe-boot-prepare was restarted"
          assert mount_id("${keepIso}") == keep_mount_id, "the first ISO was remounted"
          exports_file = router.succeed("cat /etc/exports.d/pxe-boot.exports")
          assert keep_fsid in exports_file, exports_file

      with subtest("An ISO replaced in place under the same name is remounted"):
          router.succeed("cp ${isoOf "other"} ${isoFolder}/${newIso}")
          # Mount IDs get reused, so the refresh's own log is the proof.
          router.wait_until_succeeds(
              "journalctl -u pxe-boot-prepare-refresh.service -o cat --no-pager "
              "| grep -q 'Unexporting and unmounting: ${newIso}'",
              timeout=180,
          )
          router.wait_until_succeeds(
              "mkdir -p /mnt/probe2 && mount -t nfs -o vers=3,nolock,ro "
              "${routerIp}:${mountRoot}/${newIso}/ /mnt/probe2 && "
              "(head -n 1 /mnt/probe2/images/install.img | grep -q stage2-other; r=$?; umount /mnt/probe2; exit $r)",
              timeout=180,
          )
          reader_is_clean()
          assert mount_id("${keepIso}") == keep_mount_id, "the first ISO was remounted"
          assert prepare_invocation() == prepare_before, "pxe-boot-prepare was restarted"

      with subtest("Removing an ISO unexports and unmounts it, and only it"):
          router.succeed("rm ${isoFolder}/${newIso}")
          router.wait_until_succeeds("! exportfs -v | grep -q ${newIso}", timeout=120)
          router.wait_until_succeeds(f"! grep -q '${newIso}' {menu_path}", timeout=60)
          # nfsd holds an exported ISO busy for a while after the last read.
          router.wait_until_succeeds("! mountpoint -q ${mountRoot}/${newIso}", timeout=180)

          assert mount_id("${keepIso}") == keep_mount_id, "the first ISO was remounted"
          assert prepare_invocation() == prepare_before, "pxe-boot-prepare was restarted"
          router.succeed("exportfs -v | grep -q ${keepIso}")
          reader_is_clean()

          # After the refresh that first mounted it, no refresh unmounted or
          # mounted the first ISO again.
          log = refresh_log()
          after_first_mount = log.split("Mounted ISO: ${keepIso}", 1)[1]
          touched = [
              line
              for line in after_first_mount.splitlines()
              if ("unmounting:" in line or "Mounted ISO:" in line) and "${keepIso}" in line
          ]
          assert touched == [], touched

      with subtest("The first ISO is still readable at the end"):
          router.succeed("systemctl stop nfs-reader.service")
          assert router.succeed("head -n 1 /mnt/keep/images/install.img").strip() == "stage2-keep"
    '';
  };
}
