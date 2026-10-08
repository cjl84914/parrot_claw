# GitHub Contributing Guide

> Welcome to the ParrotClaw project! This page walks through contributing via [GitHub](https://github.com/cjl84914/parrot_claw).

## Workflow

### 1. Fork the project

On the [GitHub project page](https://github.com/cjl84914/parrot_claw), click the Fork button in the top-right corner to fork the repository to your GitHub account.

### 2. Clone it locally

```bash
git clone https://github.com/<your-username>/parrot_claw.git
cd parrot_claw
```

### 3. Add the upstream remote

```bash
git remote add upstream https://github.com/cjl84914/parrot_claw.git
```

### 4. Create a feature branch

```bash
git checkout -b feat/your-feature-name
```

### 5. Make your changes and commit

```bash
git add .
git commit -m "feat: add xxx feature"
```

Commit messages are expected to follow the [Conventional Commits](https://www.conventionalcommits.org/) convention:

| Type     | Meaning             |
| -------- | ---------------- |
| `feat`   | New feature           |
| `fix`    | Bug fix         |
| `docs`   | Documentation update         |
| `refactor` | Refactor           |
| `chore`  | Build / tooling related  |

### 6. Push to your repository

```bash
git push origin feat/your-feature-name
```

### 7. Open a pull request

On GitHub, open your fork, switch to your branch, and click "Contribute" → "Open pull request", targeting the `main` branch of `cjl84914/parrot_claw`. Describe your changes and submit.

## Notes

- **Discuss in an issue first** — for larger changes, open an issue to agree on the direction before writing code
- **Keep each PR focused** — one PR solves one problem; do not mix unrelated changes
- **Sync with upstream** — pull the latest upstream code before opening a PR:

```bash
git fetch upstream
git rebase upstream/main
```

- **Test** — make sure the code compiles and `flutter analyze` reports no errors
