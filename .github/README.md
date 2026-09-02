# GitHub

CI, issue forms, and pull-request template for mac-cleanup.

- Workflow: [workflows/ci.yml](workflows/ci.yml) — package tests, workspace build, gitleaks. `permissions: contents: read`. Actions are pinned by commit SHA.
- Do not put secrets, tokens, or license keys in workflow files. Personal-account gitleaks-action does not need `GITLEAKS_LICENSE`.
- Issue forms refuse dumps, ChatStorage, `enc-key`, `apply-report.json`, and filename screenshots.
