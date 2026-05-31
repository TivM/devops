# Lab 4 Demo Guide

Краткий сценарий защиты лабораторной работы:

- DevSecOps best practices;
- тесты и покрытие 80%;
- SonarCloud Quality Gate в CI;
- CD через Argo CD в minikube;
- Telegram-уведомления о pipeline.

## 0. Перед демонстрацией

Перейти в корень проекта:

```bash
cd /Users/vladislavtrofimcenko/Documents/projects/IdeaProjects/devops
```

Проверить последний коммит:

```bash
git status
git log -1 --oneline
```

Если есть локальный коммит, который должен увидеть Argo CD, его нужно
запушить:

```bash
git push
```

Если появляется ошибка:

```text
Could not resolve host: github.com
```

значит проблема в интернете, DNS или VPN. Argo CD не увидит локальный коммит,
пока он не попадёт в GitHub.

## 1. Показать тесты и покрытие

### Backend

Запустить тесты backend с JaCoCo:

```bash
cd server
mvn -B verify
```

Что показать в выводе:

- тесты прошли успешно;
- Maven build завершился `BUILD SUCCESS`;
- JaCoCo проверяет покрытие;
- если покрытие ниже 80%, сборка падает.

Открыть HTML-отчёт покрытия:

```bash
open target/site/jacoco/index.html
```

Что показать в браузере:

- overall coverage;
- coverage по классам;
- что покрытие не ниже требуемого порога.

### Frontend

Запустить тесты frontend с coverage:

```bash
cd ../client
npm ci
npm run test:coverage
```

Что показать в выводе:

- тесты Vitest прошли;
- coverage рассчитан;
- thresholds настроены на 80%.

Открыть HTML-отчёт:

```bash
open coverage/index.html
```

Вернуться в корень проекта:

```bash
cd ..
```

## 2. Показать CI и SonarCloud

Открыть workflow:

```bash
sed -n '1,280p' .github/workflows/ci.yml
```

Что показать в файле:

- job `server-test`;
- job `client-test`;
- job `sonarcloud-scan`;
- параметр `-Dsonar.qualitygate.wait=true`;
- `docker-publish`;
- `bump-image-tag`;
- Telegram notification job.

Быстро найти Sonar-настройки:

```bash
rg -n "sonar|qualitygate|coverage" .github/workflows/ci.yml sonar-project.properties
```

Что сказать:

```text
CI падает, если:
- backend/frontend тесты не прошли;
- покрытие ниже 80%;
- SonarCloud Quality Gate failed;
- найдены критичные bugs/vulnerabilities/security issues;
- не собрались или не опубликовались Docker-образы.
```

Что показать в браузере:

- GitHub Actions run;
- job `SonarCloud Scan (Quality Gate)`;
- SonarCloud project overview;
- вкладки Coverage, Issues, Security Hotspots, Quality Gate.

## 3. Запустить minikube и Ingress

Проверить состояние minikube:

```bash
minikube status -p minikube
kubectl get nodes
```

Если кластер ещё не поднят:

```bash
bash scripts/minikube-up.sh
```

На macOS с Docker driver обязательно открыть отдельный терминал и запустить:

```bash
sudo minikube tunnel -p minikube
```

Этот терминал не закрывать во время демонстрации.

Пояснение:

```text
minikube tunnel не является kubectl port-forward.
Он нужен minikube на macOS Docker driver, чтобы Ingress был доступен через
127.0.0.1:80/443.
```

Проверить, что ingress-nginx работает:

```bash
kubectl -n ingress-nginx get pods,svc
```

Ожидаемо:

```text
ingress-nginx-controller   1/1   Running
```

Проверить Ingress приложения:

```bash
kubectl -n taskmanager get ingress
```

Ожидаемо:

```text
taskmanager   nginx   taskmanager.test
```

## 4. Показать приложение

Открыть в браузере:

```text
http://taskmanager.test
```

Проверить backend через Ingress:

```bash
curl http://taskmanager.test/api/tasks
```

Показать Kubernetes-ресурсы приложения:

```bash
kubectl -n taskmanager get deploy,svc,ingress,pods
```

Ожидаемо:

```text
client      1/1
server      1/1
postgres    1/1
pods        Running
ingress     taskmanager.test
```

Если `taskmanager.test` не открывается:

