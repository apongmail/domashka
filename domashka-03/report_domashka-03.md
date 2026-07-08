# Домашка 03 — GitHub, Git-клієнт, форк репозиторія

**Автор:** Андрій Пономарьов / Claude Code
**Завдання:** створити акаунт на GitHub, публічний репозиторій, встановити
та налаштувати локальний git-клієнт, зробити форк репозиторія
[spring-projects/spring-petclinic](https://github.com/spring-projects/spring-petclinic).

---

## 1. Акаунт GitHub

Використано існуючий акаунт: **[apongmail](https://github.com/apongmail)**

## 2. Публічний репозиторій

Публічно доступний репозиторій з домашніми завданнями:

**https://github.com/apongmail/domashka**

## 3. Git-клієнт

Ноутбук на macOS, тому замість Git for Windows / TortoiseGit використовується
нативний git (Apple Git, поставляється з Xcode Command Line Tools) плюс
офіційний GitHub CLI (`gh`) для роботи з GitHub з термінала.

```
$ git --version
git version 2.50.1 (Apple Git-155)
```

## 4. Налаштування git-користувача

```
$ git config --global user.name
apongmail

$ git config --global user.email
142420807+apongmail@users.noreply.github.com
```

Повний вивід `git config --global --list` та `gh auth status` — у файлі
[docs/git-client-info.txt](docs/git-client-info.txt).
Скріншот термінала з версією і налаштуваннями — у
[docs/](docs/).

Автентифікація до GitHub налаштована через GitHub CLI
(`credential.helper = gh auth git-credential`), тобто git використовує
токен з keychain, без збереження пароля у відкритому вигляді.

## 5. Форк spring-petclinic

Форк створено командою:

```
$ gh repo fork spring-projects/spring-petclinic --clone=false
https://github.com/apongmail/spring-petclinic
```

**Посилання на форк: https://github.com/apongmail/spring-petclinic**

---

## Звіт (підсумок)

| Пункт | Посилання |
|---|---|
| Акаунт GitHub | https://github.com/apongmail |
| Публічний репозиторій | https://github.com/apongmail/domashka |
| Форк spring-petclinic | https://github.com/apongmail/spring-petclinic |
| Версія та налаштування git | [docs/git-client-info.txt](docs/git-client-info.txt) + скріншот у docs/ |
