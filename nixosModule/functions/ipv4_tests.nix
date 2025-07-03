{ pkgs ? import <nixpkgs> {} }:
let
  inherit (pkgs) lib;
  ipv4_fn = import ./ipv4.nix {inherit lib pkgs;};
in
  lib.runTests {
    test_fromCidrString_010 = {
      expr = ipv4_fn.fromCidrString "192.168.1.8/25";

      expected = {
        address = "192.168.1.8";
        addresses = "126";
        addrSpace = "Private Use";
        broadcast = "192.168.1.127";
        maxAddr = "192.168.1.126";
        minAddr = "192.168.1.1";
        netmask = "255.255.255.128";
        network = "192.168.1.0";
        prefix = "25";
      };
    };

    test_fromCidrString_020 = {
      expr = ipv4_fn.fromCidrString "192.168.1.2/24";

      expected = {
        address = "192.168.1.2";
        addresses = "254";
        addrSpace = "Private Use";
        broadcast = "192.168.1.255";
        maxAddr = "192.168.1.254";
        minAddr = "192.168.1.1";
        netmask = "255.255.255.0";
        network = "192.168.1.0";
        prefix = "24";
      };
    };

    test_increase_010_no_subnet_verify = {
      expr = ipv4_fn.increase {ip = "192.168.1.0"; by = 24;};
      expected = "192.168.1.24";
    };

    test_increase_011_no_subnet_verify = {
      expr = ipv4_fn.increase {ip = "192.168.1.0"; by = 424;};
      expected = "192.168.2.168";
    };

    test_increase_020_subnet_verify = {
      expr = ipv4_fn.increase {ip = "192.168.1.0"; by = 24;
                               subnet = "192.168.1.0/24";};
      expected = "192.168.1.24";
    };

    test_increase_021_subnet_verify = {
      expr = ipv4_fn.increase {ip = "192.168.0.0"; by = 424;
                               subnet = "192.168.0.0/23";};
      expected = "192.168.1.168";
    };

    test_increase_030_subnet_verify_failed = {
      expr = (builtins.tryEval (ipv4_fn.increase {
        ip = "192.168.1.255"; by = 1;
        subnet = "192.168.1.0/24";
      })).success;

      expected = false;
    };

    test_increase_031_subnet_verify_failed = {
      expr = (builtins.tryEval(ipv4_fn.increase {
        ip = "192.168.1.0"; by = -1;
        subnet = "192.168.1.0/24";
      })).success;

      expected = false;
    };


    test_increase_010 = {
      expr = ipv4_fn.cidrValid "192.168.1.2/24" ;
      expected = true;
    };

    test_increase_011 = {
      expr = ipv4_fn.cidrValid "3.168.1.2/1" ;
      expected = true;
    };

    test_increase_012 = {
      expr = ipv4_fn.cidrValid "13.168.1.2/32" ;
      expected = true;
    };

    test_increase_013 = {
      expr = ipv4_fn.cidrValid "255.168.1.2/9" ;
      expected = true;
    };

    test_increase_014 = {
      expr = ipv4_fn.cidrValid "245.168.1.2/10" ;
      expected = true;
    };

    test_increase_020 = {
      expr = ipv4_fn.cidrValid "245.168.1.2/0" ;
      expected = false;
    };

    test_increase_021 = {
      expr = ipv4_fn.cidrValid "245.168.1.2/33" ;
      expected = false;
    };

    test_increase_022 = {
      expr = ipv4_fn.cidrValid "100.256.1.2/24" ;
      expected = false;
    };
  }
