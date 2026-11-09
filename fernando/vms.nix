{ pkgs, fernandoKernels, ... }:

let
  # Evaluate the toy independently; it is not part of the host boot closure.
  toyGuest = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      ({ lib, pkgs, modulesPath, ... }:

      {
        imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
        nixpkgs.hostPlatform = "x86_64-linux";
        networking.hostName = "fernando-toy";
        networking.useDHCP = true;
        system.stateVersion = "26.05";

        boot.kernelPackages = fernandoKernels.realtime;
        # vCPU 0 handles guest housekeeping; vCPUs 1-3 run the test workload.
        boot.kernelParams = [
          "console=ttyS0,115200"
          "nohz_full=1-3"
          "isolcpus=domain,managed_irq,1-3"
          "irqaffinity=0"
        ];
        # Default guest services to vCPU 0; explicit test affinity can select 1-3.
        systemd.settings.Manager.CPUAffinity = "0";
        boot.loader.grub = {
          enable = true;
          device = "/dev/vda";
        };
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };

        services.qemuGuest.enable = true;
        # Disposable local-console toy: no SSH server or password-based remote login.
        services.getty.autologinUser = "root";
        environment.systemPackages = with pkgs; [ rt-tests stress-ng procps ];
      })
    ];
  };

  toyDomain = ''
    <domain type='kvm'>
      <name>fernando-toy</name>
      <description>Manual-start NixOS RT toy. Use the realtime-reserved host profile for isolation.</description>
      <!-- Keep the VM outside the host system.slice/user.slice CPU restrictions. -->
      <resource><partition>/machine</partition></resource>
      <memory unit='MiB'>2048</memory>
      <currentMemory unit='MiB'>2048</currentMemory>
      <!-- Bound locked memory, including QEMU overhead, for this fixed-size toy. -->
      <memtune><hard_limit unit='MiB'>4096</hard_limit></memtune>
      <memoryBacking>
        <nosharepages/>
        <locked/>
        <allocation mode='immediate'/>
      </memoryBacking>
      <vcpu placement='static'>4</vcpu>
      <iothreads>1</iothreads>
      <cputune>
        <!-- One vCPU per physical core; SMT siblings 28-31 are left unused by this VM. -->
        <vcpupin vcpu='0' cpuset='12'/>
        <vcpupin vcpu='1' cpuset='13'/>
        <vcpupin vcpu='2' cpuset='14'/>
        <vcpupin vcpu='3' cpuset='15'/>
        <emulatorpin cpuset='0-11,16-27'/>
        <iothreadpin iothread='1' cpuset='0-11,16-27'/>
        <vcpusched vcpus='1-3' scheduler='fifo' priority='1'/>
      </cputune>
      <os>
        <type arch='x86_64' machine='q35'>hvm</type>
        <boot dev='hd'/>
      </os>
      <features><acpi/><apic/></features>
      <cpu mode='host-passthrough' migratable='off'>
        <topology sockets='1' cores='4' threads='1'/>
      </cpu>
      <clock offset='utc'/>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>
        <disk type='file' device='disk'>
          <driver name='qemu' type='qcow2' cache='none' io='native' iothread='1'/>
          <source file='/var/lib/libvirt/images/fernando-toy.qcow2'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        <interface type='user'><model type='virtio'/></interface>
        <serial type='pty'><target port='0'/></serial>
        <console type='pty'><target type='serial' port='0'/></console>
        <channel type='unix'>
          <target type='virtio' name='org.qemu.guest_agent.0'/>
        </channel>
        <memballoon model='none'/>
      </devices>
    </domain>
  '';

  toyCreate = pkgs.writeShellApplication {
    name = "fernando-toy-create";
    runtimeInputs = [ pkgs.coreutils pkgs.libvirt pkgs.qemu ];
    text = ''
      if [[ $# != 1 || $EUID != 0 ]]; then
        echo "Usage: sudo fernando-toy-create /path/to/fernando-toy.qcow2" >&2
        exit 1
      fi

      source_image=$(realpath -- "$1")
      disk=/var/lib/libvirt/images/fernando-toy.qcow2
      uri=qemu:///system
      if [[ ! -f "$source_image" ]]; then
        echo "Image does not exist: $source_image" >&2
        exit 1
      fi
      # Verify the daemon is reachable before treating dominfo failure as absence.
      virsh --connect "$uri" list --all >/dev/null
      if virsh --connect "$uri" dominfo fernando-toy >/dev/null 2>&1 || [[ -e "$disk" ]]; then
        echo "fernando-toy or its disk already exists; refusing to overwrite it." >&2
        exit 1
      fi

      qemu-img check -f qcow2 "$source_image"
      install -d -m 0755 /var/lib/libvirt/images
      # noclobber also prevents replacing a disk created concurrently.
      (set -o noclobber; umask 077; : > "$disk")
      cp --reflink=auto --sparse=always -- "$source_image" "$disk"
      chown qemu-libvirtd:qemu-libvirtd "$disk"
      chmod 0600 "$disk"
      virsh --connect "$uri" define --validate /etc/libvirt/fernando-toy.xml
      virsh --connect "$uri" autostart --disable fernando-toy
      echo "Created fernando-toy (stopped, autostart disabled)."
      echo "Start: virsh --connect qemu:///system start fernando-toy --console"
    '';
  };
in
{
  virtualisation.libvirtd = {
    enable = true;
    qemu.runAsRoot = false;
    # Do not restore guests that were running when the host shut down.
    onBoot = "ignore";
    onShutdown = "shutdown";
  };
  programs.virt-manager.enable = true;
  users.users.eduardo.extraGroups = [ "libvirtd" ];

  environment.systemPackages = [ pkgs.rt-tests toyCreate ];
  # A template only: fernando-toy-create defines the VM without starting it.
  environment.etc."libvirt/fernando-toy.xml".text = toyDomain;

  # Build manually from the repository root:
  # nix-build '<nixpkgs/nixos>' -I nixos-config=./fernando/configuration.nix \
  #   -A config.system.build.toyImage -o result-toy
  # sudo fernando-toy-create result-toy/fernando-toy.qcow2
  # virsh -c qemu:///system start fernando-toy --console
  # Ctrl+] detaches. The guest console logs in as root.
  # Guest test: cyclictest -a 1-3 -t3 -p80 -m -D 60s -q
  # Stop: virsh -c qemu:///system shutdown fernando-toy --mode agent
  # Boot realtime-reserved for host CPU isolation.
  system.build.toyImage = import (pkgs.path + "/nixos/lib/make-disk-image.nix") {
    inherit (toyGuest) pkgs config;
    lib = toyGuest.pkgs.lib;
    name = "fernando-toy-image";
    baseName = "fernando-toy";
    format = "qcow2";
    partitionTableType = "legacy";
    diskSize = "auto";
    additionalSpace = "2G";
    memSize = 2048;
  };
}
