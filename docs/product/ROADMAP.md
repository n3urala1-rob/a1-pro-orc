---
schema_version: 1
type: roadmap
project: pro-orc
title: "Pro Orc"
status: active
updated: 2026-08-22
source: "scaffolded by a1-tools product init"
milestones:
  - id: m1-stabilization
    title: "Stabilization and window fix (v2.2)"
    status: done
    target: null
  - id: m2-design-refresh
    title: "Light theme design refresh"
    status: done
    target: null
  - id: m3-agentic-os-views
    title: "AgenticOS views"
    status: done
    target: null
  - id: m4-sessions-graph
    title: "Session monitoring and collaboration graph"
    status: done
    target: null
  - id: m5-harness-visibility
    title: "Harness visibility"
    status: done
    target: null
  - id: m6-learning-loop
    title: "Self-learning OS"
    status: done
    target: null
  - id: m7-network-costs
    title: "Rounding out v3"
    status: done
    target: null
  - id: m8-project-organization
    title: "Project organization"
    status: in-progress
    target: null
  - id: m9-detail-roadmap-redesign
    title: "Detail view and roadmap redesign"
    status: done
    target: null
  - id: m10-detail-ui-refinement
    title: "Detail UI refinement (compact, high-level)"
    status: done
    target: null
  - id: m11-agentic-loop-foundation
    title: "Learning loop & second brain foundation"
    status: in-progress
    target: null
  - id: m12-vault-integration
    title: "ProOrc vault integration & skill buttons"
    status: planned
    target: null
features:
  - id: 002-project-organization
    milestone: m8-project-organization
    title: "Project Hub: list/grid toggle, custom groups, archive, a1-badge"
    status: done
    stage: done
    depends_on: []
    started: 2026-07-12
    finished: 2026-07-15
    spec_path: projects/pro-orc/spec/002-project-organization.md
    plan_path: projects/pro-orc/plans/002-project-organization-wave-plan.md
  - id: 003-detail-roadmap-redesign
    milestone: m9-detail-roadmap-redesign
    title: "Detail view cleanup + tier-0 product-store roadmap (hero, lanes, cards, structured spec renderer, timeline)"
    status: done
    stage: null
    depends_on: []
    started: null
    finished: null
    spec_path: null
    plan_path: null
  - id: 004-magazine-detail-ui
    milestone: m9-detail-roadmap-redesign
    title: "Magazine-style detail UI: Vision/Roadmap/Zeitstrahl tabs per approved mockup"
    status: done
    stage: done
    depends_on: []
    started: 2026-07-16
    finished: 2026-07-16
    spec_path: null
    plan_path: null
  - id: 005-compact-detail-ui
    milestone: m10-detail-ui-refinement
    title: "Compact detail UI: sans fonts, milestone accordion, vision teaser (mockup v2)"
    status: done
    stage: done
    depends_on: []
    started: 2026-07-16
    finished: 2026-07-16
    spec_path: null
    plan_path: null
  - id: 006-vision-first-tab-consolidation
    milestone: m10-detail-ui-refinement
    title: "Vision-first tab consolidation: merge Übersicht into Vision, product version, links section"
    status: done
    stage: done
    depends_on: []
    started: 2026-07-16
    finished: 2026-07-16
    spec_path: null
    plan_path: null
  - id: 007-links-own-tab
    milestone: m10-detail-ui-refinement
    title: "Links section becomes its own tab (Vision|Roadmap|Zeitstrahl|Links)"
    status: done
    stage: done
    depends_on: []
    started: 2026-07-16
    finished: 2026-07-16
    spec_path: null
    plan_path: null
  - id: 008-files-tokens-own-tabs
    milestone: m10-detail-ui-refinement
    title: "Dateien and Token-Nutzung become their own tabs"
    status: done
    stage: done
    depends_on: []
    started: 2026-07-16
    finished: 2026-07-16
    spec_path: null
    plan_path: null
  - id: 009-complete-project-deletion
    milestone: m8-project-organization
    title: "Complete Project Deletion (incl. Vercel)"
    status: done
    stage: done
    depends_on: []
    started: 2026-07-20
    finished: 2026-07-20
    spec_path: projects/pro-orc/spec/007-complete-project-deletion.md
    plan_path: null
  - id: 010-deletion-scope-preflight-check
    milestone: m8-project-organization
    title: "Pre-Flight Permission Check for Destructive External Deletions"
    status: done
    stage: done
    depends_on:
      - 009-complete-project-deletion
    started: 2026-07-21
    finished: 2026-07-22
    spec_path: projects/pro-orc/spec/008-deletion-scope-preflight-check.md
    plan_path: null
  - id: 011-permission-popup-repo-owner
    milestone: m8-project-organization
    title: "Show Repo Owner in the Missing-Permission Popup"
    status: done
    stage: done
    depends_on:
      - 010-deletion-scope-preflight-check
    started: 2026-07-22
    finished: 2026-07-22
    spec_path: projects/pro-orc/spec/009-permission-popup-repo-owner.md
    plan_path: null
  - id: 012-close-learning-loop
    milestone: m11-agentic-loop-foundation
    title: "Close the learning loop: run a1-evolve over 7 pending postmortems, fix cloud-brain push 404"
    status: done
    stage: done
    depends_on: []
    started: 2026-08-22
    finished: 2026-08-22
    spec_path: null
    plan_path: null
  - id: 013-vault-navigation-map
    milestone: m11-agentic-loop-foundation
    title: "Vault navigation map: index.md per top-level folder + CLAUDE.md in vault root"
    status: done
    stage: done
    depends_on: []
    started: 2026-08-22
    finished: 2026-08-22
    spec_path: null
    plan_path: null
  - id: 014-session-skill-mining
    milestone: m11-agentic-loop-foundation
    title: "Session mining audit: extract repeated tasks from claude-mem history into new skills"
    status: done
    stage: done
    depends_on: []
    started: 2026-08-22
    finished: 2026-08-22
    spec_path: null
    plan_path: null
  - id: 015-learning-loop-automation
    milestone: m11-agentic-loop-foundation
    title: "Learning automation: weekly scheduled check for >=5 learnings and MEMORY.md limit"
    status: planned
    stage: null
    depends_on:
      - 012-close-learning-loop
    started: null
    finished: null
    spec_path: null
    plan_path: null
  - id: 016-vault-status-writer
    milestone: m12-vault-integration
    title: "ProOrc writes project status into vault project hubs"
    status: planned
    stage: null
    depends_on:
      - 013-vault-navigation-map
    started: null
    finished: null
    spec_path: null
    plan_path: null
  - id: 017-skill-buttons-headless
    milestone: m12-vault-integration
    title: "Skill buttons: one-click headless claude -p runs per project, output to vault"
    status: planned
    stage: null
    depends_on:
      - 014-session-skill-mining
      - 016-vault-status-writer
    started: null
    finished: null
    spec_path: null
    plan_path: null
