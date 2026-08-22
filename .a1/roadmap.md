# Pro Orc v3 „agenticOS" — Roadmap

> 2026-07-05. Details: docs/plans/2026-07-05-v3-agentic-os-plan.md

| Milestone | Inhalt | Status |
|---|---|---|
| M1 — Stabilisierung + Fenster-Fix (v2.2) | Bug-Fixes (GitHub-Regex, Rescan-Caching, async Memory-Reader, catch-Logging, Papierkorb-Delete), ActivationPolicy-Switching | done (2026-07-05, Branch feature/v2.2-stabilization) |
| M2 — Design-Refresh hell | Light-Theme, Theme-Umschalter, theme-fähige GlassCard/Orb | done (2026-07-05) |
| M3 — agenticOS Views | Agents-Tab (global+projekt-lokal), Skills-Tab | done (2026-07-05, Plugin-Skills als TODO) |
| M4 — Sessions + Graph | Session-Monitoring (JSONL), Zusammenarbeits-Mini-Graph im Detail-Panel | done (2026-07-05; voller Netzwerk-Tab offen) |
| M5 — Harness-Sichtbarkeit | Session-Deep-Dive, Harness-Tab, Skill-Launcher, Secret-Maskierung | done (2026-07-05, gemerged 8369413) |
| M6 — Selbstlernendes OS | Learning-Tab (Retros/Patterns/Observations), a1-Phasen-Status, Automatisierungen | done (2026-07-05, gemerged 695d189) |
| M7 — Abrundung | Netzwerk-Vollansicht, Plugin-Skills, Token-Schätzung | done (2026-07-05, gemerged f03b2a6) — **v3-Roadmap komplett** |
| M8 — Projekt-Organisation | Kacheln/Listen-Ansicht, benutzerdefinierte Gruppen (Drag&Drop, Rechtsklick), Projekt duplizieren/umbenennen, a1-SpecForge-Kennzeichnung | planning (2026-07-10) |
<!-- entry: m8-project-organization -->

> Ab M9 ist `docs/product/ROADMAP.md` (schema v1) die Source of Truth. Diese Datei hält nur noch die Entry-Marker für den Grep-Check von a1-new-feature/a1-execute.

## Milestone 11: Learning-Loop & Second-Brain-Fundament
<!-- entry: m11-agentic-loop-foundation -->
**Goal:** a1-Self-Improvement-Loop schließen und dem Vault eine billige Navigationskarte geben (Video-Level 1+2).
**Success:** a1-evolve gelaufen, Cloud-Brain-Push repariert, Vault-Indizes + Vault-CLAUDE.md vorhanden, Session-Mining-Skills gebaut, wöchentliche Learning-Automation aktiv.

### Phase M11-P1: close-learning-loop
<!-- entry: m11-p1-close-learning-loop -->
**Status:** planned

### Phase M11-P2: vault-navigation-map
<!-- entry: m11-p2-vault-navigation-map -->
**Status:** planned

### Phase M11-P3: session-skill-mining
<!-- entry: m11-p3-session-skill-mining -->
**Status:** planned

### Phase M11-P4: learning-loop-automation
<!-- entry: m11-p4-learning-loop-automation -->
**Status:** planned

## Milestone 12: ProOrc Vault-Integration & Skill-Buttons
<!-- entry: m12-vault-integration -->
**Goal:** ProOrc füttert das Second Brain (Status-Writer) und macht a1-Skills zu Ein-Klick-Buttons via headless `claude -p` (Video-Level 3).
**Success:** Projektstatus erscheint in den Vault-Projekt-Hubs; Skill-Buttons laufen headless durch den ProcessSemaphore, Output landet im Vault.
**Status:** planned (Phasen werden erst nach M11-Abschluss gescaffoldet — one-milestone-ahead-Regel)
