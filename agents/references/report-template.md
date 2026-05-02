# Canonical Report Template

Every numbered report file (`NN-name.md`) produced by an agent in this toolkit follows this structure. Downstream agents and the orchestrator parse reports by section heading, so **section names and order are not optional** — only the body content varies per report.

## Required filename

`NN-kebab-case-name.md` where `NN` is the two-digit canonical report ID from `agents/migration-orchestrator.md`. The `before-tool-write.sh` hook enforces this.

## Required header block

The first lines of every report:

```markdown
# [Report Title]

**Report:** NN-name (the canonical filename without `.md`)
**Subject:** One-sentence description of what this report covers.
**Status:** Draft | In Progress | Complete | Requires Review
**Date:** YYYY-MM-DD (UTC)
**Producer:** @agent-name
**Topic:** One-sentence summary of the most important finding.

---
```

## Required sections (in this exact order)

### 1. Executive Summary
3–5 bullets covering the most critical findings. Stand alone; a reader who only reads this section should understand the headline conclusions.

### 2. Scope
What was analyzed:
- **Inputs:** report files / source files consumed (list with paths).
- **Boundaries:** what was deliberately excluded.
- **Environment:** Sybase ASE version, app stack, etc., as relevant.

### 3. Detailed Findings
The meat. Numbered subsections (3.1, 3.2, …) with tables, code blocks, and analysis. Every claim must trace to a source file or report.

### 4. Impact Analysis
Always a table:

| Area | Impact | Severity | Details |
|------|--------|----------|---------|

Severity uses one of: `Low`, `Medium`, `High`, `Critical`. Downstream agents grep for this column.

### 5. Affected Components
List of Sybase objects, application modules, integrations, or batch jobs touched by the findings. One bullet per component with a short rationale.

### 6. Reference Material
Internal pointers (other reports, skill `references/` files) and external pointers (Spanner docs, regulator guidance) that informed the conclusions.

### 7. Recommendations
Prioritized action items. For each, give:
- **Option A (Recommended):** what to do, why.
- **Option B (Alternative):** rejected option, why.
- **Effort:** S / M / L.
- **Owner:** role or team to action.

### 8. Dependencies and Prerequisites
What must be true before the recommendations in §7 can be acted on. List upstream report numbers, data availability requirements, and team/tool dependencies.

### 9. Verification Criteria
Concrete, testable checks that confirm the recommendations were implemented correctly. Each criterion is a single sentence with a measurable outcome.

## Optional appendices

If an agent needs to attach raw output (DDL listings, OpenAPI fragments, Mermaid diagrams), append them as `Appendix A`, `Appendix B`, … after §9. Do not embed appendix-sized blobs inside the numbered sections.

## Why this matters

- **Machine-readability:** orchestrator and downstream agents grep by section heading. Renaming `## 4. Impact Analysis` to `## Impact` breaks them silently.
- **Comparability:** `migration-orchestrator` synthesizes report 24 by joining tables across reports. Identical column names enable that.
- **Audit:** the financial-domain audit trail (`.gemini/audit/migration-audit.jsonl`) records section headings; a reviewer pulling sections by name needs them stable.

## Hook interactions

- `before-tool-write.sh` enforces the `NN-name.md` naming convention under `reports/`.
- `after-tool-report.sh` updates `migration-state.json` whenever a report matching this template is written.
- Neither hook validates the section structure itself; that is the agent's responsibility.
