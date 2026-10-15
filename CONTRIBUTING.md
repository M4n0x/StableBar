# Contributing

## Setup

StableBar needs macOS 14 or later and Xcode's Swift 6 toolchain. [Build and run](README.md#build-and-run) covers building the app. For development:

```sh
swift build
swift test
```

Node.js runs only the release tooling and the commit message check. `npm ci` installs them, and `npx commitlint --from origin/main` checks your commits before you push.

[t3.json](t3.json) defines project scripts: it builds each new worktree in the background and adds **Test** and **Build app**. Coding agents read [AGENTS.md](AGENTS.md); `CLAUDE.md` points Claude Code to it.

## How we work

1. **Start from an issue** for bugs and features, using the issue forms. The [triage skill](#agent-skills) checks whether a report is already tracked, fixed or supported. A small, obvious fix can go straight to a pull request.
2. **Branch from `main` and open a pull request.** Nobody pushes to `main` directly. Fill in the template: the problem, the changes, how you tested them and how to merge. Upload screenshots of visible changes to the pull request instead of committing them.
3. **Keep one problem per pull request.** Unrelated fixes and cleanups get their own.
4. **Wait for CI.** `Test` and `Commit messages` must pass.
5. **Merge** with a merge commit or a rebase merge, so semantic-release sees each commit. Squash only when the title alone should reach the changelog.

Reviews are requested automatically from the people listed in [CODEOWNERS](.github/CODEOWNERS), but they are not required. Ask for one when a change is risky or outside your usual area.

## Commits and releases

Pull requests run `swift test` on macOS and check that every commit message, and the pull request title, follows [Conventional Commits](https://www.conventionalcommits.org). Squash merges use the title as the commit message.

After the tests pass on `main`, [semantic-release](https://github.com/semantic-release/semantic-release) reads the commits since the last tag and decides the next version:

| Commit | Release |
| --- | --- |
| `fix:`, `perf:` | Patch: 0.1.0 → 0.1.1 |
| `feat:` | Minor: 0.1.0 → 0.2.0 |
| `feat!:`, or a `BREAKING CHANGE:` footer | Major: 0.1.0 → 1.0.0 |
| `build:`, `chore:`, `ci:`, `docs:`, `refactor:`, `style:`, `test:` | None |

A release sets `CFBundleShortVersionString` and `CFBundleVersion` in [Resources/Info.plist](Resources/Info.plist) with `scripts/set-version.sh`, adds its notes to `CHANGELOG.md`, commits both as `chore(release): <version>`, tags `v<version>` and publishes the notes as a GitHub release.

## Agent skills

Skills for coding agents live in [.agents/skills](.agents/skills), one folder per skill with a `SKILL.md`. Codex reads that directory, and `.claude/skills` links to it for Claude Code. Invoke a skill by name (`/triage` in Claude Code, `$triage` in Codex) or describe the task and let the agent choose it.

| Skill | Use |
| --- | --- |
| [triage](.agents/skills/triage/SKILL.md) | Checks a bug report or feature request against issues, pull requests, `main` and releases, and drafts a GitHub issue when nothing covers it. It posts only what you asked it to file or approved. |

To add a skill, create `.agents/skills/<name>/SKILL.md` with `name` and `description` front matter.

## Security

Report vulnerabilities privately, as described in [SECURITY.md](.github/SECURITY.md).
