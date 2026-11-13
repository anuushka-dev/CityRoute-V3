## What this changes

<!-- One or two sentences. Link the issue it closes, if there is one. -->

Closes #

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Performance improvement
- [ ] Refactor (no behaviour change)
- [ ] Documentation
- [ ] CI/CD or container change

## How it was verified

<!-- The commands you ran and what they printed. Evidence beats adjectives. -->

```bash
python -m ruff check .
python -m ruff format --check .
python -m pytest
```

- [ ] `ruff check` and `ruff format --check` are clean
- [ ] `python -m pytest` passes (626 tests)
- [ ] Multi-worker consistency tests run separately if the graph, matrix or routing services changed
- [ ] `cd frontend && npm run build` succeeds if the UI changed

## Checklist

- [ ] `CHANGELOG.md` updated for anything user-visible
- [ ] `README.md` endpoint table updated if an endpoint was added, changed or removed
- [ ] No secrets, tokens or local `.env` values committed
- [ ] Algorithm changes keep their unit tests, and any behavioural change is deliberate
