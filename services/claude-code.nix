{ config, lib, ... }:

# Claude Code Remote Control server, reachable from the Claude mobile app and
# claude.ai/code (spudbox.claudeCode). The binary is the native install at
# ~/.local/bin/claude (self-updating; runs via nix-ld) rather than
# pkgs.claude-code, which lags. One-time setup is in the README ("Claude Code").
#
# Runs as spudbox.claudeCode.user. If that user is a superuser (passwordless
# sudo), Claude sessions have root on the server: anyone controlling the
# claude.ai account, or a prompt injection reaching a session, does too.
let
  cfg = config.spudbox.claudeCode;
  inherit (cfg) user;
  home = config.users.users.${user}.home;
  workDir = "${home}/workspace";
in
lib.mkIf cfg.enable {
  assertions = [
    {
      assertion = lib.any (u: u.username == user) config.spudbox.users;
      message = "spudbox.claudeCode.user (${user}) must be one of spudbox.users.";
    }
  ];

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
    # Never restart it on a switch: Claude's own sessions run in this unit,
    # so a deploy started from one would kill itself (and the switch) midway.
    # Changes here apply on the next boot or a manual restart over SSH.
    restartIfChanged = false;
    # Skip until `claude auth login` has been done interactively.
    unitConfig.ConditionPathExists = "${home}/.claude/.credentials.json";
    serviceConfig = {
      User = user;
      WorkingDirectory = workDir;
      ExecStart = "${home}/.local/bin/claude remote-control --name ${cfg.name}";
      Restart = "always";
      RestartSec = 30;
      # It redraws its status screen (QR hint, connection, capacity) about
      # once a second: ~400k journal lines a day. Drop just those lines;
      # anything else it prints, errors included, still reaches the journal.
      # (Regexes; "." stands in for spaces, which can't appear here.)
      LogFilterPatterns = [
        "~QR.code"
        "~ask.Claude.to.work.in.this.folder"
        "~claude.ai/code"
        "~·.Connected.·"
        "~Capacity:.[0-9]"
      ];
    };
  };
}
