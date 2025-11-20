{ pkgs ? import <nixpkgs> {}
, nixosModule ? ../.
}:

let
  inherit (pkgs) lib;

  # Create a dummy ISO directory with test ISO file
  dummyIsoDir = pkgs.runCommand "iso-directory" {} ''
    mkdir -p $out
    # Create a minimal ISO file (just for testing structure)
    echo "Test ISO content" > $out/test.iso
    echo "Another test ISO" > $out/rhel-9.6-x86_64-dvd.iso
  '';

  # Create a test autoinstall script
  testAutoinstallScript = pkgs.writeText "test.ks" ''
    # Test kickstart script
    lang en_US.UTF-8
    keyboard us
    # This is a minimal test script
  '';
in

pkgs.nixosTest {
  name = "router-pxe-boot";

  nodes = {
    router = { config, pkgs, ... }: {
      imports = [ nixosModule.nixosModules.default ];

      virtualisation.vlans = [ 1 ];

      networking.useDHCP = false;

      my.router = {
        enable = true;

        pxe-boot = {
          enable = true;
          isoFolderPath = dummyIsoDir;
          autoinstall = {
            "test.iso" = [
              {
                scriptName = "minimal.ks";
                script = testAutoinstallScript;
              }
              {
                scriptName = "advanced.ks";
                script = "# Advanced config\nnetwork --bootproto=dhcp";
              }
            ];
            "rhel-9.6-x86_64-dvd.iso" = [
              {
                scriptName = "server.ks";
                script = testAutoinstallScript;
              }
            ];
          };
        };

        configInterface = [
          {
            name = "eth1";
            mac = null;
            dhcp = {
              server = {
                id = 200;
                gateway = "192.168.75.1/24";
                firstIP = 10;
                pxe-boot = {
                  enable = true;
                  defaultIso = "test.iso";
                  defaultScriptName = "minimal.ks";
                };
              };
            };
            forwarding = true;
          }
        ];
      };
    };

    # Client that will request PXE boot info
    client = { ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = false;
      networking.firewall.enable = false;

      # Install TFTP client and jq for testing
      environment.systemPackages = with pkgs; [ tftp-hpa jq ];
    };
  };

  testScript = ''
    import json

    start_all()

    # Wait for router to be ready
    router.wait_for_unit("multi-user.target")
    router.wait_for_unit("systemd-networkd.service")
    router.wait_for_unit("kea-dhcp4-server.service")

    # Wait for PXE boot services
    router.wait_for_unit("pxe-boot-prepare.service")
    router.wait_for_unit("pxe-boot-main-script.service")

    with subtest("TFTP service is running"):
        router.succeed("systemctl is-active atftpd.service")

    with subtest("Router interface is configured correctly"):
        addr_info = json.loads(router.succeed("ip --json addr show eth1"))
        ipv4_addrs = [
            addr for addr in addr_info[0]["addr_info"]
            if addr.get("local") == "192.168.75.1" and addr.get("prefixlen") == 24
        ]
        assert len(ipv4_addrs) == 1, "eth1 should have 192.168.75.1/24"

    with subtest("Boot files are present and valid"):
        # Verify GRUB bootloaders exist by checking file size
        # If files don't exist, stat will fail
        grubx64_size = int(router.succeed("stat -c %s /srv/tftp/grubx64.efi").strip())
        grub_pxe_size = int(router.succeed("stat -c %s /srv/tftp/grub.pxe").strip())
        grubaa64_size = int(router.succeed("stat -c %s /srv/tftp/grubaa64.efi").strip())

        assert grubx64_size > 0, "grubx64.efi should not be empty"
        assert grub_pxe_size > 0, "grub.pxe should not be empty"
        assert grubaa64_size > 0, "grubaa64.efi should not be empty"

    with subtest("GRUB config includes all ISOs and scripts"):
        # Read GRUB config once and validate everything
        grub_cfg = router.succeed("cat /srv/tftp/grub/grub.cfg")
        assert len(grub_cfg) > 0, "GRUB config should not be empty"

        # Check that both ISOs are in the config
        assert "test.iso" in grub_cfg, "GRUB config should include test.iso"
        assert "rhel-9.6-x86_64-dvd.iso" in grub_cfg, "GRUB config should include rhel ISO"

        # Check that autoinstall scripts are mentioned
        assert "minimal.ks" in grub_cfg, "GRUB config should include minimal.ks script"
        assert "advanced.ks" in grub_cfg, "GRUB config should include advanced.ks script"
        assert "server.ks" in grub_cfg, "GRUB config should include server.ks script"

    with subtest("Kea DHCP config has PXE client classes"):
        # Check the actual Kea configuration file for PXE client classes
        kea_config = router.succeed("cat /etc/kea/kea-dhcp4.conf")
        kea_json = json.loads(kea_config)

        # Verify client-classes exist in config
        assert "Dhcp4" in kea_json, "Kea config should have Dhcp4 section"
        assert "client-classes" in kea_json["Dhcp4"], "Kea config should have client-classes"

        client_classes = kea_json["Dhcp4"]["client-classes"]
        class_names = [c["name"] for c in client_classes]

        # Check for architecture-specific classes
        assert any("iPXE" in name for name in class_names), "Should have iPXE client class"
        assert any("UEFI" in name and "x86_64" in name for name in class_names), "Should have UEFI x86_64 class"
        assert any("BIOS" in name for name in class_names), "Should have BIOS Legacy class"
        assert any("aarch64" in name for name in class_names), "Should have aarch64 class"

    with subtest("Autoinstall scripts are created correctly"):
        # Read and verify script content (reading will fail if files don't exist)
        minimal_script = router.succeed("cat /srv/pxeboot/scripts/test.iso/minimal.ks")
        assert "lang en_US.UTF-8" in minimal_script, "Script should contain expected content"
        assert "keyboard us" in minimal_script, "Script should contain keyboard setting"

        advanced_script = router.succeed("cat /srv/pxeboot/scripts/test.iso/advanced.ks")
        assert "network --bootproto=dhcp" in advanced_script, "Advanced script should have network config"

    with subtest("Boot environments JSON is valid"):
        # Read and parse JSON (will fail if file doesn't exist or isn't valid JSON)
        boot_env = json.loads(router.succeed("cat /srv/pxeboot/boot-environments.json"))

        # Check structure
        assert "test.iso" in boot_env, "Boot environments should include test.iso"
        assert "rhel-9.6-x86_64-dvd.iso" in boot_env, "Boot environments should include rhel ISO"

        # Check test.iso has both scripts
        test_iso_scripts = boot_env["test.iso"]
        assert len(test_iso_scripts) == 2, "test.iso should have 2 autoinstall scripts"

        script_names = [s["scriptName"] for s in test_iso_scripts]
        assert "minimal.ks" in script_names, "Should have minimal.ks in boot env"
        assert "advanced.ks" in script_names, "Should have advanced.ks in boot env"

    with subtest("TFTP server is accessible and serves files"):
        client.wait_for_unit("multi-user.target")

        # Configure client with static IP for testing
        client.succeed("ip addr add 192.168.75.50/24 dev eth1")
        client.succeed("ip link set eth1 up")

        # Wait for network to be ready
        client.sleep(2)

        # Test network connectivity
        client.succeed("ping -c 3 192.168.75.1")

        # Fetch GRUB bootloader via TFTP (will fail if TFTP doesn't work)
        client.succeed("tftp 192.168.75.1 -c get grubx64.efi /tmp/grubx64.efi")

        # Verify downloaded file is not empty
        size = int(client.succeed("stat -c %s /tmp/grubx64.efi").strip())
        assert size > 0, f"Downloaded grubx64.efi should not be empty, got size: {size}"

        # Fetch and verify GRUB config
        client.succeed("tftp 192.168.75.1 -c get grub/grub.cfg /tmp/grub.cfg")
        grub_content = client.succeed("cat /tmp/grub.cfg")
        assert "test.iso" in grub_content, "Fetched GRUB config should contain test.iso"

    with subtest("ISO files are linked/available"):
        # Check that ISOs are available (test -e works for both files and symlinks)
        router.succeed("test -e /srv/pxeboot/test.iso")
        router.succeed("test -e /srv/pxeboot/rhel-9.6-x86_64-dvd.iso")
  '';
}
