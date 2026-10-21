# Kafkade Agentkit

Reusable [agent skills](https://agentskills.io/specification) shared across all
Kafkade projects. Compatible with **GitHub Copilot CLI**, **Claude Code**, and
any agent supporting the [Agent Skills open standard](https://github.com/agentskills/agentskills).

## Available Skills

| Skill | Description |
|-------|-------------|
| [pr-ready](skills/pr-ready/) | Generate PR descriptions, update changelogs, and run quality checks — auto-detects project type (Rust, Node.js, Go, Python, .NET, Java) |

## Installation

Clone this repo and run the install script. Skills can be installed to any of
these user-level directories:

| Target | Directory | Agent |
|--------|-----------|-------|
| `copilot` | `~/.copilot/skills/` | GitHub Copilot CLI |
| `claude` | `~/.claude/skills/` | Claude Code |
| `agents` | `~/.agents/skills/` | Vendor-neutral (any compatible agent) |

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

The installer walks you through three steps:

1. **Select skills.** A checkbox list shows each skill with its version and
   status. New and outdated skills are preselected.
2. **Select targets.** A checkbox list shows each target directory and what
   would change there, for example `(1 new, 1 update)`. All targets are
   preselected.
3. **Confirm.** A summary shows the selected skills and targets. Press
   `Enter` or `y` to proceed.

In each list, use `↑`/`↓` (or `j`/`k`) to move, `space` to toggle, `a` to
toggle all, `Enter` to confirm, and `q` or `Esc` to cancel.

| Status | Meaning | Preselected |
|--------|---------|-------------|
| `not installed` | Not in any target directory | Yes |
| `up to date` | Identical in all targets | No |
| `update available (a -> b)` | The repo has a higher version | Yes |
| `modified (version not bumped)` | Content differs but versions match. Either the repo changed without a version bump, or an installed copy was edited | Yes |
| `installed is newer (a > b)` | The installed version is higher than the repo's. Run `git pull` first | No (never downgrades) |
| `partially installed (n/3 targets)` | Missing from some targets | Yes |

Skip the menus with these options:

| Action | macOS / Linux | Windows |
|--------|---------------|---------|
| Install or update all skills | `./install.sh --all` | `.\install.ps1 -All` |
| Install or update specific skills | `./install.sh pr-ready staff-explain` | `.\install.ps1 -Skill pr-ready,staff-explain` |
| Limit to specific targets | `./install.sh --all --target copilot,claude` | `.\install.ps1 -All -Target copilot,claude` |
| Show status only | `./install.sh --list` | `.\install.ps1 -List` |

Without a target option, these commands use all targets. When input isn't
interactive (for example, in CI), all skills are installed to all targets.

### Updating

Pull the latest changes and re-run the script. New and outdated skills are
preselected, so you can press `Enter` through each step:

```bash
git pull
./install.sh        # macOS/Linux
.\install.ps1       # Windows
```

### Uninstalling

The uninstall option uses the same steps, listing only installed skills and
preselecting the targets where they're installed. Combine it with
`--all` / `-All`, skill names, or a target option to skip the menus.

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
2. Add a `SKILL.md` with YAML frontmatter (`name`, `description`, and
   `metadata.version`, starting at `"1.0.0"`) and instructions. Bump the
   version with every change: patch for wording, minor for new sections or
   modes, major for changed invocation or output format.
3. Optionally add scripts or supplementary files in `scripts/`, `references/`, or `assets/`
4. Run `./install.sh` to install locally
5. Validate with `gh skill publish --dry-run` (if using gh CLI ≥ 2.90.0)

## License

MIT
