---
name: pr-ready
description: >
  Prepare a pull request: generate a PR description using the repo's template,
  update the Unreleased section of CHANGELOG.md with user-facing changes, run
  quality checks, and write the PR title and description to a local .pr-ready/ file for the pr-submit script to open the PR. Invoke when the
  user asks to "generate a PR description", "describe this PR", "write PR notes",
  "prepare a PR", "pr ready", or "prep this PR".
metadata:
  version: "1.0.0"
---

# PR Ready — Description + Changelog

Prepare a branch for pull request: generate a PR description from the diff AND
update the changelog, then write the PR title and description to a local
`.pr-ready/` file that the `pr-submit` script can use to open the PR.

## Steps

### Phase 1: Gather context

1. **Detect the base branch**
   Run `git remote show origin` or check for `main` / `master` to determine the
   default branch.

2. **Identify the current branch**
   Run `git branch --show-current` to get the feature branch name.

3. **Gather the diff context**
   - Run `git log <base>..<current> --oneline` to get the commit list.
   - Run `git diff <base>..<current> --stat` to get the file change summary.
   - For each changed source file, read the diff to understand what changed.
     Focus on source directories for code changes.
   - Skip binary files, lock files, and generated files.

4. **Read the PR template**
   - Look for `.github/pull_request_template.md` in the repository.
   - If it exists, use its exact structure (sections, checkboxes) as the PR
     description format.
   - If it doesn't exist, use a sensible default format with Description,
     Type of Change, and Checklist sections.

5. **Read the current changelog**
   - Read `CHANGELOG.md` and note the existing `## [Unreleased]` section
     contents.
   - Understand the Keep a Changelog format used (Added, Changed, Deprecated,
     Removed, Fixed, Security).
   - If no `CHANGELOG.md` exists, skip changelog updates entirely.

### Phase 2: Run quality checks

6. **Detect the project type and run appropriate checks** (for the PR checklist)

   Detect the project type by checking for marker files in the repo root:

   | Marker file      | Project type | Commands to run                                                      |
   | ---------------- | ------------ | -------------------------------------------------------------------- |
   | `Cargo.toml`     | Rust         | `cargo fmt -- --check`, `cargo clippy -- -D warnings`, `cargo test`  |
   | `package.json`   | Node.js      | `npm run lint` (if script exists), `npm test` (if script exists)     |
   | `go.mod`         | Go           | `gofmt -l .`, `go vet ./...`, `go test ./...`                       |
   | `pyproject.toml` | Python       | `ruff check .` (if available), `pytest` (if available)               |
   | `Makefile`       | Make-based   | `make lint` (if target exists), `make test` (if target exists)       |
   | `pom.xml`        | Java/Maven   | `mvn verify`                                                         |
   | `build.gradle`   | Java/Gradle  | `./gradlew check`                                                    |
   | `.sln` / `.csproj` | .NET       | `dotnet format --verify-no-changes`, `dotnet test`                   |

   If multiple marker files exist, run checks for **all** detected project
   types (e.g., a repo with both `Cargo.toml` and `package.json`).

   Note which checks pass/fail to fill in the checklist accurately.

   **Important**: If a command doesn't exist or isn't applicable (e.g., the
   npm `lint` script is not defined), skip it gracefully — don't fail the
   entire phase.

### Phase 3: Generate the PR description

