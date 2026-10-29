# AGENTS.md

spudbox is a NixOS module for a self-hosted media server. `README.md` is the
user guide.

- **Installing a server for someone:** read and follow
  [`.claude/skills/install-spudbox/SKILL.md`](.claude/skills/install-spudbox/SKILL.md).
  It's written for any agent that can run shell commands, not only Claude
  Code. Its safety rules (typed confirmation before erasing a disk, secrets
  typed by the person and never through the chat, the instance repository
  kept private) apply whichever agent you are.
- **Changing spudbox itself:** read [`CLAUDE.md`](CLAUDE.md) and
  [`docs/CODE-MAP.md`](docs/CODE-MAP.md) for the layout, conventions and how
  to test a change.
