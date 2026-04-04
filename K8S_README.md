# Kubernetes Lab Guide (Task Manager)

Ниже пошаговый сценарий выполнения лабораторной:

1. развернуть Kubernetes;
2. задеплоить приложение из Docker-образов;
3. включить HPA (15% CPU);
4. подключить Prometheus + Grafana;
5. добавить job в CI для push образов в Yandex Container Registry.

> В проекте уже подготовлены манифесты в папке `k8s/`.

## 0) Подготовка образов в Yandex Container Registry

```bash
export YC_REGISTRY_ID=<REGISTRY_ID>
export IMAGE_TAG=v1

yc iam create-token | docker login --username iam --password-stdin cr.yandex

docker buildx build --platform linux/amd64 -t cr.yandex/$YC_REGISTRY_ID/taskmanager-server:$IMAGE_TAG ./server --push
docker buildx build --platform linux/amd64 -t cr.yandex/$YC_REGISTRY_ID/taskmanager-client:$IMAGE_TAG ./client --push
```

## 1) Развернуть Minikube (локально)

```bash
minikube start --driver=docker
minikube addons enable metrics-server
kubectl get nodes
```

`metrics-server` обязателен для HPA.

## 2) Подготовить Kubernetes-манифесты под ваши теги

В файлах:

- `k8s/server-deployment.yaml`
- `k8s/client-deployment.yaml`

заменить:

- `REPLACE_REGISTRY_ID` -> ваш `REGISTRY_ID`
- `REPLACE_TAG` -> ваш тег (например `v1`)

## 3) Создать pull-secret для приватного YCR

Сначала получить IAM токен:

```bash
export YC_IAM_TOKEN=$(yc iam create-token)
```

Создать secret в namespace `taskmanager`:

```bash
kubectl apply -f k8s/namespace.yaml

kubectl -n taskmanager create secret docker-registry ycr-pull-secret \
  --docker-server=cr.yandex \
  --docker-username=iam \
  --docker-password="$YC_IAM_TOKEN"
```

## 4) Деплой приложения в Kubernetes

```bash
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-pvc.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml

kubectl apply -f k8s/server-deployment.yaml
kubectl apply -f k8s/server-service.yaml
kubectl apply -f k8s/client-deployment.yaml
kubectl apply -f k8s/client-service.yaml
kubectl apply -f k8s/server-hpa.yaml
```

Проверка:

```bash
kubectl -n taskmanager get pods
kubectl -n taskmanager get svc
kubectl -n taskmanager get hpa
```

Доступ к клиенту:

```bash
minikube service client -n taskmanager --url
```

## 5) Проверить и продемонстрировать HPA (15% CPU)

Нагрузка на backend:

```bash
kubectl -n taskmanager run loadgen --rm -it --image=busybox:1.36 -- \
  sh -c 'while true; do wget -q -O- http://server:3001/api/tasks > /dev/null; done'
```

В другом терминале:

```bash
kubectl -n taskmanager get hpa -w
kubectl -n taskmanager get pods -l app=server -w
kubectl top pods -n taskmanager
```

Ожидаемо: при росте CPU у `server` HPA увеличивает количество pod'ов.

## 6) Prometheus + Grafana

Установка через Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
```

Подключить сбор метрик backend:

```bash
kubectl apply -f k8s/server-servicemonitor.yaml
```

Проверить:

```bash
kubectl -n monitoring get pods
kubectl -n taskmanager get servicemonitor
```

Открыть Grafana:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Логин:

- user: `admin`
- password:

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

Что смотреть в Grafana:

- CPU/Memory по pod'ам (`taskmanager` namespace)
- `http_server_requests_seconds_*` (метрики Spring)
- `jvm_*` метрики
- количество pod'ов backend во время нагрузки

Prometheus endpoint backend:

```text
/actuator/prometheus
```

## 7) CI job для push образов в YCR

В `.github/workflows/ci.yml` добавлен отдельный job `docker-publish`.

Нужно добавить Secrets в GitHub:

- `YC_REGISTRY_ID` — id реестра (без `cr.yandex/`)
- `YC_OAUTH_TOKEN` — OAuth токен для логина в `cr.yandex`

Job:

- логинится в `cr.yandex`
- собирает и пушит `server` и `client`
- теги: `latest` и `sha-<commit>`

## Что показать преподавателю

1. Kubernetes:
   - `kubectl get nodes`
   - `kubectl -n taskmanager get pods,svc,hpa`
   - приложение открывается через `minikube service client --url`
2. Масштабирование:
   - запущенный генератор нагрузки
   - `kubectl get hpa -w` и рост реплик `server`
3. Мониторинг:
   - Grafana dashboard с метриками pod'ов
   - метрики Spring/HTTP запросов через Prometheus
4. CI:
   - job `docker-publish` в GitHub Actions
   - образы в Yandex Container Registry

## Очистка ресурсов

```bash
kubectl delete namespace taskmanager
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring
minikube stop
```
