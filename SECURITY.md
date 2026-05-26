# SECURITY — Лучшие практики DevSecOps для проекта Task Manager

Документ описывает применённые и рекомендуемые практики безопасности
для приложения (Spring Boot + React) и его инфраструктуры (Yandex Cloud,
Kubernetes, GitHub Actions, Argo CD). Используется как чек-лист для
лабораторной работы №4 и как ориентир для дальнейшей работы.

---

## 1. Принципы (shift-left security)

1. **Security as Code** — все правила безопасности (пайплайн, политики
   Kubernetes, IaC) хранятся в Git и проходят code review.
2. **Shift Left** — уязвимости ловим как можно раньше: ещё в pull request,
   а не на проде. Для этого включены статический анализ (SonarCloud),
   тесты и проверка покрытия в CI.
3. **Least Privilege** — каждый сервис/токен имеет минимально нужный
   набор прав (отдельные сервис-аккаунты Yandex Cloud, RBAC в K8s,
   `imagePullSecrets` отдельно от deploy-токенов).
4. **Defense in Depth** — защита на нескольких уровнях: сеть (security
   groups), runtime (limits, probes), приложение (валидация input),
   секреты (GitHub Secrets / Yandex Lockbox).
5. **Immutable Infrastructure** — образы пересобираются и тегируются
   по SHA коммита; никакого ручного `kubectl edit` на проде.

---

## 2. Безопасность кода и зависимостей

### 2.1 Что уже сделано в проекте

- Статический анализ через **SonarCloud** (job `sonarcloud-scan`
  в `.github/workflows/ci.yml`).
- Quality Gate: CI **падает**, если:
  - покрытие тестами ниже **80 %**;
  - найдены **bugs / vulnerabilities / security hotspots**;
  - есть **code smells** выше порога;
  - не проходят unit-тесты сервера или клиента.
- Покрытие считается **JaCoCo** (Java) и `@vitest/coverage-v8`
  (React) — отчёты грузятся в SonarCloud в формате `jacoco.xml` и `lcov`.

### 2.2 Рекомендации сверх лабораторной

- **Dependabot / Renovate** — автоматическое обновление зависимостей
  с уязвимостями. Включается в `.github/dependabot.yml`.
- **SCA**: дополнительно к Sonar — `Trivy fs` или `Snyk` в CI
  для отдельной проверки CVE в `pom.xml` и `package-lock.json`.
- **Secret scanning**: `gitleaks` как pre-commit hook + GitHub native
  secret scanning (включается в Settings → Code security).
- **Pre-commit hooks** для linters (`eslint`, `spotless`, `checkstyle`).

---

## 3. Безопасность контейнеров

### 3.1 Образы

- Базовые образы — **официальные**, с фиксированной версией
  (`eclipse-temurin:21-jre-alpine`, `node:20-alpine` и т.п.) — никаких
  `latest`.
- Сканирование образов рекомендую добавить отдельным job:
  `aquasecurity/trivy-action` → fail on `HIGH,CRITICAL`.
- Multi-stage build — финальный образ не содержит maven/npm и исходников.

### 3.2 Runtime

В `k8s/server-deployment.yaml` и `k8s/client-deployment.yaml`:

- `resources.requests` и `resources.limits` — защита от noisy neighbour
  и DoS из-за утечки памяти.
- `readinessProbe`, `livenessProbe`, `startupProbe` — не пускаем трафик
  в неготовый pod, перезапускаем зависшие.
- Рекомендую добавить блок `securityContext`:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

- `imagePullSecrets: ycr-pull-secret` — отдельный IAM-токен только
  для pull из приватного Yandex Container Registry.

---

## 4. Безопасность Kubernetes

- **Namespace isolation**: всё приложение живёт в namespace
  `taskmanager` (см. `k8s/namespace.yaml`).
- **Secrets**: пароли БД в `k8s/postgres-secret.yaml` (в реальном
  проде стоит вынести в Yandex Lockbox через
  `external-secrets-operator`).
- **NetworkPolicy** (рекомендую добавить): запретить трафик
  между namespace по умолчанию, разрешать только `client → server`
  и `server → postgres`.
- **RBAC**: сервис-аккаунт Argo CD получает права только на namespace
  `taskmanager`, а не cluster-admin.

---

## 5. Безопасность CI/CD

- **GitHub Secrets** для всех чувствительных данных:
  `YC_OAUTH_TOKEN`, `YC_REGISTRY_ID`, `SONAR_TOKEN`,
  `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.
- `permissions: contents: read` в workflow по умолчанию — минимально
  возможные права `GITHUB_TOKEN`.
- Защищённые ветки: push в `main` только через PR + обязательные
  status checks (CI, Sonar Quality Gate).
- Argo CD авторизуется в кластере отдельным сервис-аккаунтом
  Yandex Cloud (Kubernetes Editor только на нужный namespace).
- Telegram-бот шлёт уведомления о каждом успешном/упавшем job
  (job `notify` в CI workflow), чтобы команда быстро реагировала.

---

## 6. Безопасность инфраструктуры (Yandex Cloud)

- VPC + Security Group (см. `terraform/main.tf`). В проде стоит
  закрыть SSH (22) до конкретных IP, а не `0.0.0.0/0`.
- Доступ к Managed Kubernetes через сервис-аккаунт с ролью
  `k8s.cluster-api.cluster-admin` только для CD-агента.
- Логи и аудит — `yc logging` + `audit-trails`.
- Container Registry — приватный, доступ по IAM-токену.

---

## 7. Чек-лист на каждый PR

- [ ] Прошёл CI (server-test, client-test, build).
- [ ] Прошёл SonarCloud Quality Gate (coverage ≥ 80 %, 0 bugs / vulnerabilities).
- [ ] Нет новых TODO / FIXME в security-критичных местах.
- [ ] Нет хардкод-секретов (проверить `git diff`).
- [ ] Образ собирается и публикуется в YCR с тегом `sha-<commit>`.
- [ ] Argo CD автоматически синхронизировал изменения после merge.
- [ ] В Telegram пришло финальное уведомление о пайплайне.

---

## 8. Ссылки

- OWASP Top 10 — <https://owasp.org/Top10/>
- CIS Kubernetes Benchmark — <https://www.cisecurity.org/benchmark/kubernetes>
- SonarCloud Quality Gates — <https://docs.sonarsource.com/sonarcloud/improving/quality-gates/>
- Argo CD Best Practices — <https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/>
