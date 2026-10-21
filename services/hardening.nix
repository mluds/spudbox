# Baseline systemd sandboxing for services whose NixOS modules set none but
# which handle untrusted input (usenet archives, subtitles, media metadata).
# Use as `serviceConfig = import ./hardening.nix // { ... };`.
#
# Deliberately leaves filesystem paths alone: ProtectSystem=full only makes
# /usr, /boot and /etc read-only, so /var/lib and the /mnt media pools stay
# writable. MemoryDenyWriteExecute is left out (breaks Node's JIT).
{
  NoNewPrivileges = true; # no setuid escalation (su/sudo)
  RestrictSUIDSGID = true;
  PrivateTmp = true;
  PrivateDevices = true;
  ProtectSystem = "full";
  ProtectHome = true;
  ProtectProc = "invisible"; # other users' processes (and their argv) hidden
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  ProtectControlGroups = true;
  ProtectClock = true;
  ProtectHostname = true;
  RestrictNamespaces = true;
  RestrictRealtime = true;
  LockPersonality = true;
  SystemCallArchitectures = "native";
  RestrictAddressFamilies = [
    "AF_UNIX"
    "AF_INET"
    "AF_INET6"
    "AF_NETLINK"
  ];
}
