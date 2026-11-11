{
  imports = [
    (builtins.getFlake "path:${toString ./vms}").nixosModules.default
  ];
}
