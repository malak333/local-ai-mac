# MCP Server Configuration

## Desktop Automation: computer-use-mcp

**Package**: `computer-use-mcp` (by domdomegg)
**NPM**: https://www.npmjs.com/package/computer-use-mcp
**GitHub**: https://github.com/domdomegg/computer-use-mcp

### Purpose

MCP server for desktop computer control via nut.js. Exposes tools for:
- Screenshot capture
- Mouse movement and clicking
- Keyboard input
- Clipboard operations

### Configuration

```json
{
  "mcp": {
    "computer-use": {
      "type": "local",
      "command": ["npx", "-y", "computer-use-mcp"],
      "enabled": true
    }
  }
}
```

### macOS Permissions Required

The terminal application used with OpenCode must have these permissions granted:

1. **System Settings > Privacy & Security > Screen Recording**
2. **System Settings > Privacy & Security > Accessibility**

Without these, the MCP server cannot take screenshots or control mouse/keyboard.

---

## Browser Automation: opencode-chromium

**Package**: `opencode-chromium` (by Quindart-com)
**NPM**: https://www.npmjs.com/package/opencode-chromium
**GitHub**: https://github.com/Quindart-com/opencode-chromium
**Version installed**: 1.7.2

### Purpose

Chromium-based browser automation for MCP clients. Provides four tools:
- `browser_run` - Execute JavaScript in the browser
- `browser_observe` - Get DOM snapshot with accessibility tree
- `browser_session` - Manage browser session
- `browser_finalize` - Clean up session

Supports Chrome, Edge, Brave, and Chromium.

### Installation

Installed globally via npm:
```bash
npm install -g opencode-chromium
```

This provides the `opencode-chromium-mcp` binary and native plugin adapter.

### Configuration

Two integration methods are configured:

**1. Native OpenCode plugin** (in `plugin` array):
```json
{
  "plugin": ["opencode-chromium"]
}
```

**2. MCP server** (in `mcp` object):
```json
{
  "mcp": {
    "opencode-browser-plugin": {
      "type": "local",
      "command": ["opencode-chromium-mcp"],
      "enabled": true
    }
  }
}
```

Do not enable both the native adapter and MCP server in the same session unless duplicate tools are intentional.

### Requirements

- A Chromium-based browser installed (Chrome, Edge, Brave, Chromium)
- Node.js >= 18 (already available via npm)

---

## Knowledge Base Entries

### Session: MCP Computer Use Setup (September 10, 2026)

**Decision**: Added desktop and browser automation via MCP servers.

**Why**: OpenCode doesn't have native computer use capabilities. MCP servers provide the integration path for external tool access including GUI automation.

**Chosen packages**:
- `computer-use-mcp` for desktop automation (mouse, keyboard, screenshots)
- `opencode-chromium` for browser automation (DOM interaction, JavaScript execution)

**Implementation notes**:
- `computer-use-mcp` runs via `npx` (no global install needed)
- `opencode-chromium` installed globally for both native plugin and MCP server
- macOS Screen Recording and Accessibility permissions required for computer-use-mcp
- Browser must be Chromium-based for opencode-chromium

**Config path**: `config/opencode.json`

**Relevant env variables**: None required for these MCP servers.

### Session: OpenCode MCP Architecture (September 10, 2026)

**Key patterns**:
- MCP servers add to context size — only enable needed servers
- Local MCP servers run as child processes via `command` array
- Native plugins use the `plugin` array in opencode.json
- After any config change, opencode must be restarted for changes to take effect

**MCP config schema**:
```json
{
  "mcp": {
    "server-name": {
      "type": "local",           // "local" or "remote"
      "command": ["binary", "args"],
      "enabled": true,
      "environment": {},
      "timeout": 5000
    }
  }
}
```

**Plugin config schema**:
```json
{
  "plugin": ["npm-package", "./local-plugin.ts", ["package", {"key": "val"}]]
}
```

**Alternative MCP servers considered**:
- `@atomicbotai/computer-use-mcp` - Has native OCR capabilities
- `chrome-devtools-mcp` - Official Chrome DevTools MCP server
- `opencode-browser-mcp` (mirsella) - Session-isolated browser automation
- `opencode-browser-mcp` (HoganDong486) - Playwright-based, cross-browser

**Resources**:
- OpenCode MCP docs: https://opencode.ai/docs/mcp-servers/
- OpenCode plugins docs: https://opencode.ai/docs/plugins/
- OpenCode ecosystem: https://opencode.ai/docs/ecosystem/
