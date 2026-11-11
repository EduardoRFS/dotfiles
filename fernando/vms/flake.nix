{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixvirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixvirt, ... }:
  let
    inherit (nixpkgs) lib;
    # Host SMT sibling pairs.
    cpus = [ 8 24 9 25 10 26 11 27 12 28 13 29 14 30 15 31 ];
    vcpus = builtins.length cpus;

    domain = nixvirt.lib.domain.writeXML {
      type = "kvm";
      name = "robert";
      uuid = "188bd2bc-fc02-4ab7-9c96-09fc741ec36f";
      memory = { count = 24; unit = "GiB"; };
      memoryBacking = {
        nosharepages = {};
        locked = {};
        allocation.mode = "immediate";
      };
      vcpu.count = vcpus;
      cputune = {
        vcpupin = lib.imap0 (vcpu: cpu: { inherit vcpu; cpuset = toString cpu; }) cpus;
        emulatorpin.cpuset = "0-7,16-23";
        vcpusched = { vcpus = "0-${toString (vcpus - 1)}"; scheduler = "fifo"; priority = 1; };
      };
      os = {
        type = "hvm";
        arch = "x86_64";
        machine = "q35";
        firmware = "efi";
        # Avoid firmware requiring SMM; let libvirt choose the file.
        loader = { secure = false; path = ""; };
      };
      features.acpi = {};
      cpu = {
        mode = "host-passthrough";
        migratable = false;
        topology = { sockets = 1; cores = builtins.div vcpus 2; threads = 2; };
      };
      devices = {
        serial.type = "pty";
        memballoon.model = "none";
        disk = {
          type = "block";
          driver = { name = "qemu"; type = "raw"; cache = "none"; io = "native"; };
          source.dev = "/dev/disk/by-id/nvme-eui.002538b421400b86";
          target = { dev = "vda"; bus = "virtio"; };
        };
        interface = {
          type = "bridge";
          source.bridge = "br0";
          mac.address = "52:54:00:72:6f:62";
          model.type = "virtio";
        };
        channel = { type = "unix"; target = { type = "virtio"; name = "org.qemu.guest_agent.0"; }; };
      };
    };
  in
  {
    nixosConfigurations.robert = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./robert.nix ];
    };

    nixosModules.default = { pkgs, ... }: {
      imports = [ nixvirt.nixosModules.default ];
      virtualisation.libvirt = {
        enable = true;
        package = pkgs.libvirt;
        connections."qemu:///system".domains = [{
          definition = domain;
          restart = false;
        }];
      };
      systemd.services.nixvirt.postStart = ''
        ${pkgs.libvirt}/bin/virsh -c qemu:///system autostart --disable robert
      '';
      virtualisation.libvirtd = {
        qemu.runAsRoot = false;
        onBoot = "ignore";
        onShutdown = "shutdown";
      };
      programs.virt-manager.enable = true;
      users.users.eduardo.extraGroups = [ "libvirtd" ];
    };
  };
}
