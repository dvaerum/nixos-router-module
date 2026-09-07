{
  pkgs ? import <nixpkgs> {},
  netLib,
}: let
  inherit (pkgs) lib;
  ipv4_fn = import ./ipv4.nix {inherit lib netLib;};
in
  lib.runTests {
    test_fromCidrString_010 = {
      expr = ipv4_fn.fromCidrString "192.168.1.8/25";

      expected = {
        address = "192.168.1.8";
        addresses = 126;
        broadcast = "192.168.1.127";
        maxAddr = "192.168.1.126";
        minAddr = "192.168.1.1";
        netmask = "255.255.255.128";
        network = "192.168.1.0";
        prefix = 25;
      };
    };

    test_fromCidrString_020 = {
      expr = ipv4_fn.fromCidrString "192.168.1.2/24";

      expected = {
        address = "192.168.1.2";
        addresses = 254;
        broadcast = "192.168.1.255";
        maxAddr = "192.168.1.254";
        minAddr = "192.168.1.1";
        netmask = "255.255.255.0";
        network = "192.168.1.0";
        prefix = 24;
      };
    };

    # A bare network address must report `address = null` — the `subnet`
    # validator relies on this to reject host CIDRs.
    test_fromCidrString_030_network_addr_is_null = {
      expr = (ipv4_fn.fromCidrString "10.0.0.0/8").address;
      expected = null;
    };

    test_subnetValid_010_network = {
      expr = ipv4_fn.subnetValid "172.20.90.0/24";
      expected = true;
    };

    test_subnetValid_020_host_rejected = {
      expr = ipv4_fn.subnetValid "172.20.90.5/24";
      expected = false;
    };

    test_nthAddress_010 = {
      expr = ipv4_fn.nthAddress "192.168.1.0/24" 5;
      expected = "192.168.1.5";
    };

    test_nthAddress_020_crosses_octet = {
      expr = ipv4_fn.nthAddress "192.168.0.0/23" 424;
      expected = "192.168.1.168";
    };

    # An index beyond the network's size must throw.
    test_nthAddress_030_out_of_range = {
      expr = (builtins.tryEval (ipv4_fn.nthAddress "192.168.1.0/24" 300)).success;
      expected = false;
    };

    test_increase_010 = {
      expr = ipv4_fn.cidrValid "192.168.1.2/24";
      expected = true;
    };

    test_increase_011 = {
      expr = ipv4_fn.cidrValid "3.168.1.2/1";
      expected = true;
    };

    test_increase_012 = {
      expr = ipv4_fn.cidrValid "13.168.1.2/32";
      expected = true;
    };

    test_increase_013 = {
      expr = ipv4_fn.cidrValid "255.168.1.2/9";
      expected = true;
    };

    test_increase_014 = {
      expr = ipv4_fn.cidrValid "245.168.1.2/10";
      expected = true;
    };

    test_increase_020 = {
      expr = ipv4_fn.cidrValid "245.168.1.2/0";
      expected = false;
    };

    test_increase_021 = {
      expr = ipv4_fn.cidrValid "245.168.1.2/33";
      expected = false;
    };

    test_increase_022 = {
      expr = ipv4_fn.cidrValid "100.256.1.2/24";
      expected = false;
    };
  }
