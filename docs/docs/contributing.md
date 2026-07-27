# 贡献指南

> 欢迎参与 ParrotClaw 项目！项目托管在 [Gitee](https://gitee.com/alexcai/parrot_claw)。

---

## 贡献流程

### 1. Fork 项目

在 [项目主页](https://gitee.com/alexcai/parrot_claw) 点击右上角的 Fork 按钮，将仓库 fork 到你的 Gitee 账号下。

### 2. 克隆到本地

```bash
git clone https://gitee.com/<你的用户名>/parrot_claw.git
cd parrot_claw
```

### 3. 添加上游仓库

```bash
git remote add upstream https://gitee.com/alexcai/parrot_claw.git
```

### 4. 创建功能分支

```bash
git checkout -b feat/your-feature-name
```

### 5. 修改代码并提交

```bash
git add .
git commit -m "feat: 添加 xxx 功能"
```

提交信息建议遵循 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

| 类型     | 说明             |
| -------- | ---------------- |
| `feat`   | 新功能           |
| `fix`    | 修复 Bug         |
| `docs`   | 文档更新         |
| `refactor` | 重构           |
| `chore`  | 构建/工具链相关  |

### 6. 推送到你的仓库

```bash
git push origin feat/your-feature-name
```

### 7. 发起 Pull Request

在 Gitee 上进入你的 fork 仓库，点击"Pull Request" → "新建 Pull Request"，选择你的分支，目标分支为 `alexcai/parrot_claw` 的 `main` 分支。填写变更说明后提交。

---

## 注意事项

- **先开 Issue 讨论** — 大的功能变更建议先提 Issue 讨论方向，避免做无用功
- **保持单次 PR 专注** — 一个 PR 解决一个问题，不要混在一起
- **同步上游** — 提交 PR 前先拉取上游最新代码：

```bash
git fetch upstream
git rebase upstream/main
```

- **测试** — 确保代码编译通过，运行 `flutter analyze` 无错误