```bash
grep -E 'taskmanager.test|argocd.test' /etc/hosts
lsof -nP -iTCP:80 -sTCP:LISTEN
kubectl -n ingress-nginx get pods
kubectl -n taskmanager get ingress
```

Частая причина:

```text
127.0.0.1:80 никто не слушает -> не запущен sudo minikube tunnel -p minikube.
```

Временная проверка без Ingress:

```bash
minikube service client -n taskmanager --url
```

## 5. Показать Argo CD

Открыть UI:

```text
https://argocd.test
```

Логин:

```text
admin
```

Пароль:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Проверить Argo CD из терминала:

```bash
kubectl -n argocd get pods
kubectl -n argocd get applications
kubectl -n argocd get application taskmanager
```

Ожидаемо:

```text
taskmanager   Synced   Healthy
```

Подробный статус:

```bash
kubectl -n argocd get application taskmanager \
  -o jsonpath='{.status.sync.status}{"\n"}{.status.health.status}{"\n"}{.status.sync.revision}{"\n"}'
```

Что показать в UI Argo CD:

- приложение `taskmanager`;
- `Sync Status: Synced`;
- `Health Status: Healthy`;
- дерево ресурсов;
- `Deployment/client`;
- `Deployment/server`;
- `StatefulSet/postgres`;
- `Service/client`;
- `Ingress/taskmanager`;
- `History and Rollback`;
- кнопку `Sync`.

Что сказать:

```text
Argo CD следит за Git-репозиторием и приводит состояние кластера к тому,
что описано в k8s-манифестах. Это GitOps-подход.
```

## 6. Показать работу CD

Вариант для полноценной демонстрации:

1. Сделать небольшое изменение в Git.
2. Запушить его в `main`.
3. Показать, что Argo CD увидел новый revision.
4. Показать переход `OutOfSync -> Progressing -> Synced`.

Команды:

```bash
git status
git log -1 --oneline
git push
```

Проверить revision, который видит Argo CD:

```bash
kubectl -n argocd get application taskmanager \
  -o jsonpath='{.status.sync.revision}{"\n"}'
```

Если установлен Argo CD CLI:

```bash
argocd app get taskmanager --grpc-web --insecure
argocd app sync taskmanager --grpc-web --insecure
```

Если CLI нет, в UI нажать:

```text
Refresh
Sync
```

Что показать:

- новый commit/revision;
- состояние `Synced`;
- pod'ы приложения в `Running`;
- приложение открывается по `http://taskmanager.test`.

## 7. Показать Telegram-уведомления

Открыть инструкцию:

```bash
sed -n '1,220p' TELEGRAM_BOT.md
```

Найти Telegram job в CI:

```bash
rg -n "telegram|TELEGRAM|notify" .github/workflows/ci.yml
```

Что показать в GitHub:

- repository secrets:
  - `TELEGRAM_BOT_TOKEN`;
  - `TELEGRAM_CHAT_ID`;
- workflow job/step уведомления;
- сообщение в Telegram после запуска pipeline.

Что сказать:

```text
Telegram bot получает итоговый статус pipeline и отправляет сообщение в чат.
Уведомление запускается даже при падении pipeline, потому что используется
if: always().
```

## 8. Короткий сценарий на 5 минут

Если времени мало, показать только это:

```bash
mvn -f server/pom.xml -B verify
```

```bash
cd client && npm run test:coverage && cd ..
```

```bash
kubectl -n argocd get applications
```

```bash
kubectl -n taskmanager get deploy,svc,ingress,pods
```

Открыть:

```text
https://argocd.test
http://taskmanager.test
```

Показать в Argo CD:

```text
taskmanager
Sync Status: Synced
Health Status: Healthy
History and Rollback
resource tree
```

## 9. Что говорить в конце

Короткое резюме:

```text
В лабораторной настроен DevSecOps pipeline. Backend и frontend проходят
автоматические тесты с обязательным покрытием 80%. SonarCloud выполняет
статический анализ и Quality Gate, поэтому CI падает при проблемах качества
или безопасности. После успешного CI/CD образы публикуются, Kubernetes
манифесты обновляются в Git, а Argo CD автоматически синхронизирует minikube
кластер по GitOps-модели. Telegram bot отправляет итоговый статус pipeline.
```
