_:

# Claude Code Remote Control server, reachable from the Claude mobile app and
# claude.ai/code. The binary is the native install at ~/.local/bin/claude
# (self-updating; runs via nix-ld) rather than pkgs.claude-code, which lags.
# One-time setup is in README.md ("Claude Code").
let
  user = "luds";
  home = "/home/${user}";
  workDir = "${home}/workspace";
in
{
  environment.localBinInPath = true;

  systemd.tmpfiles.rules = [ "d ${workDir} 0755 ${user} users -" ];

  systemd.services.claude-remote-control = {
    description = "Claude Code Remote Control server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    # Tools available to Claude's sessions.
    path = [
      "/run/wrappers"
      "/run/current-system/sw"
    ];
    environment.HOME = home;
    # Skip until `claude auth login` has been done interactively.
    unitConfig.ConditionPathExists = "${home}/.claude/.credentials.json";
    serviceConfig = {
      User = user;
      WorkingDirectory = workDir;
      ExecStart = "${home}/.local/bin/claude remote-control --name spudbox";
      Restart = "always";
      RestartSec = 30;
    };
  };
}
