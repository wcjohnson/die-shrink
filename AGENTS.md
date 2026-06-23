# AGENTS

This file provides working guidance for human and AI coding agents contributing
to Die Shrink.

## Project Snapshot

- Name: Die Shrink
- Type: Factorio 2.0 mod (Lua 5.2)
- Goal: let players compose many combinators in a design space, then compile and
  shrink the result into a single 1x1 circuit element in the world.
- Scope philosophy: focused and minimal. Keep features centered on integrated
  circuit shrinking and pin I/O.

## Primary Architecture

- Data stage entrypoint: `data.lua`
- Runtime entrypoint: `control.lua`
- Runtime modules: `control/`
- Prototype definitions: `data/`
- Shared utility/framework code: `lib/`
- Constants: `lib/constants.lua`
- Locale: `locale/en/base.cfg`
- Metadata: `info.json`, `changelog.txt`

Notes:

- `data.lua` defines custom events, custom input, and registrations for IC/pin
  entities.
- `control.lua` wires runtime behavior and logging/trace integration.
- The mod depends on `0-things`; preserve its integration points unless a
  change explicitly targets that API usage.

## Working Rules

1. Preserve behavior first.
2. Keep changes small and targeted.
3. Do not introduce broad refactors unless requested.
4. Prefer extending existing module patterns over adding new abstractions.
5. Keep deterministic behavior for blueprint, orientation, and child-entity
   handling.

## Style And Formatting

- Lua target: Lua 5.2 semantics.
- Formatting is defined in `stylua.toml`:
  - Tabs for indentation
  - Width 80
  - Windows line endings
- Match existing naming and table layout style in touched files.
- Add comments only when logic is non-obvious.

## Where To Put Changes

- Add/modify prototype entities, events, custom inputs: `data.lua` and `data/`
- Add/modify runtime event handlers and gameplay logic: `control.lua` and
  `control/`
- Add shared helpers only when reused by multiple modules: `lib/`
- Add user-facing text: `locale/en/base.cfg`
- Bump release metadata: `info.json` and `changelog.txt`

## Safety Boundaries

- Avoid save-breaking changes unless explicitly requested.
- Avoid changing public names/IDs of prototypes and custom events unless the
  task requires migration-aware changes.

## Validation Checklist

Before finalizing a change:

1. Verify data-stage and runtime-stage require paths are correct.
2. Verify locale keys exist for any new user-facing strings.
3. Update `changelog.txt` and `info.json` version when preparing release
   changes.
4. Summarize any migration risk if entity names, event names, or stored state
   shapes change.

## Out Of Scope By Default

- Adding non-essential features not aligned with Die Shrink's minimal scope.
- Modifying the internal framework under `lib/core/` without explicit need.
- Large-scale renames of core entities, events, or storage keys.
