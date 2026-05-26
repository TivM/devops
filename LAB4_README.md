# Лабораторная работа №4 — DevSecOps, SonarQube, Argo CD, Telegram-бот

> Облако: **Yandex Cloud** (Managed Kubernetes + Container Registry).
> Репозиторий: GitHub (CI на GitHub Actions).

Сделанные задания:

1. ✓ Лучшие практики безопасности — см. [`SECURITY.md`](./SECURITY.md).
2. ✓ Статический анализ SonarCloud + Quality Gate в CI.
3. ✓ Coverage ≥ 80 % обязателен (JaCoCo + vitest v8) — без него CI падает.
4. ✓ CD через Argo CD (GitOps) — см. [`argocd/README.md`](./argocd/README.md).
5. ✓ Telegram-бот шлёт статусы всех jobs пайплайна — см. [`TELEGRAM_BOT.md`](./TELEGRAM_BOT.md).

---

## 0. Что появилось / поменялось в репозитории

```
NEW  SECURITY.md                                   # практики DevSecOps
NEW  TELEGRAM_BOT.md                               # как поднять бота и подключить
NEW  LAB4_README.md                                # этот файл
NEW  sonar-project.properties                      # конфиг для sonar-scanner

NEW  argocd/namespace.yaml
NEW  argocd/project.yaml
NEW  argocd/application-taskmanager.yaml
NEW  argocd/README.md

MOD  server/pom.xml                                # + JaCoCo + sonar-maven-plugin
MOD  client/package.json                           # + @vitest/coverage-v8, скрипт test:coverage
MOD  client/vite.config.js                         # + coverage config + thresholds
MOD  .github/workflows/ci.yml                      # + sonarcloud-scan, bump-image-tag, notify-telegram
```

---

## 1. Какие GitHub Secrets нужны

Идём в `Settings → Secrets and variables → Actions` и добавляем:

| Secret                  | Откуда взять                                                       |
|-------------------------|---------------------------------------------------------------------|
| `YC_OAUTH_TOKEN`        | <https://oauth.yandex.com/...> (как и в лаб. 3, push образов в YCR) |
| `YC_REGISTRY_ID`        | `yc container registry list` — id без префикса `cr.yandex/`         |
| `SONAR_TOKEN`           | SonarCloud → My Account → Security → Generate Token                 |
| `TELEGRAM_BOT_TOKEN`    | токен от @BotFather (см. `TELEGRAM_BOT.md`)                         |
| `TELEGRAM_CHAT_ID`      | chat_id вашего личного чата или группы                              |

| Variable               | Откуда взять                                      |
|------------------------|---------------------------------------------------|
| `SONAR_ORGANIZATION`   | ключ организации в SonarCloud (slug)              |
| `SONAR_PROJECT_KEY`    | ключ проекта в SonarCloud (например `TivM_devops`) |

---

## 2. Подключение SonarCloud (один раз)

1. Зайти на <https://sonarcloud.io>, авторизоваться через GitHub.
2. **+ → Analyze new project → выбрать репозиторий `devops`**.
3. В качестве способа анализа выбрать **With GitHub Actions**.
4. SonarCloud покажет:
   - `SONAR_TOKEN` — сразу добавить в GitHub Secrets;
   - `Organization Key` → variable `SONAR_ORGANIZATION`;
   - `Project Key`      → variable `SONAR_PROJECT_KEY`.
5. На вкладке **Administration → Analysis Method** *отключить*
   автоматическое сканирование Sonar (`Automatic Analysis: Off`),
   иначе он будет конфликтовать с CI.
6. **Quality Gate** → выбрать `Sonar way` или создать кастомный
   с условиями (примерные):
   - **Coverage on New Code** ≥ 80 %.
   - **New Bugs** = 0.
   - **New Vulnerabilities** = 0.
   - **New Security Hotspots Reviewed** = 100 %.
   - **New Code Smells** ≤ 5.
   - **New Duplicated Lines (%)** ≤ 3 %.

В CI флаг `-Dsonar.qualitygate.wait=true` форсирует ожидание
вердикта, и если Quality Gate **FAILED** — шаг и весь job падают.

> **Self-hosted альтернатива (если требуется именно своя инсталляция в YC):**
> поднять `sonarqube` через docker-compose на отдельной ВМ Yandex Cloud
> (`docker-compose.prod.yml` уже есть в репо, образ
> `sonarqube:community` + postgres), пробросить порт 9000, добавить
> в DNS-зону. В job `sonarcloud-scan` поменять `-Dsonar.host.url` и
> убрать `-Dsonar.organization`. Остальная логика идентична.

---

## 3. Что именно делает CI после изменений (порядок jobs)

```
            server-test         <- JaCoCo coverage
                |
            server-build
                |
            client-test         <- vitest --coverage
                |
            client-build
                |
       +----> sonarcloud-scan   <- Quality Gate >= 80% coverage, 0 bugs
       |        |
       |   docker-publish       <- push в Yandex Container Registry
       |        |
       |   bump-image-tag       <- commit нового sha-тега в k8s/*.yaml
       |        |
       +---> notify-telegram (if: always)  <- статус всех jobs в Telegram
```

