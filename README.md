# ccbox — Claude Code in a podman container

Run Claude Code inside a rootless podman container with `gh`, `gcloud`, `git`
(SSH), and an authenticated Atlassian MCP server — without giving the agent
any access to your host beyond the directory you launch it from.

## Design

- **Isolation first.** The only host bind mount is your current working
  directory. All credentials are created *inside* the container and persist in
  a named podman volume (`ccbox-home`); your host config dirs and `~/.ssh` are
  never exposed.
- **Rootless + SELinux-aware.** Runs as a non-root user, with `:z` shared
  relabeling and `--userns=keep-id` so files you create in the workspace stay
  owned by you — and so concurrent instances on the same repo don't fight over
  the SELinux label.

## Files

| File | Purpose |
|------|---------|
| `Containerfile` | Image: Node 24 + Claude Code + base tools |
| `install-tools.sh` | **The seam for adding tools** — one function per tool |
| `mcp-atlassian.json` | Atlassian remote MCP server definition |
| `managed-settings.json` | Claude Code policy settings baked into the image |
| `ccbox` | Launcher: `build` / `update` / `auth` / `auto` / `shell` / `help` / run |

## Quick start

```bash
./ccbox build          # build the image (add --no-cache for a clean rebuild)
./ccbox update         # later: bump Claude Code only, no full rebuild
./ccbox auth           # one-time logins (see below)
cd ~/your/project
/path/to/ccbox          # launch Claude Code against this dir
```

Put `ccbox` on your PATH for convenience (a write to your own bin dir):

```bash
ln -s "$PWD/ccbox" ~/.local/bin/ccbox
```

## Auto mode (`./ccbox auto`)

Launches Claude Code with `--permission-mode auto` — actions run autonomously,
gated by background safety checks instead of per-action prompts. This is broader
than the `acceptEdits` mode you reach by cycling with shift+tab (which only
auto-accepts file edits), so reach for it deliberately:

```bash
cd ~/your/project
ccbox auto             # run with permission mode set to auto
ccbox auto [args]      # extra args pass through to claude
```

Because the container only ever sees the directory you launch it from, the
agent can act freely without reaching anything else on your host.

## First-run auth (`./ccbox auth`)

Drops you into the container and prints guidance. Run once — everything
persists in the `ccbox-home` volume:

```bash
gh auth login
gcloud auth login --no-launch-browser
claude                       # sign in to your subscription, then /exit
# run any Atlassian query inside `claude` once to complete its OAuth
```

`auth` also generates a **dedicated SSH key** in the volume and prints its
public key — add that to GitHub / your git hosts. Add host aliases to
`~/.ssh/config` inside the container as needed.

## Updating Claude Code

```bash
ccbox update           # update to the latest release
ccbox update 2.1.215   # or pin an exact version
```

Takes seconds, not a full rebuild. Claude Code is installed in the **last**
image layer, keyed on a `CC_VERSION` build arg; `update` resolves the version
you asked for and rebuilds from that layer onward, so everything above it —
notably git built from source — is reused from the layer cache. If you're
already on the target version the build arg is unchanged, the cache hits, and
the command is a no-op.

Claude Code's built-in updater does **not** work in this container, by design:
npm's global dir is root-owned and the container runs as `node`, so a
self-update fails with `no_permissions`. That's the tradeoff for keeping the
agent non-root and the installed toolchain immutable — the version is a
property of the image, so `ccbox update` is the way to move it.

Note that a plain `ccbox build` will *not* pick up a new Claude Code release:
the build arg still says `latest`, which is unchanged from the cache's point of
view. Use `ccbox update` (or `ccbox build --no-cache`, which rebuilds
everything, git included).

## Adding a tool

Edit `install-tools.sh`: add an `install_<name>` function and a call to it in
the call list at the bottom, then `./ccbox build`. That's the only place to
change.

## Claude Code settings (baked into the image)

