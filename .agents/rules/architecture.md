# Architecture & Code Organization Guidelines

Follow a modular, responsibility-based architecture throughout this Roblox project.

Before creating, editing, splitting, merging, or renaming scripts, inspect the existing architecture and identify the authoritative runtime implementation.

## Core Rules

1. **Single Responsibility**: Each module must own one cohesive system or clearly defined responsibility.
2. **Avoid Monoliths**: Avoid giant scripts that combine unrelated gameplay, economy, UI, animation, audio, and effects.
3. **Avoid Micro-Fragmentations**: Avoid unnecessary micro-modules containing only trivial functions that belong together.
4. **Cohesion & Independence**: Keep closely related logic together and separate systems that change, run, or require testing independently.
5. **Clear Interfaces & Ownership**: Define clear interfaces, dependencies, and ownership of shared state.
6. **Server Authority**: Keep server-authoritative logic on the server. Never move economy validation, bid acceptance, damage decisions, or survival outcomes to an untrusted client.
7. **Eliminate Competing Truths**: Avoid duplicate implementations, circular dependencies, unnecessary abstractions, and multiple competing sources of truth.
8. **Contract & Mapping Preservation**: Preserve existing Rojo mappings, remote-event contracts, instance references, and public module interfaces unless a deliberate migration is required.
9. **Incremental & Documented Refactoring**: Before a refactor, document the files and runtime systems affected. Make incremental changes rather than rewriting the whole project.
10. **Runtime Verification**: After each change, run relevant tests, inspect Studio Output, and verify actual runtime behavior.

Do not split files merely to meet a line-count target. Refactor when it improves cohesion, testability, readability, or the ability to change one system without breaking another.

Optimize the architecture for maintainability by both human developers and AI coding agents, not for minimizing or maximizing the number of files.