next: null
---

# Pro Orc

## Milestones

(none yet — use `product add-milestone`)

## In-flight features

None.

## Changelog

- **2026-07-12** — project initialized — scaffolded by `product init`
- **2026-07-12** — milestone 'm1-stabilization' added — Fix critical bugs and switch window activation policy dynamically.
- **2026-07-12** — milestone 'm2-design-refresh' added — Ship a light glassmorphism theme with a mode switcher.
- **2026-07-12** — milestone 'm3-agentic-os-views' added — Show agents and skills (global and project-local) as first-class tabs.
- **2026-07-12** — milestone 'm4-sessions-graph' added — Show live Claude Code sessions and a mini collaboration graph per project.
- **2026-07-12** — milestone 'm5-harness-visibility' added — Expose hooks, rules, permissions, MCP config, and a skill launcher.
- **2026-07-12** — milestone 'm6-learning-loop' added — Surface a1 retros, patterns, and observations as a Learning tab.
- **2026-07-12** — milestone 'm7-network-costs' added — Full network view, plugin skills, and token cost estimation.
- **2026-07-12** — milestone 'm8-project-organization' added — Grid/list toggle, custom groups, and a1-SpecForge badge for organizing many projects.
- **2026-07-12** — feature '002-project-organization' added — Merge Code/Research tabs into one Projects view, group projects by context, add archive group.
- **2026-07-12** — 002-project-organization -> started — stage transition via `product stage`
- **2026-07-12** — feature.md created for '002-project-organization' — formal spec/plan attached via `product feature-init`
- **2026-07-12** — adopt: migrated legacy .a1/roadmap.md (M1-M8) to docs/product/ROADMAP.md schema v1 — M1-M7 marked done from merged feature branches + merge commits on main (evidence ladder rung b: feature/v2.2-stabilization, feature/v3-m5-harness-visibility, feature/v3-m6-learning-loop, feature/v3-m7-network-costs) plus release tag v3.0.0; M8 carried over as in-progress (no completion evidence yet). Legacy .a1/roadmap.md kept as-is, not deleted.
- **2026-07-13** — 002-project-organization -> complete — stage transition via `product stage`
- **2026-07-13** — 002-project-organization -> merge — stage transition via `product stage`
- **2026-07-13** — 002-project-organization -> origin-cleanup — stage transition via `product stage`
- **2026-07-15** — 002-project-organization -> done — stage transition via `product stage`
- **2026-07-15** — milestone 'm9-detail-roadmap-redesign' added — Non-technical, visual project detail + drill-down roadmap view
- **2026-07-15** — feature '003-detail-roadmap-redesign' added — Non-technical, visual project detail + drill-down roadmap view
- **2026-07-15** — milestone m9-detail-roadmap-redesign status -> done — marker set via `product markers --set`
- **2026-07-15** — feature '004-magazine-detail-ui' added — Implement docs/design/roadmap-redesign-mockup.html 1:1 in Flutter
- **2026-07-15** — milestone m9-detail-roadmap-redesign status -> in-progress — marker set via `product markers --set`
- **2026-07-16** — 004-magazine-detail-ui -> verify — stage transition via `product stage`
- **2026-07-16** — 004-magazine-detail-ui -> done — stage transition via `product stage`
- **2026-07-16** — milestone m9-detail-roadmap-redesign status -> done — marker set via `product markers --set`
- **2026-07-16** — milestone 'm10-detail-ui-refinement' added — Live-feedback iteration on the magazine detail UI: sans typography, compact milestone accordion, vision teaser in overview
- **2026-07-16** — feature '005-compact-detail-ui' added — new feature via `product add-feature`
- **2026-07-16** — 005-compact-detail-ui -> started — stage transition via `product stage`
- **2026-07-16** — 005-compact-detail-ui -> complete — stage transition via `product stage`
- **2026-07-16** — 005-compact-detail-ui -> review — stage transition via `product stage`
- **2026-07-16** — 005-compact-detail-ui -> verify — stage transition via `product stage`
- **2026-07-16** — 005-compact-detail-ui -> merge — stage transition via `product stage`
- **2026-07-16** — 005-compact-detail-ui -> origin-cleanup — stage transition via `product stage`
- **2026-07-16** — 005-compact-detail-ui -> done — stage transition via `product stage`
- **2026-07-16** — milestone m10-detail-ui-refinement status -> done — marker set via `product markers --set`
- **2026-07-16** — feature '006-vision-first-tab-consolidation' added — new feature via `product add-feature`
- **2026-07-16** — 006-vision-first-tab-consolidation -> started — stage transition via `product stage`
- **2026-07-16** — 006-vision-first-tab-consolidation -> complete — stage transition via `product stage`
- **2026-07-16** — 006-vision-first-tab-consolidation -> review — stage transition via `product stage`
- **2026-07-16** — 006-vision-first-tab-consolidation -> verify — stage transition via `product stage`
- **2026-07-16** — 006-vision-first-tab-consolidation -> merge — stage transition via `product stage`
- **2026-07-16** — 006-vision-first-tab-consolidation -> origin-cleanup — stage transition via `product stage`
- **2026-07-16** — 006-vision-first-tab-consolidation -> done — stage transition via `product stage`
- **2026-07-16** — feature '007-links-own-tab' added — new feature via `product add-feature`
- **2026-07-16** — 007-links-own-tab -> started — stage transition via `product stage`
- **2026-07-16** — 007-links-own-tab -> complete — stage transition via `product stage`
- **2026-07-16** — 007-links-own-tab -> review — stage transition via `product stage`
- **2026-07-16** — 007-links-own-tab -> verify — stage transition via `product stage`
- **2026-07-16** — 007-links-own-tab -> merge — stage transition via `product stage`
- **2026-07-16** — 007-links-own-tab -> origin-cleanup — stage transition via `product stage`
- **2026-07-16** — 007-links-own-tab -> done — stage transition via `product stage`
- **2026-07-16** — feature '008-files-tokens-own-tabs' added — new feature via `product add-feature`
- **2026-07-16** — 008-files-tokens-own-tabs -> started — stage transition via `product stage`
- **2026-07-16** — 008-files-tokens-own-tabs -> complete — stage transition via `product stage`
- **2026-07-16** — 008-files-tokens-own-tabs -> review — stage transition via `product stage`
- **2026-07-16** — 008-files-tokens-own-tabs -> verify — stage transition via `product stage`
- **2026-07-16** — 008-files-tokens-own-tabs -> merge — stage transition via `product stage`
- **2026-07-16** — 008-files-tokens-own-tabs -> origin-cleanup — stage transition via `product stage`
- **2026-07-16** — 008-files-tokens-own-tabs -> done — stage transition via `product stage`
- **2026-07-19** — feature '009-complete-project-deletion' added — new feature via `product add-feature`
- **2026-07-19** — feature.md created for '009-complete-project-deletion' — formal spec/plan attached via `product feature-init`
- **2026-07-20** — 009-complete-project-deletion -> done — stage transition via `product stage`
- **2026-07-21** — feature '010-deletion-scope-preflight-check' added — Detect a missing GitHub delete_repo scope when the user checks the resource, before any deletion is attempted
- **2026-07-21** — feature.md created for '010-deletion-scope-preflight-check' — formal spec/plan attached via `product feature-init`
- **2026-07-21** — 010-deletion-scope-preflight-check -> started — stage transition via `product stage`
- **2026-07-22** — 010-deletion-scope-preflight-check -> complete — stage transition via `product stage`
- **2026-07-22** — 010-deletion-scope-preflight-check -> review — stage transition via `product stage`
- **2026-07-22** — 010-deletion-scope-preflight-check -> verify — stage transition via `product stage`
- **2026-07-22** — 010-deletion-scope-preflight-check -> merge — stage transition via `product stage`
- **2026-07-22** — 010-deletion-scope-preflight-check -> origin-cleanup — stage transition via `product stage`
- **2026-07-22** — 010-deletion-scope-preflight-check -> done — stage transition via `product stage`
- **2026-07-22** — feature '011-permission-popup-repo-owner' added — Display the GitHub repository owner in the missing-permission popup so users with multiple accounts know which one to authenticate with
- **2026-07-22** — feature.md created for '011-permission-popup-repo-owner' — formal spec/plan attached via `product feature-init`
- **2026-07-22** — 011-permission-popup-repo-owner -> started — stage transition via `product stage`
- **2026-07-22** — 011-permission-popup-repo-owner -> complete — stage transition via `product stage`
- **2026-07-22** — 011-permission-popup-repo-owner -> review — stage transition via `product stage`
- **2026-07-22** — 011-permission-popup-repo-owner -> verify — stage transition via `product stage`
- **2026-07-22** — 011-permission-popup-repo-owner -> merge — stage transition via `product stage`
- **2026-07-22** — 011-permission-popup-repo-owner -> origin-cleanup — stage transition via `product stage`
- **2026-07-22** — 011-permission-popup-repo-owner -> done — stage transition via `product stage`
- **2026-08-21** — milestone 'm11-agentic-loop-foundation' added — Close the a1 self-improvement loop and give Claude a cheap navigation map of the vault (video levels 1+2: skills, loops, memory, state).
- **2026-08-21** — milestone 'm12-vault-integration' added — ProOrc feeds the second brain (status writer) and exposes a1 skills as one-click headless buttons (video level 3).
- **2026-08-21** — feature '012-close-learning-loop' added — The accumulated learnings (7 postmortems > threshold 5) are synthesized via a1-evolve and the broken cloud-brain push endpoint (HTTP 404 since 2026-08-17) works again.
- **2026-08-21** — feature '013-vault-navigation-map' added — Every top-level vault folder has a maintained index/MOC and the vault root has a CLAUDE.md with structure + navigation pattern, so Claude navigates the vault cheaply (Karpathy pattern).
- **2026-08-21** — feature '014-session-skill-mining' added — Recurring manual workflows (e.g. the ProOrc release process) are identified from real session history and codified as skills.
- **2026-08-21** — feature '015-learning-loop-automation' added — A scheduled routine checks weekly whether >=5 new learnings call for a1-evolve and whether MEMORY.md approaches its 200-line limit (rem-sleep), removing reliance on manual discipline.
- **2026-08-21** — feature '016-vault-status-writer' added — ProOrc updates status lines in the vault's project/<slug>.md hubs so the dashboard feeds the second brain instead of living beside it.
- **2026-08-21** — feature '017-skill-buttons-headless' added — ProOrc project cards offer buttons that run a1 skills headless via claude -p (through the ProcessSemaphore), writing results into the vault.
- **2026-08-22** — 012-close-learning-loop -> started — stage transition via `product stage`
- **2026-08-22** — 012-close-learning-loop -> done — stage transition via `product stage`
- **2026-08-22** — milestone m11-agentic-loop-foundation status -> in-progress — marker set via `product markers --set`
- **2026-08-22** — 013-vault-navigation-map -> started — stage transition via `product stage`
- **2026-08-22** — 013-vault-navigation-map -> done — stage transition via `product stage`
- **2026-08-22** — 014-session-skill-mining -> started — stage transition via `product stage`
- **2026-08-22** — 014-session-skill-mining -> done — stage transition via `product stage`

## Appendix — migrated details

(none)
