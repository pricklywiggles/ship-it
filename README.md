# Fractally Claude Marketplace

Fractally's [Claude Code](https://code.claude.com) plugins: a marketplace you add to Claude Code to install them by name.

## Quick start

Add the marketplace once (requires a Claude Code with plugin support; run `/plugin` to confirm it's available):

```shell
/plugin marketplace add pricklywiggles/fractally-claude-marketplace
```

Then browse and install from the interactive menu:

```shell
/plugin
```

…or install a specific plugin directly (see below).

## Plugins

| Plugin | What it does |
|---|---|
| **[ship-it](plugins/ship-it/README.md)** | Drive a batch of issues (or your current local changes) from work to merged PR, end to end and concurrently: implement, review, comment cleanup, and PR, with living docs kept in sync. A configurable orchestrator plus standalone, individually callable stage skills. |
| **[stack-it](plugins/stack-it/README.md)** | Take a new project from nothing to a working, verified, documented tech stack: identify the decision categories, research and pick version-pinned, security-vetted tools, install them, scaffold a vertical slice and run it green, then document the stack. A resume-aware orchestrator plus five standalone stage skills. |

Install them:

```shell
/plugin install ship-it@fractally-claude-marketplace
/plugin install stack-it@fractally-claude-marketplace
```

The `@fractally-claude-marketplace` suffix is the marketplace's name (from [`marketplace.json`](.claude-plugin/marketplace.json)), not the repo name. Each plugin's skills auto-activate when Claude judges them relevant, or you can invoke one explicitly as `/<plugin>:<skill>` (e.g. `/ship-it:init`, `/stack-it:setup-stack`). Both plugins have a full web manual: the marketplace site at **[pricklywiggles.github.io/fractally-claude-marketplace](https://pricklywiggles.github.io/fractally-claude-marketplace/)** links out to the [ship-it](https://pricklywiggles.github.io/fractally-claude-marketplace/ship-it.html) and [stack-it](https://pricklywiggles.github.io/fractally-claude-marketplace/stack-it.html) manuals.

## Team setup (no prompts)

To enable these for a whole team without anyone running commands, add to `.claude/settings.json` (project) or `~/.claude/settings.json` (user):

```json
{
  "extraKnownMarketplaces": {
    "fractally-claude-marketplace": {
      "source": { "source": "github", "repo": "pricklywiggles/fractally-claude-marketplace" }
    }
  },
  "enabledPlugins": {
    "ship-it@fractally-claude-marketplace": true,
    "stack-it@fractally-claude-marketplace": true
  }
}
```

## Managing the marketplace

```shell
/plugin marketplace update fractally-claude-marketplace   # refresh plugin listings
/plugin marketplace remove fractally-claude-marketplace   # remove it (and its plugins)
```

## Repository layout

```
.claude-plugin/marketplace.json   # the marketplace manifest: lists the plugins
plugins/
  ship-it/                        # → plugins/ship-it/README.md
  stack-it/                       # → plugins/stack-it/README.md
docs/                             # the published site (GitHub Pages)
```

Each plugin is self-contained under `plugins/<name>/`, with its own `.claude-plugin/plugin.json`, `skills/`, and README. To add a plugin, drop it under `plugins/` and add an entry to [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).
