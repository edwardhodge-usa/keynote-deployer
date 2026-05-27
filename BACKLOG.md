# Keynote Deployer — Backlog (moved)

The canonical Keynote Deployer backlog now lives in the ImagineLab vault:

- **App work:** `~/Obsidian/ImagineLab/Backlogs/Keynote Deployer.md`
- **Portal wiring (Keynote → Airtable → Framer):** `~/Obsidian/ImagineLab/Backlogs/Keynote Portal Wiring.md`

These files are the single source of truth for `/resume`, the ImagineLab Backlog dashboard, and Cortex. Edit them — not this file.

---

_Why the move:_ the dashboard reader skips vault entries for any project that has a non-empty repo `BACKLOG.md`, so two backlogs were silently diverging. Vault is canonical because Cortex, Obsidian linking, and `/resume` all read from it. (Migration: 2026-05-17) (This whole-file shadowing was fixed 2026-05-18 — the ImagineLab Backlog app now merges the repo `BACKLOG.md` and vault per item, and the Claude Dashboard reads the vault only; see the keep-empty note below. Kept here as the original migration rationale.)

**Keep this stub empty.** The canonical Keynote Deployer backlog lives in the vault (`~/Obsidian/ImagineLab/Backlogs/Keynote Deployer.md`). Items added here are **not** hidden by any dashboard — whole-file shadowing was fixed 2026-05-18 (the ImagineLab Backlog app merges/dedups both the repo `BACKLOG.md` and the vault `Backlogs/*.md` per item, by project + description; the Claude Dashboard reads the vault only and never reads repo `BACKLOG.md`). But items here create a **second source of truth that drifts from the vault**. Add backlog items to the vault file, not here.
