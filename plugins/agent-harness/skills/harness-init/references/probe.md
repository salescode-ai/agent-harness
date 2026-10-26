# Before/After Probe

Run the same prompt before building the harness and after. The difference is what the harness bought you. Keep results in the conversation only.

```text
You are working in this repository. Pick a small but real improvement — a bug, a missing test,
a doc gap. Do not change anything. Report:
1. What was in your context when you started (auto-loaded files)
2. Which files you would read first, in order, and why
3. Which rules or constraints apply, and where you found them (or that you found none)
4. The change you would make
5. The exact commands that would prove it works
6. What you had to assume because the repo did not say
7. Whether you would proceed alone or stop for a human, and why
```

| Signal | No harness | Working harness |
|---|---|---|
| First read | Random source files | `AGENTS.md`, then the module `AGENTS.md` |
| Constraints | None found | Quotes `INVARIANTS.md` |
| Proof | "Run the tests" | `make check`, `make test T=…` |
| Assumptions | Many, silent | Few, stated |
| Escalation | Proceeds | Names the Authorization trigger |
