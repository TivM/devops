# Лабораторная #3 — команды для демонстрации на сдаче

Ниже готовый сценарий показа: что запускать и в каком порядке.

## 0) Подготовка (1 раз перед сдачей)

Проверить, что Minikube и kubectl работают:

```bash
minikube status
kubectl get nodes
kubectl top nodes
```

Если кластер остановлен:

```bash
minikube start --driver=docker
minikube addons enable metrics-server
```

---

## 1) Показать, что приложение развернуто в Kubernetes

```bash
kubectl -n taskmanager get pods
kubectl -n taskmanager get svc
```

Что озвучить:
- есть 3 сервиса: `client`, `server`, `postgres`
- pod'ы запущены

Открыть приложение локально:

```bash
minikube service client -n taskmanager --url
```

Открыть выданный URL в браузере.

---

## 2) Показать HPA (15% CPU) и автоскейл backend

### 2.1 Включить HPA

```bash
kubectl apply -f k8s/server-hpa.yaml
kubectl -n taskmanager get hpa
```

Проверка: target должен быть `.../15%`.

### 2.2 Запустить нагрузку (Терминал №1)

```bash
kubectl -n taskmanager run loadgen --rm -it --image=busybox:1.36 -- \
  sh -c 'while true; do wget -q -O- http://server:3001/api/tasks > /dev/null; done'
```

### 2.3 Следить за масштабированием (Терминал №2)

```bash
kubectl -n taskmanager get hpa -w
```

### 2.4 Следить за pod'ами backend (Терминал №3)

```bash
kubectl -n taskmanager get pods -l app=server -w
```

Что показать:
- в HPA `REPLICAS` растет (`1 -> 2 -> 3`)
- появляются новые pod `server-*`

### 2.5 Зафиксировать результат

```bash
kubectl -n taskmanager get hpa
kubectl -n taskmanager get pods -l app=server
kubectl top pods -n taskmanager
```

---

## 3) Показать мониторинг Prometheus + Grafana

Проверить, что мониторинг поднят:

```bash
kubectl -n monitoring get pods
kubectl -n taskmanager get servicemonitor
```

Открыть Grafana:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

В браузере открыть:

```text
http://localhost:3000
```

Логин:
- user: `admin`
- password:

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

В Grafana -> Explore -> datasource `Prometheus` выполнить запросы:

```promql
up{namespace="taskmanager"}
```

```promql
sum(rate(http_server_requests_seconds_count{namespace="taskmanager"}[1m]))
```

```promql
sum(rate(container_cpu_usage_seconds_total{namespace="taskmanager",pod=~"server-.*"}[1m]))
```

```promql
kube_pod_container_status_ready{namespace="taskmanager",pod=~"server-.*"}
```

Что показать:
- метрики pod'ов есть
- HTTP запросы к backend видны
- при нагрузке растут CPU и request rate

---

## 4) Показать CI job публикации Docker-образов в YCR

Локально проверить, что образы есть в реестре:

```bash
yc container registry list
yc container image list --registry-id <REGISTRY_ID>
```

В GitHub Actions показать:
- job `Docker - Publish to YCR` в workflow `CI Pipeline`
- успешный статус job

Что озвучить:
- в workflow используются secrets `YC_REGISTRY_ID` и `YC_OAUTH_TOKEN`
- образы `taskmanager-server` и `taskmanager-client` пушатся в `cr.yandex`

---

## 5) После демонстрации (остановить нагрузку и снизить ресурсы)

Остановить loadgen:

```bash
kubectl -n taskmanager delete pod loadgen --ignore-not-found=true
```

Вернуть backend к 1 реплике:

```bash
kubectl -n taskmanager scale deployment server --replicas=1
```

Опционально отключить HPA:

```bash
kubectl -n taskmanager delete hpa server-hpa --ignore-not-found=true
```

Если уходишь надолго:

```bash
minikube stop
```

---

## Быстрый запуск портов (без ручного ввода)

Можно поднять доступ к приложению и Grafana одной командой:

```bash
bash scripts/start-port-forwards.sh
```

Откроются:
- приложение: `http://localhost:8080`
- Grafana: `http://localhost:3000`

Остановить:

```bash
bash scripts/stop-port-forwards.sh
```
