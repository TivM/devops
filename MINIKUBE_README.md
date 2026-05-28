# Minikube + Argo CD guide

Эта инструкция поднимает весь контур локально в minikube:

```text
GitHub Actions -> YCR images -> Git commit with sha tag -> Argo CD -> minikube
```

Приложение и Argo CD UI открываются через Ingress:

```text
http://taskmanager.test
https://argocd.test
```

## 1. Проверить инструменты

```bash
minikube version
kubectl version --client
helm version
```

Argo CD CLI нужен только для удобной проверки:

```bash
brew install argocd
argocd version --client
```

Если CLI не установлен, всё равно можно пользоваться Argo CD через UI.

## 2. Быстрый запуск без port-forward

В репозитории есть скрипт, который поднимает minikube, включает Ingress,
ставит Argo CD, применяет Application и прописывает локальные домены:

```bash
bash scripts/minikube-up.sh
```

После завершения открывай:

```text
http://taskmanager.test
https://argocd.test
```

На macOS с Docker driver скрипт запускает `minikube tunnel` в фоне. Это не
`kubectl port-forward`: tunnel нужен minikube для доступа к Ingress на
`127.0.0.1:80/443`.

## 3. Запустить minikube вручную

```bash
minikube start --driver=docker
minikube addons enable metrics-server
minikube addons enable ingress
kubectl get nodes
```

Дождаться ingress controller:

```bash
kubectl -n ingress-nginx get pods -w
```

Все pod'ы должны стать `Running`.

## 4. Настроить локальный URL приложения

Ingress использует host'ы `taskmanager.test` и `argocd.test`.
Добавь их в `/etc/hosts`:

```bash
echo "$(minikube ip) taskmanager.test argocd.test" | sudo tee -a /etc/hosts
```

Проверка:

```bash
ping taskmanager.test
ping argocd.test
```

Если minikube был пересоздан через `minikube delete`, IP мог поменяться.
Тогда удали старую строку из `/etc/hosts` и добавь новую.

На macOS с Docker driver прямой доступ к `minikube ip` обычно недоступен.
В этом случае в `/etc/hosts` лучше прописать `127.0.0.1`, а tunnel запустить
один раз как системный процесс:

```bash
echo "127.0.0.1 taskmanager.test argocd.test" | sudo tee -a /etc/hosts
```

В отдельном терминале:

```bash
minikube tunnel
```

Это не port-forward приложения, а сетевой tunnel minikube для доступа к
Ingress/LoadBalancer-адресам.

## 5. Создать pull-secret для Yandex Container Registry

Манифесты используют приватные образы из YCR, поэтому minikube должен уметь
их скачивать.

```bash
kubectl apply -f k8s/namespace.yaml

export YC_IAM_TOKEN="$(yc iam create-token)"

kubectl -n taskmanager create secret docker-registry ycr-pull-secret \
  --docker-server=cr.yandex \
  --docker-username=iam \
  --docker-password="$YC_IAM_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Проверка:

```bash
kubectl -n taskmanager get secret ycr-pull-secret
```

## 6. Установить Argo CD в minikube

```bash
kubectl apply -f argocd/namespace.yaml
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd get pods -w
```

Дождись, пока pod'ы Argo CD станут `Running`.

## 7. Открыть Argo CD UI

Применить Ingress для Argo CD:

```bash
kubectl apply -f argocd/argocd-ingress.yaml
```

Открыть:

```text
https://argocd.test
```

Браузер покажет предупреждение о self-signed certificate. Для локального
minikube это ожидаемо.

Логин:

```text
admin
```

Пароль:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d ; echo
```

Опционально залогиниться CLI:

```bash
argocd login argocd.test --username admin --password <password> --insecure --grpc-web
```

Fallback, если Ingress для UI недоступен:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

И открыть `https://localhost:8080`.

## 8. Подключить приложение к Argo CD

В репозитории уже есть:

- `argocd/project.yaml` — ограниченный Argo CD project;
- `argocd/application-taskmanager.yaml` — Application, который читает `k8s/`
  из `https://github.com/TivM/devops.git`.

Применить:

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application-taskmanager.yaml
```

Проверить:

```bash
kubectl -n argocd get applications
```

Если установлен Argo CD CLI:

```bash
argocd app get taskmanager
argocd app sync taskmanager
```

В UI приложение `taskmanager` должно стать:

```text
Sync Status: Synced
Health Status: Healthy
```

## 9. Проверить приложение

Проверить ресурсы:

```bash
kubectl -n taskmanager get pods
kubectl -n taskmanager get deploy,svc,ingress
```

Открыть приложение:

```text
http://taskmanager.test
```

Проверить backend через nginx proxy клиента:

```bash
curl http://taskmanager.test/api/tasks
```

Fallback без Ingress:

```bash
minikube service client -n taskmanager --url
```

## 10. Проверить CD-автоматизацию

1. Сделать изменение в коде или манифестах.
2. Запушить в `main`.
3. Дождаться GitHub Actions:
   - `server-test`;
   - `client-test`;
   - `sonarcloud-scan`;
   - `docker-publish`;
   - `bump-image-tag`.
4. Job `bump-image-tag` обновит image tag в:
   - `k8s/server-deployment.yaml`;
   - `k8s/client-deployment.yaml`.
5. Argo CD увидит новый commit и применит изменения в minikube.

Проверка image tag в кластере:

```bash
kubectl -n taskmanager get deploy server \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

kubectl -n taskmanager get deploy client \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

Тег должен быть `sha-<commit>`.

## 11. Опционально включить HPA

В основном Argo CD деплое HPA не включён, чтобы количество pod'ов не росло
само и приложение оставалось в 1 реплике. Для демонстрации автоскейлинга из
лабораторной 3 можно включить его вручную:

```bash
kubectl apply -f k8s/server-hpa.yaml
```

Выключить HPA и вернуть backend в 1 pod:

```bash
kubectl -n taskmanager delete hpa server-hpa --ignore-not-found=true
kubectl -n taskmanager scale deployment server --replicas=1
```

## 12. Опционально включить ServiceMonitor

`server-servicemonitor.yaml` не входит в основной Argo CD sync, потому что
ресурс `ServiceMonitor` существует только после установки Prometheus Operator.
Если мониторинг уже поднят из лабораторной 3, применить его можно отдельно:

```bash
kubectl apply -f k8s/server-servicemonitor.yaml
```

## 13. Диагностика

Если pod'ы не стартуют:

```bash
kubectl -n taskmanager get pods
kubectl -n taskmanager describe pod <pod-name>
kubectl -n taskmanager logs <pod-name>
```

Если видишь `ImagePullBackOff`, проверь `ycr-pull-secret` и доступ к YCR.

Если `taskmanager.test` не открывается:

```bash
kubectl -n ingress-nginx get pods
kubectl -n taskmanager get ingress
minikube ip
grep -E 'taskmanager.test|argocd.test' /etc/hosts
```

На macOS с Docker driver попробуй:

```bash
minikube tunnel
```

## 14. Остановка

```bash
bash scripts/minikube-down.sh
```

Или вручную:

```bash
minikube stop
```

Полная очистка:

```bash
kubectl delete -f argocd/application-taskmanager.yaml --ignore-not-found=true
kubectl delete -f argocd/project.yaml --ignore-not-found=true
kubectl delete namespace taskmanager --ignore-not-found=true
kubectl delete namespace argocd --ignore-not-found=true
minikube delete
```
