# Contributing to Gemini CLI Skills

## Creating a New Skill

### Directory Structure

Each skill lives under `skills/<skill-name>/` with the following layout:

```
skills/<skill-name>/
├── SKILL.md              (required — entry point with YAML frontmatter)
├── README.md             (required — human-readable docs)
├── references/           (optional — templates, guides, cheat sheets)
│   └── *.md
└── scripts/              (optional — helper scripts the skill can invoke)
    └── *.sh
```

### SKILL.md Format

The `SKILL.md` file is the entry point that Gemini CLI reads. It must start with YAML frontmatter:

```yaml
---
name: your-skill-name
description: A short one-line description of what the skill does
---
```

After the frontmatter, write the full instructions that Gemini should follow when the skill is active. This is free-form markdown — treat it as a system prompt for the skill's behavior.

### Naming Conventions

- Use lowercase kebab-case for skill directory names (e.g., `software-troubleshooter`).
- The `name` field in SKILL.md frontmatter must match the directory name.
- Keep names descriptive but concise.

### References and Scripts

- Place any templates, guides, or reference material in `references/`.
- Place any shell scripts in `scripts/`. Ensure they are portable across macOS and Linux.
- All scripts must be executable (`chmod +x`).

## Testing Checklist

Before submitting a PR, verify:

- [ ] `SKILL.md` has valid YAML frontmatter with `name` and `description` fields
- [ ] The `name` field matches the directory name
- [ ] `README.md` exists with usage examples
- [ ] All scripts are executable and run on both macOS and Linux
- [ ] The skill works when installed via `scripts/install.sh <skill-name>`
- [ ] The skill works when copied manually to `~/.gemini/skills/<name>/`
- [ ] No hardcoded absolute paths in any file

## Pull Request Guidelines

1. One skill per PR (unless the changes are tightly coupled).
2. Update the root `README.md` skills catalog table with your new skill.
3. Include a brief description of the skill's purpose and target audience in the PR body.
4. Test all three installation methods before submitting.
