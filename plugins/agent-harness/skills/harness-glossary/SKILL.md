---
name: harness-glossary
description: Add, sharpen or check domain terms in GLOSSARY.md (or a per-context glossary via GLOSSARY-MAP.md) and keep code, tests, tickets and specs using the same words. Use when a new domain concept appears, two words are used for one thing, or a reviewer flags vocabulary.
---

# Harness Glossary

One concept, one word, everywhere: code, tests, tickets, specs, commit messages. The glossary is where that word is decided.

If another installed skill also manages domain terms, it must write to the same `GLOSSARY.md` (see `AGENTS.md` → Skills and plugins).

## Which glossary

- `GLOSSARY-MAP.md` at the root → read it and use the glossary for the context you are working in.
- Otherwise `GLOSSARY.md` at the root. Create it from the harness template if missing.

## Add or change a term

1. Find the concept in code (`grep -rn`) and in tickets/specs. List the words currently used for it, with counts.
2. Ask the developer which word wins and what it means in one sentence. **Never write a definition from code alone** — code shows usage, not meaning.
3. Add the row: Term · Meaning · Avoid (the losing synonyms) · Code name.
4. If choosing the word was a real trade-off (e.g. it differs from the client's vocabulary), add an ADR and index row.

## Check usage (on a diff or the whole repo)

1. Collect the "Avoid" words from the glossary.
2. `git diff` (or the given scope) → list every Avoid word that appears in new identifiers, test names, strings shown to users, and docs.
3. List new nouns in new identifiers that are not in the glossary — candidates, not errors.

Output:

```
Glossary: <file>
Avoided terms used: - "<word>" @ file:line → use "<term>"
New concepts (not in glossary): - "<word>" @ file:line
```

Renaming existing code to match the glossary is a separate, explicit change — propose it, do not do it as a side effect.
