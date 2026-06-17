# Claude Code in a rootless podman container.
#
# Build:  ./ccbox build
# See README.md for the full workflow.

FROM node:24-bookworm-slim

# --- base tools (git, ssh, gh, gcloud, ...) -------------------------------
# install-tools.sh is the single seam for extending the toolset.
COPY install-tools.sh /tmp/install-tools.sh
RUN chmod +x /tmp/install-tools.sh && /tmp/install-tools.sh && rm /tmp/install-tools.sh

# --- Claude Code ----------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# --- non-root runtime user ------------------------------------------------
# Run as the base image's built-in "node" user (uid 1000, home /home/node).
# Matching uid 1000 lets plain `--userns=keep-id` map it to the host user, so
# files written into the mounted workspace stay owned by you. Never root.

# Atlassian remote MCP definition, registered on first auth (see ccbox).
COPY mcp-atlassian.json /etc/ccbox/mcp-atlassian.json

USER node
WORKDIR /workspace

CMD ["claude"]
