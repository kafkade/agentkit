# Kafkade Agentkit

Reusable [agent skills](https://agentskills.io/specification) shared across all
Kafkade projects. Compatible with **GitHub Copilot CLI**, **Claude Code**, and
any agent supporting the [Agent Skills open standard](https://github.com/agentskills/agentskills).

## Available Skills

| Skill | Description |
|-------|-------------|
| [pr-ready](skills/pr-ready/) | Generate PR descriptions, update changelogs, and run quality checks — auto-detects project type (Rust, Node.js, Go, Python, .NET, Java) |

## Installation

Clone this repo and run the install script. Skills are copied to all three
user-level directories so they work everywhere:

- `~/.copilot/skills/` — GitHub Copilot CLI
- `~/.claude/skills/` — Claude Code
- `~/.agents/skills/` — Vendor-neutral (any compatible agent)

**macOS / Linux:**

```bash
git clone https://github.com/kafkade/agentkit.git
cd agentkit
./install.sh
```

**Windows (PowerShell):**

```powershell
git clone https://github.com/kafkade/agentkit.git
cd agentkit
.\install.ps1
```

### Updating

Pull the latest changes and re-run the script:

```bash
git pull
./install.sh        # macOS/Linux
.\install.ps1       # Windows
```

### Uninstalling

```bash
./install.sh --uninstall        # macOS/Linux
.\install.ps1 -Uninstall        # Windows
```

### Using `gh skill` (gh CLI ≥ 2.90.0)

If you have a recent version of the GitHub CLI, you can also install
individual skills directly:

```bash
gh skill install kafkade/agentkit pr-ready --scope user
gh skill update pr-ready
```

### Custom install location

Set `COPILOT_HOME` or `CLAUDE_HOME` environment variables to override the
default install paths for Copilot or Claude respectively.

## Adding New Skills

1. Create a new directory under `skills/` (lowercase, hyphenated)
2. Add a `SKILL.md` with YAML frontmatter (`name`, `description`) and instructions
3. Optionally add scripts or supplementary files in `scripts/`, `references/`, or `assets/`
4. Run `./install.sh` to install locally
5. Validate with `gh skill publish --dry-run` (if using gh CLI ≥ 2.90.0)

## License

MIT
