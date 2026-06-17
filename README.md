# ccbox — Claude Code in a podman container

Run Claude Code inside a rootless podman container with `gh`, `gcloud`, `git`
(SSH), and an authenticated Atlassian MCP server — without giving the agent
any access to your host beyond the directory you launch it from.

## Design

- **Isolation first.** The only host bind mount is your current working
  directory. All credentials are created *inside* the container and persist in
  a named podman volume (`ccbox-home`); your host config dirs and `~/.ssh` are
  never exposed.
- **Rootless + SELinux-aware.** Runs as a non-root user, with `:Z` relabeling
  and `--userns=keep-id` so files you create in the workspace stay owned by you.

## Files

| File | Purpose |
|------|---------|
| `Containerfile` | Image: Node 24 + Claude Code + base tools |
| `install-tools.sh` | **The seam for adding tools** — one function per tool |
| `mcp-atlassian.json` | Atlassian remote MCP server definition |
| `ccbox` | Launcher: `build` / `auth` / `auto` / `shell` / `help` / run |

## Quick start

```bash
./ccbox build          # build the image
./ccbox auth           # one-time logins (see below)
cd ~/your/project
/path/to/ccbox          # launch Claude Code against this dir
```

Put `ccbox` on your PATH for convenience (a write to your own bin dir):

```bash
ln -s "$PWD/ccbox" ~/.local/bin/ccbox
```

## Auto mode (`./ccbox auto`)

Launches Claude Code with `--permission-mode auto` — the same auto-accept mode
you reach by cycling permission modes with shift+tab, but on from the start:

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

## Adding a tool

Edit `install-tools.sh`: add an `install_<name>` function and a call to it in
the call list at the bottom, then `./ccbox build`. That's the only place to
change.

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

## Host boundary (what crosses it)

- `$PWD` → `/workspace` (`:Z`) — the one bind mount.
- `ccbox-home` named volume — podman-managed, not a host path.
- Shared podman network (when `CCBOX_NET` is set) + outbound network.
- Nothing else: no host config dirs, no `~/.ssh`, no podman/Docker socket,
  non-root, rootless. Any future host path is added explicitly, with approval.