Image-wide Claude Code defaults live in `managed-settings.json`, copied to
`/etc/claude-code/managed-settings.json` at build time. That path is Claude
Code's managed-policy location and sits **outside** the `ccbox-home` volume, so
the defaults survive the volume mount and apply to every run — including a brand
new volume. This is the same pattern as the container-wide `worktree.useRelativePaths`
git default: an image-baked preference kept out of your home volume.

Managed settings are enforced policy (highest precedence), so they can't be
overridden per-user or per-project — reserve this file for defaults you always
want on. Current contents:

| Key | Value | Effect |
|-----|-------|--------|
| `respondToBashCommands` | `false` | After an input-box `!` command runs, its output is added to context **without** Claude responding to it. |

To change a default, edit `managed-settings.json` and `./ccbox build`.

## Accessing your platform (db + services)

Bring your platform up with its existing compose file, then join the agent to
its network so it can reach services by name:

```bash
podman compose up -d                 # your existing platform compose
podman network ls                    # find the network, e.g. myapp_default
CCBOX_NET=myapp_default ./ccbox      # agent joins it; reach db, api, ... by name
```

Outbound internet still works on that network, so `gh`/`gcloud`/Claude/MCP
remain reachable.

## Environment overrides

| Var | Default | Meaning |
|-----|---------|---------|
| `CCBOX_NET` | `podman` | podman network to join (set to your platform's) |
| `CCBOX_IMAGE` | `ccbox:latest` | image tag |
| `CCBOX_VOLUME` | `ccbox-home` | credentials volume name |

## Git worktrees

A linked worktree records its link to the main repo by path. On the host that
path is the repo's real location; in the container the repo is mounted at
`/workspace` — two different paths for the same checkout, which is what breaks
worktrees created on one side and used on the other.

ccbox handles this by **building git from source (≥ 2.48) and defaulting to
`worktree.useRelativePaths`**, so a worktree created inside the container
records its links *relative* to the repo. The same checkout then resolves both
in the container and on the host. This only covers worktrees **created inside
the container**: one you made on the *host* with ordinary git records *absolute*
links to the host path, which don't exist at `/workspace`, so make worktrees
from inside ccbox, not on the host. The preference lives in the container's
system git config only — never written to your home volume or to any repo, so
the preference itself never leaks across the bind mount.

**Your host git must also be ≥ 2.48.** Creating a relative worktree permanently
marks the repo: git writes `extensions.relativeWorktrees` into
`<repo>/.git/config` and bumps `core.repositoryformatversion` to `1`. That file
lives in the bind-mounted checkout, so the marking is visible on the host too. A
host git that predates the extension then **refuses every command on the repo** —
`git status`, `log`, `commit`, `push`, and libgit2-backed editors (VS Code,
JetBrains) all fail with `fatal: unknown repository extension found:
relativeworktrees`. Many common hosts ship older git (Ubuntu 22.04 → 2.34,
Debian 12 → 2.39, Debian 13 → 2.47, Apple/Xcode git ≈ 2.39), so check
`git --version` on the host before using this. The marker is sticky and outlives
the worktrees; undo it with `git config --unset extensions.relativeWorktrees`
run from the repo.

One rule: **launch ccbox from the main repo root, not from inside a worktree
directory.** That mounts the repo — including worktrees nested under it, such as
`.claude/worktrees/<name>` — as a unit at `/workspace`, so the relative links
resolve. Claude can then create and enter worktrees during the session.

## Host boundary (what crosses it)

- `$PWD` → `/workspace` (`:z`, shared SELinux label) — the one bind mount.
- `ccbox-home` named volume — podman-managed, not a host path.
- Shared podman network (when `CCBOX_NET` is set) + outbound network.
- Nothing else: no host config dirs, no `~/.ssh`, no podman/Docker socket,
  non-root, rootless. Any future host path is added explicitly, with approval.