CI падает (статус Workflow = failure), если:

- упал хотя бы один unit-тест (server или client);
- JaCoCo `check` не достиг порога **80 %** lines coverage;
- `vitest --coverage` не достиг порога **80 %** lines/statements/functions;
- SonarCloud Quality Gate `FAILED` (низкое покрытие, новые баги, vulnerabilities, и т.д.);
- упала сборка / публикация docker-образа.

---

## 4. Что именно делает CD (Argo CD)

1. После успешного `docker-publish` job `bump-image-tag`
   обновляет `k8s/server-deployment.yaml` и `k8s/client-deployment.yaml`,
   ставя свежий тег `sha-<commit>`.
2. Делается автоматический commit обратно в `main`
   (с `paths-ignore` в триггере — повторный CI не запускается).
3. Argo CD замечает изменение в Git (`auto-sync` каждые ~3 минуты,
   либо webhook), применяет манифесты в кластер `taskmanager`.
4. В Argo CD UI видно дерево ресурсов, History, Diff, кнопку Rollback.

Инструкции по установке Argo CD и подключению этого репозитория —
в `argocd/README.md`.

---

## 5. Сценарий демонстрации (примерно 15 минут)

### Этап 1. Безопасность (2–3 мин)

- Открыть `SECURITY.md`, проговорить:
  - shift-left, least privilege, secrets в GitHub Secrets;
  - что в проекте уже есть (probes, resources.limits, imagePullSecrets);
  - что добавлено сейчас (SonarCloud, Quality Gate, coverage 80 %).

### Этап 2. SonarCloud (4 мин)

1. Открыть <https://sonarcloud.io/project/overview?id=...> — показать проект.
2. Открыть `.github/workflows/ci.yml` — показать job `sonarcloud-scan`,
   ключевые флаги:
   - `-Dsonar.qualitygate.wait=true`;
   - `-Dsonar.coverage.jacoco.xmlReportPaths=...`;
   - `-Dsonar.javascript.lcov.reportPaths=...`.
3. Запустить демо-PR с заведомо «плохим» кодом
   (например, добавить метод с дублированием и без тестов).
4. Показать, что CI завершился `failure` именно на шаге
   `SonarCloud Scan` со ссылкой на отчёт.
5. Открыть отчёт SonarCloud — показать вкладки Issues / Coverage / Hotspots.

### Этап 3. Argo CD (4 мин)

1. `kubectl -n argocd get pods` — показать, что Argo CD поднят.
2. `argocd app list` / открыть UI на `https://localhost:8080`.
3. Показать `Application taskmanager`: Sync = `Synced`, Health = `Healthy`.
4. Кликнуть `App diff` — diff пустой (всё применено).
5. Сделать `git commit` с изменением (например, число реплик в `server-deployment.yaml`).
6. Дождаться auto-sync (или `argocd app sync taskmanager`) — увидеть
   разноцветный граф `OutOfSync → Progressing → Synced`.
7. Открыть `History & Rollback` — показать, что можно откатиться кнопкой.

### Этап 4. Telegram-уведомления (2 мин)

1. Открыть Telegram-чат с ботом.
2. Запустить PR / push в main.
3. Дождаться окончания пайплайна.
4. Показать пришедшее сообщение со списком всех jobs и статусом:
   `CI/CD PASSED` / `CI/CD FAILED` + ссылка на run.

### Этап 5. Резюме (1 мин)

- Что было: ручной деплой, CI без статанализа.
- Что стало: shift-left security, Quality Gate, GitOps-CD,
  моментальные уведомления в чат команды.

---

## 6. Локальная проверка перед push'ем

### Сервер

```bash
cd server
mvn -B verify
# JaCoCo отчёт: server/target/site/jacoco/index.html
# CI упадёт, если coverage < 80%
```

### Клиент

```bash
cd client
npm ci
npm run test:coverage
# HTML отчёт: client/coverage/index.html
# CI упадёт, если lines/statements/functions < 80%
```

### Sonar-скан локально (опционально)

```bash
docker run --rm -e SONAR_HOST_URL=https://sonarcloud.io \
  -e SONAR_TOKEN=<your-token> \
  -v $(pwd):/usr/src sonarsource/sonar-scanner-cli \
  -Dsonar.organization=<your-org> \
  -Dsonar.projectKey=<your-project>
```

---

## 7. Чек-лист сдачи

- [ ] В GitHub добавлены все 7 секретов.
- [ ] SonarCloud-проект создан, Quality Gate настроен (coverage ≥ 80 %).
- [ ] CI на main зелёный, в SonarCloud есть отчёт с покрытием.
- [ ] В Argo CD UI приложение Synced + Healthy.
- [ ] Любое изменение в main вызывает: CI → push образа в YCR → коммит
      нового тега в k8s/ → синк Argo CD → обновление подов.
- [ ] В Telegram приходит финальное сообщение со статусом пайплайна.
- [ ] Документы открываются и читаются: `SECURITY.md`, `argocd/README.md`,
      `TELEGRAM_BOT.md`, этот `LAB4_README.md`.
