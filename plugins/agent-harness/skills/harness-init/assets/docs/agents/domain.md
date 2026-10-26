# Domain docs

How agents and skills use this repo's domain documentation.

## Before exploring, read

- `GLOSSARY.md` (or `GLOSSARY-MAP.md`, which points to one `GLOSSARY.md` per context)
- `docs/DECISIONS.md`, then the ADRs in `docs/adr/` that touch the area you are working in

If a file does not exist yet, carry on; it is created when the first term or decision is settled.

## Rules

- Use glossary terms in names, tests, tickets and specs. Do not drift to the synonyms in its "Avoid" column.
- A needed concept missing from the glossary is a signal: flag it for the team rather than inventing a word.
- If your work contradicts an accepted ADR, say so explicitly ("contradicts ADR-0007 because …").
- When you add or change an ADR, update its row in `docs/DECISIONS.md` in the same change.
