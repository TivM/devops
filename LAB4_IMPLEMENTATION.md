# Lab 4 Implementation Notes

Документ объясняет, что именно реализовано в проекте для лабораторной работы
по DevSecOps, SonarCloud, Argo CD, minikube и Telegram-уведомлениям.

## 1. Общая схема

В проекте реализован такой процесс:

```text
Developer push / pull request
        |
        v
GitHub Actions CI
        |
        +--> backend tests + JaCoCo coverage
        +--> frontend tests + Vitest coverage
        +--> SonarCloud static analysis + Quality Gate
        |
        v
Docker image build and push to Yandex Container Registry
        |
        v
GitOps commit with new image tags in k8s manifests
        |
        v
Argo CD watches GitHub repository
        |
        v
Argo CD syncs minikube Kubernetes cluster
        |
        v
Application is available through Ingress
```

Главная идея: кластер не обновляется вручную через `kubectl apply` после
каждого релиза. Источником истины является Git. Argo CD смотрит на каталог
`k8s/` в репозитории и приводит кластер к состоянию, описанному в Git.

## 2. Backend: тесты, покрытие и Sonar

Backend находится в каталоге:

```text
server/
```

Основные файлы:

| Файл | Назначение |
|------|------------|
| `server/pom.xml` | Maven-конфигурация backend-приложения |
| `server/src/main/java/...` | Spring Boot REST API |
| `server/src/test/java/...` | Unit/integration tests |
| `server/Dockerfile` | Сборка Docker-образа backend |

В `server/pom.xml` реализовано:

- подключение Spring Boot;
- подключение тестов через `spring-boot-starter-test`;
- подключение JaCoCo;
- генерация JaCoCo-отчёта на фазе `verify`;
- проверка покрытия строк не ниже 80%;
- настройка путей для Sonar.

Ключевой фрагмент логики:

```text
mvn verify
```

делает сразу несколько вещей:

- запускает тесты;
- собирает отчёт покрытия;
- проверяет coverage threshold;
- падает, если покрытие ниже 80%.

HTML-отчёт backend coverage появляется здесь:

```text
server/target/site/jacoco/index.html
```

XML-отчёт для SonarCloud:

```text
server/target/site/jacoco/jacoco.xml
```

## 3. Frontend: тесты и покрытие

Frontend находится в каталоге:

```text
client/
```

Основные файлы:

| Файл | Назначение |
|------|------------|
| `client/package.json` | npm scripts и зависимости |
| `client/vite.config.js` | Vite/Vitest/coverage config |
| `client/src/components/` | React-компоненты |
| `client/src/__tests__/` | Frontend-тесты |
| `client/Dockerfile` | Сборка Docker-образа frontend |
| `client/nginx.conf` | nginx config для production-контейнера |

В `client/package.json` добавлены команды:

```json
"test": "vitest run --reporter=verbose",
"test:coverage": "vitest run --coverage"
```

В `client/vite.config.js` настроено:

- тестовое окружение `jsdom`;
- coverage provider `v8`;
- отчёты `text`, `lcov`, `html`;
- директория отчётов `client/coverage`;
- пороги покрытия:
  - lines: 80;
  - statements: 80;
  - functions: 80;
  - branches: 70.

Команда проверки:

```bash
cd client
npm run test:coverage
```

HTML-отчёт frontend coverage:

```text
client/coverage/index.html
```

LCOV-отчёт для SonarCloud:

```text
client/coverage/lcov.info
```

## 4. SonarCloud

Файл конфигурации:

```text
sonar-project.properties
```

В нём описано:

- где находятся backend и frontend sources;
- где находятся tests;
- какие файлы исключить из анализа;
- где лежит JaCoCo XML report;
- где лежит frontend LCOV report;
- где лежат JUnit reports.

Ключевые параметры:

```properties
sonar.sources=server/src/main/java,client/src
sonar.tests=server/src/test/java,client/src/__tests__
sonar.coverage.jacoco.xmlReportPaths=server/target/site/jacoco/jacoco.xml
sonar.javascript.lcov.reportPaths=client/coverage/lcov.info
sonar.junit.reportPaths=server/target/surefire-reports
```

Организация и project key не захардкожены в файле. Они передаются в CI через
GitHub repository variables/secrets:

```text
SONAR_ORGANIZATION
SONAR_PROJECT_KEY
SONAR_TOKEN
```

## 5. GitHub Actions CI/CD

Основной workflow:

```text
.github/workflows/ci.yml
```

Workflow запускается на:

- push в `main`;
- pull request в `main`.

### Jobs

| Job | Что делает |
|-----|------------|
| `server-test` | Запускает backend-тесты и JaCoCo coverage |
| `server-build` | Собирает backend jar |
| `client-test` | Запускает frontend-тесты и coverage |
| `client-build` | Собирает frontend |
| `sonarcloud-scan` | Запускает SonarCloud scan и ждёт Quality Gate |
| `docker-publish` | Собирает и публикует Docker-образы в YCR |
| `bump-image-tag` | Обновляет image tags в Kubernetes manifests |
| `notify-telegram` | Отправляет итоговый статус pipeline в Telegram |

