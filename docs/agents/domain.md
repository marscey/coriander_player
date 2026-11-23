# Domain Docs

**Layout:** Single-context

## Context file

- `CONTEXT.md` at the repo root — the project's domain language and ubiquitous vocabulary

## Architecture Decision Records

- `docs/adr/` at the repo root — numbered ADRs following the Nygard format

## Consumer rules

Skills that read domain docs should:

1. Read `CONTEXT.md` first to understand the project's domain language
2. Check `docs/adr/` for past architectural decisions that may constrain the current task
3. If `CONTEXT.md` doesn't exist, infer domain language from `CLAUDE.md` and existing code

## Creating CONTEXT.md

If `CONTEXT.md` doesn't exist yet, it should be created with:

- **Domain name** and brief description
- **Key entities** and their relationships (e.g., Audio, Playlist, Artist, Album)
- **Glossary** of domain-specific terms used in the codebase
- **Bounded contexts** if applicable (for this project: playback, library, cloud, metadata, lyrics)

## Creating ADRs

ADRs in `docs/adr/` should follow the format:

- `NNNN-short-title.md` (e.g., `0001-player-engine-abstraction.md`)
- Status: Proposed / Accepted / Deprecated / Superseded
- Context, Decision, Consequences