7. **Write the PR description** using the PR template structure:
   - **Description section**: Write a clear summary of what the PR does.
     Include:
     - A one-line summary of the purpose
     - A "What's included" subsection listing key changes with brief
       explanations
     - Reference specific files/modules only when it adds clarity
   - **Related Issues**: Check commit messages for issue references (#123).
     If none, leave placeholder.
   - **Type of Change**: Check the appropriate box(es) based on diff content:
     - New files in source directories → New feature
     - Modified existing logic fixing bugs → Bug fix
     - Changes only in docs/ or *.md → Documentation update
     - Changes in `.github/` or CI configs → CI / infrastructure
     - Restructuring without behavior change → Refactoring
   - **Checklist**: Mark items based on the results from step 6.

8. **Quality guidelines for the PR description**
   - Do NOT reference internal planning documents (PLAN.md stages, etc.) —
     describe actual features
   - Write from the user/contributor perspective
   - Be specific about what was added/changed
   - Keep the description concise but complete — aim for 15-30 lines

### Phase 4: Update the changelog

9. **Identify user-facing changes** from the diff. A change is user-facing
   if it:
   - Adds a feature the user can see or interact with
   - Fixes a bug the user could encounter
   - Changes behavior the user would notice (keybindings, UI, output format)
   - Adds or changes configuration options
   - **Is NOT user-facing**: refactoring, CI changes, test additions, internal
     restructuring, dependency updates, code style fixes

10. **Categorize each change** using Keep a Changelog categories:
    - **Added** — new features or capabilities
    - **Changed** — changes to existing functionality
    - **Deprecated** — features that will be removed
    - **Removed** — features that were removed
    - **Fixed** — bug fixes
    - **Security** — vulnerability fixes

11. **Update the `## [Unreleased]` section** of `CHANGELOG.md`:
    - **Append** new entries to the existing Unreleased section — do NOT delete
      what's already there
    - If a category header (e.g., `### Added`) already exists with entries,
      add new entries below the existing ones
    - If a category header doesn't exist yet, add it
    - Write entries as concise, user-facing descriptions — no implementation
      details
    - Each entry starts with `- ` (markdown list item)
    - Do NOT include entries for: CI changes, refactoring, dependency bumps,
      test-only changes, documentation-only changes

12. **Changelog entry style guide**
    - ✅ Good: `- Help overlay showing keybindings and shortcuts (press ?)`
    - ✅ Good: `- Fixed CPU percentage exceeding 100% on systems with frequency scaling`
    - ❌ Bad: `- Refactored ring buffer module` (not user-facing)
    - ❌ Bad: `- Added unit tests for network collector` (not user-facing)
    - ❌ Bad: `- Implements Stage 5 from PLAN.md` (references internals)

### Phase 5: Output

13. **Write the PR title and description to a `.pr-ready/` file**

    Instead of copying to the clipboard, persist the proposed PR so it can be
    reviewed and opened later by the `pr-submit` script.

    a. **Ensure the output directory exists and stays untracked**
       - Create a `.pr-ready/` directory at the repository root.
       - Keep it out of git *without* touching the tracked `.gitignore` by
         adding it to the repo-local exclude file:
         ```sh
         mkdir -p .pr-ready
         grep -qxF '.pr-ready/' .git/info/exclude 2>/dev/null || echo '.pr-ready/' >> .git/info/exclude
         ```

    b. **Write the PR draft as a JSON file**
       - File path: `.pr-ready/<timestamp>__<branch>.json`, where `<timestamp>`
         is `YYYYMMDD-HHMMSS` and `<branch>` is the current branch with every
         `/` replaced by `-` (so the name is filesystem-safe).
       - **Use the file-writing tool to create this file — do NOT `echo` or
         heredoc the JSON through the shell.** The title and body routinely
         contain backticks, quotes, `$`, and newlines; writing the file
         directly avoids all shell-escaping and command-substitution hazards.
       - Use exactly this schema (the `pr-submit` script parses it with `jq`):
         ```json
         {
           "title": "<conventional-commit-style PR title>",
           "body": "<the full PR description, exactly as it should appear>",
           "base": "<base branch, e.g. main>",
           "branch": "<current branch>",
           "created_at": "<ISO 8601 timestamp>"
         }
         ```
       - `body` is the complete PR description from Phase 3, preserving all
         markdown — headings, checkboxes, and fenced code blocks included.

14. **Suggest a PR title**
    - Based on the changes, suggest a conventional-commit-style PR title
      (this is the value stored in `title` above).
    - Format: `feat: add process table with tree view` or
      `fix: correct CPU calculation`

15. **Show a summary** to the user:
    - The suggested PR title
    - The path to the `.pr-ready/` JSON file that was written
    - A reminder that they can run `pr-submit` from the repo to pick this
      draft, review it, and open the PR (auto-merge, squash)
    - A summary of what was added to CHANGELOG.md (list the new entries)
    - Note any changelog entries that were already present and preserved