### Почему CI падает при проблемах

CI завершается с ошибкой, если:

- backend-тесты не прошли;
- frontend-тесты не прошли;
- JaCoCo coverage ниже 80%;
- Vitest coverage ниже настроенных thresholds;
- SonarCloud Quality Gate не пройден;
- Docker image не собрался или не запушился;
- не удалось обновить GitOps manifests.

### SonarCloud Quality Gate

В job `sonarcloud-scan` используется:

```text
-Dsonar.qualitygate.wait=true
-Dsonar.qualitygate.timeout=600
```

Это важно: GitHub Actions не просто отправляет данные в SonarCloud, а ждёт
результат Quality Gate. Если Quality Gate failed, job падает.

### Docker publish

Job `docker-publish` публикует два образа в Yandex Container Registry:

```text
taskmanager-server
taskmanager-client
```

Теги:

```text
v1
sha-<github-sha>
```

Пример:

```text
cr.yandex/<registry-id>/taskmanager-server:sha-...
cr.yandex/<registry-id>/taskmanager-client:sha-...
```

### GitOps bump image tag

Job `bump-image-tag` меняет image tags в файлах:

```text
k8s/server-deployment.yaml
k8s/client-deployment.yaml
```

После этого job делает commit обратно в репозиторий:

```text
ci(gitops): bump images to sha-<github-sha> [skip ci]
```

`[skip ci]` и `paths-ignore` нужны, чтобы не получить бесконечный цикл CI,
когда workflow сам коммитит изменение image tag.

## 6. Kubernetes manifests

Основной каталог Kubernetes-манифестов:

```text
k8s/
```

Главный файл для Argo CD:

```text
k8s/kustomization.yaml
```

Он перечисляет ресурсы, которые Argo CD применяет в кластер:

- namespace;
- PostgreSQL secret;
- PostgreSQL StatefulSet/service;
- backend deployment/service;
- frontend deployment/service;
- Ingress.

### Backend deployment

Файл:

```text
k8s/server-deployment.yaml
```

Что реализовано:

- deployment `server`;
- image из Yandex Container Registry;
- `imagePullSecrets` для приватного YCR;
- переменные подключения к PostgreSQL;
- resource requests/limits;
- readiness/liveness/startup probes;
- Prometheus annotations.

Проверки здоровья:

```text
/actuator/health
/actuator/health/readiness
/actuator/health/liveness
```

### Frontend deployment

Файл:

```text
k8s/client-deployment.yaml
```

Что реализовано:

- deployment `client`;
- image из Yandex Container Registry;
- `imagePullSecrets`;
- container port 80;
- resource requests/limits;
- readiness/liveness probes.

### PostgreSQL

Файлы:

```text
k8s/postgres-secret.yaml
k8s/postgres-service.yaml
k8s/postgres-statefulset.yaml
```

Что реализовано:

- отдельный PostgreSQL pod, созданный через StatefulSet;
- стабильное имя pod'а `postgres-0`;
- persistent volume claim через `volumeClaimTemplates`;
- secret с `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`;
- service `postgres`;
- backend подключается к PostgreSQL по DNS-имени `postgres`.

### Ingress

Файл:

```text
k8s/ingress.yaml
```

Ingress публикует frontend:

```text
http://taskmanager.test
```

Правило:

```text
host taskmanager.test -> service client:80
```

Backend доступен через nginx proxy frontend-контейнера по пути:

```text
http://taskmanager.test/api/tasks
```

## 7. Argo CD

Каталог:

```text
argocd/
```

Файлы:

| Файл | Назначение |
|------|------------|
| `argocd/namespace.yaml` | Namespace `argocd` |
| `argocd/project.yaml` | Ограниченный Argo CD AppProject |
| `argocd/application-taskmanager.yaml` | Argo CD Application для Task Manager |
| `argocd/argocd-ingress.yaml` | Ingress для Argo CD UI |

### AppProject

Файл:

```text
argocd/project.yaml
```

В нём ограничено:

- из каких GitHub repositories можно брать manifests;
- в какие namespaces можно деплоить;
- какие Kubernetes resources разрешены.

Разрешённые namespace resources включают:

- `Deployment`;
- `Service`;
- `Secret`;
- `ConfigMap`;
- `PersistentVolumeClaim`;
- `Ingress`;
- `HorizontalPodAutoscaler`;
- `ServiceMonitor`.

### Application

Файл:

```text
argocd/application-taskmanager.yaml
```

Ключевые настройки:

```yaml
source:
  repoURL: https://github.com/TivM/devops.git
  targetRevision: main
  path: k8s

destination:
  server: https://kubernetes.default.svc
  namespace: taskmanager
```

То есть Argo CD берёт manifests из GitHub repository, ветка `main`, каталог
`k8s/`, и применяет их в namespace `taskmanager`.

Автоматическая синхронизация:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

Что это значит:

- `prune: true` удаляет ресурсы, которые убрали из Git;
- `selfHeal: true` откатывает ручные изменения в кластере обратно к Git;
- Argo CD автоматически применяет новые commits.

### Argo CD UI Ingress

Файл:

