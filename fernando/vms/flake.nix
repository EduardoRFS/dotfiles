{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixvirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixvirt, ... }:
  let
    domain = nixvirt.lib.domain.writeXML {
      type = "kvm";
      name = "fernando-toy";
      uuid = "ecb41d83-ddd8-44ae-9b0d-bc08fb304720";
      description = "Manual-start VM; payload unspecified. Use the realtime-reserved host profile for isolation.";
      memory = { count = 2048; unit = "MiB"; };
      # Include QEMU overhead in the locked-memory limit.
      memtune.hard_limit = { count = 4096; unit = "MiB"; };
      memoryBacking = {
        nosharepages = {};
        locked = {};
        allocation.mode = "immediate";
      };
      vcpu = { count = 4; placement = "static"; };
      cputune = {
        # One vCPU per physical core; SMT siblings 28-31 stay unused by this VM.
        vcpupin = builtins.genList (vcpu: { inherit vcpu; cpuset = toString (12 + vcpu); }) 4;
        emulatorpin.cpuset = "0-11,16-27";
        vcpusched = { vcpus = "0-3"; scheduler = "fifo"; priority = 1; };
      };
      os = { type = "hvm"; arch = "x86_64"; machine = "q35"; };
      features = { acpi = {}; apic = {}; };
      cpu = {
        mode = "host-passthrough";
        migratable = false;
        topology = { sockets = 1; cores = 4; threads = 1; };
      };
      clock.offset = "utc";
      on_poweroff = "destroy";
      on_reboot = "restart";
      on_crash = "destroy";
      devices = {
        serial = { type = "pty"; target.port = 0; };
        console = { type = "pty"; target = { type = "serial"; port = 0; }; };
        memballoon.model = "none";
      };
    };
  in
  {
    nixosModules.default = { pkgs, ... }: {
      imports = [ nixvirt.nixosModules.default ];
      virtualisation.libvirt = {
        enable = true;
        package = pkgs.libvirt;
        connections."qemu:///system".domains = [{
          definition = domain;
          active = null;
          restart = false;
        }];
      };
      systemd.services.nixvirt.postStart = ''
        ${pkgs.libvirt}/bin/virsh -c qemu:///system autostart --disable fernando-toy
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