```text
argocd/argocd-ingress.yaml
```

UI доступен по адресу:

```text
https://argocd.test
```

Для локального minikube self-signed certificate warning в браузере нормален.

## 8. Minikube automation

Для локального запуска добавлены скрипты:

```text
scripts/minikube-up.sh
scripts/minikube-down.sh
```

### minikube-up.sh

Скрипт делает:

- запускает minikube;
- включает `metrics-server`;
- включает `ingress`;
- ждёт `ingress-nginx-controller`;
- прописывает локальные hostnames;
- создаёт `ycr-pull-secret`, если доступен `YC_IAM_TOKEN` или `yc`;
- устанавливает Argo CD;
- применяет Argo CD project/application;
- применяет Ingress для Argo CD UI;
- на macOS Docker driver запускает `minikube tunnel` в фоне.

Локальные адреса:

```text
http://taskmanager.test
https://argocd.test
```

На macOS с Docker driver в `/etc/hosts` используется:

```text
127.0.0.1 taskmanager.test argocd.test
```

Поэтому должен работать `minikube tunnel`, иначе будет:

```text
ERR_CONNECTION_REFUSED
```

### minikube-down.sh

Скрипт:

- останавливает фоновый `minikube tunnel`, если он запускался через
  `minikube-up.sh`;
- останавливает minikube profile.

## 9. Telegram notifications

Документация:

```text
TELEGRAM_BOT.md
```

Реализация находится в job:

```text
notify-telegram
```

в файле:

```text
.github/workflows/ci.yml
```

Job запускается с:

```yaml
if: always()
```

Это значит, что уведомление отправляется даже если один из предыдущих jobs
упал.

Telegram secrets:

```text
TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID
```

Что отправляет бот:

- общий статус pipeline: passed/failed/cancelled;
- repository;
- branch;
- commit;
- event type;
- список jobs и их статусы;
- ссылку на GitHub Actions run.

## 10. Security practices

Основной документ:

```text
SECURITY.md
```

В проекте применены следующие практики:

- secrets не хранятся в коде;
- GitHub Secrets используются для токенов;
- Docker images публикуются в registry;
- Kubernetes `Secret` используется для PostgreSQL credentials;
- `imagePullSecrets` используется для приватного YCR;
- настроены readiness/liveness/startup probes;
- настроены resource requests/limits;
- CI включает SAST через SonarCloud;
- Quality Gate блокирует небезопасный или некачественный код;
- покрытие тестами контролируется автоматически.

## 11. Что именно показывать преподавателю в коде

### Покрытие backend

Файл:

```text
server/pom.xml
```

Показать:

- `jacoco-maven-plugin`;
- `goal report`;
- `goal check`;
- minimum `0.80`.

### Покрытие frontend

Файл:

```text
client/vite.config.js
```

Показать:

- `coverage.provider = v8`;
- reporters `text`, `lcov`, `html`;
- thresholds `80`.

### SonarCloud

Файлы:

```text
sonar-project.properties
.github/workflows/ci.yml
```

Показать:

- sources/tests paths;
- JaCoCo report path;
- LCOV report path;
- `sonarcloud-scan`;
- `-Dsonar.qualitygate.wait=true`.

### CI/CD pipeline

Файл:

```text
.github/workflows/ci.yml
```

Показать:

- jobs order;
- `needs`;
- `docker-publish`;
- `bump-image-tag`;
- `notify-telegram`.

### Argo CD

Файлы:

```text
argocd/project.yaml
argocd/application-taskmanager.yaml
argocd/argocd-ingress.yaml
```

Показать:

- `repoURL`;
- `targetRevision: main`;
- `path: k8s`;
- `automated.prune`;
- `automated.selfHeal`;
- Ingress `argocd.test`.

### Kubernetes app manifests

Каталог:

```text
k8s/
```

Показать:

- `kustomization.yaml`;
- `server-deployment.yaml`;
- `client-deployment.yaml`;
- `postgres-statefulset.yaml`;
- `ingress.yaml`;
- `imagePullSecrets`;
- probes;
- resources;
- Ingress host `taskmanager.test`.

### Minikube local access

Файлы:

```text
scripts/minikube-up.sh
scripts/minikube-down.sh
MINIKUBE_README.md
```

Показать:

- `minikube addons enable ingress`;
- `minikube addons enable metrics-server`;
- `/etc/hosts`;
- `minikube tunnel`;
- URLs `taskmanager.test` and `argocd.test`.

## 12. Итоговая формулировка

Можно сказать так:

```text
В коде реализован полный DevSecOps/GitOps-контур. Тесты backend и frontend
запускаются автоматически, покрытие контролируется на уровне 80%, результаты
передаются в SonarCloud, а Quality Gate блокирует дальнейшие stages при
проблемах качества или безопасности. После успешного CI Docker-образы
публикуются в Yandex Container Registry, pipeline обновляет image tags в
Kubernetes manifests, а Argo CD автоматически синхронизирует minikube-кластер
с Git. Приложение и Argo CD UI доступны через Ingress без ручного
kubectl port-forward. Telegram bot отправляет итоговый статус pipeline.
```
