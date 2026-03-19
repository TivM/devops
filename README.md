# Task Manager — DevOps Lab

Этот репозиторий содержит full-stack приложение Task Manager и инфраструктурные файлы для выполнения лабораторной работы:

1. развернуть виртуальную машину в Yandex Cloud с помощью Terraform;
2. установить Docker на ВМ с помощью Ansible;
3. контейнеризировать сервер и клиент через Docker;
4. поднять приложение из 3 сервисов через Docker Compose;
5. сохранить образы в Yandex Container Registry;
6. запустить приложение на ВМ из облачного реестра.

## Что находится в проекте

```text
devops/
├── terraform/                # Конфигурация инфраструктуры в Yandex Cloud
├── ansible/                  # Установка Docker на ВМ
├── server/                   # Spring Boot REST API
├── client/                   # React/Vite frontend
├── docker-compose.yml        # Локальный запуск 3 сервисов
├── docker-compose.prod.yml   # Продовый запуск на ВМ из registry
└── .env.example              # Пример переменных для prod compose
```

## Архитектура решения

Приложение состоит из 3 сервисов:

1. `db` — PostgreSQL
2. `server` — Spring Boot REST API
3. `client` — React-приложение, которое раздается через Nginx

Схема работы:

- пользователь открывает `http://<vm_ip>`;
- запрос попадает в `client`;
- `client` отправляет запросы на `/api`;
- Nginx внутри `client` проксирует `/api` в контейнер `server`;
- `server` работает с `db` по внутренней Docker-сети.

## Серверное приложение

Стек: Java 21, Spring Boot 3, Spring Data JPA, PostgreSQL.

Основные endpoints:

| Method | URL            | Description      |
|--------|----------------|------------------|
| GET    | `/api/tasks`   | Получить задачи  |
| GET    | `/api/tasks/:id` | Получить задачу |
| POST   | `/api/tasks`   | Создать задачу   |
| PUT    | `/api/tasks/:id` | Изменить задачу |
| DELETE | `/api/tasks/:id` | Удалить задачу  |

## Клиентское приложение

Стек: React, Vite, Nginx.

Клиент собирается в статические файлы и отдается через Nginx.  
В `client/nginx.conf` настроено:

- SPA routing через `try_files`
- проксирование `/api` на `http://server:3001`

Это позволяет открывать фронтенд на `80` порту и обращаться к backend без отдельного CORS-настроя.

## Что делает каждый инфраструктурный файл

### Terraform

- `terraform/main.tf` — создает сеть, подсеть, security group и виртуальную машину.
- `terraform/variables.tf` — описывает переменные: токен, `cloud_id`, `folder_id`, путь к SSH-ключу, зону.
- `terraform/terraform.tfvars.example` — шаблон значений.
- `terraform/outputs.tf` — выводит IP ВМ и готовую SSH-команду.

### Ansible

- `ansible/inventory.yml.example` — шаблон inventory с IP виртуальной машины.
- `ansible/playbook.yml` — устанавливает Docker Engine и плагины `buildx` и `compose`.

### Docker

- `server/Dockerfile` — multi-stage сборка backend.
- `client/Dockerfile` — multi-stage сборка frontend.
- `docker-compose.yml` — локальный запуск `db + server + client`.
- `docker-compose.prod.yml` — запуск на ВМ из образов, хранящихся в Yandex Container Registry.

## Требования перед началом

На локальной машине должны быть установлены:

- `terraform`
- `yc`
- `ansible`
- `docker`
- `docker compose`

Проверка:

```bash
terraform version
yc version
ansible --version
docker --version
docker compose version
```

Также нужен SSH-ключ:

```bash
ls ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
```

Если ключей нет:

```bash
ssh-keygen -t rsa -b 4096 -C "devops-lab"
```

## Шаг 1. Подготовка Terraform

### Что мы делаем

На этом этапе мы подготавливаем значения переменных для Terraform, чтобы он мог подключиться к Yandex Cloud и создать ВМ.

### Команды

Из корня проекта:

```bash
cd "/Users/vladislavtrofimcenko/Documents/projects/IdeaProjects/devops"
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Нужно получить значения:

```bash
yc config get cloud-id
yc config get folder-id
yc iam create-token
```

После этого заполнить файл `terraform/terraform.tfvars`:

```tfvars
yandex_token     = "ваш_iam_токен"
yandex_cloud_id  = "ваш_cloud_id"
yandex_folder_id = "ваш_folder_id"
ssh_public_key_path = "~/.ssh/id_rsa.pub"
vm_name          = "devops-lab2-vm"
zone             = "ru-central1-a"
```

### Что важно понимать

- `yandex_token` нужен Terraform для вызова API Yandex Cloud.
- `cloud_id` и `folder_id` определяют, где создавать ресурсы.
- `ssh_public_key_path` нужен, чтобы потом зайти на ВМ по SSH без пароля.

## Шаг 2. Развертывание ВМ через Terraform

### Что мы делаем

Terraform прочитает `.tf` файлы и создаст:

- VPC network
- subnet
- security group
- виртуальную машину Ubuntu

### Команды

```bash
terraform -chdir=terraform init
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

На вопрос подтверждения нужно ответить:

```text
yes
```

### Что проверить после выполнения

Получить outputs:

```bash
terraform -chdir=terraform output
terraform -chdir=terraform output -raw vm_public_ip
terraform -chdir=terraform output -raw vm_ssh
```

Проверить SSH:

```bash
ssh ubuntu@<VM_PUBLIC_IP>
```

### Что делает `main.tf`

- `yandex_vpc_network` создает сеть
- `yandex_vpc_subnet` создает подсеть
- `yandex_vpc_security_group` открывает порты:
  - `22` для SSH
  - `80` для frontend
  - `3001` для backend
- `yandex_compute_instance` создает ВМ
- `data "yandex_compute_image"` подбирает актуальный образ Ubuntu 22.04 LTS

## Шаг 3. Установка Docker на ВМ через Ansible

### Что мы делаем

Ansible подключается к ВМ по SSH и автоматически настраивает Docker.

### Подготовка inventory

```bash
cp ansible/inventory.yml.example ansible/inventory.yml
```

Пример `ansible/inventory.yml`:

```yaml
all:
  children:
    vm:
      hosts:
        lab2:
          ansible_host: <VM_PUBLIC_IP>
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

### Проверка подключения

```bash
ansible vm -i ansible/inventory.yml -m ping
```

Ожидаемый результат:

```text
lab2 | SUCCESS => ...
```

### Установка Docker

```bash
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml
```

### Проверка на ВМ

```bash
ssh ubuntu@<VM_PUBLIC_IP> "docker --version && docker compose version"
```

### Что делает playbook

- обновляет `apt`
- добавляет GPG-ключ Docker
- подключает официальный Docker repository
- устанавливает:
  - `docker-ce`
  - `docker-ce-cli`
  - `containerd.io`
  - `docker-buildx-plugin`
  - `docker-compose-plugin`
- запускает и включает сервис Docker
- добавляет пользователя `ubuntu` в группу `docker`

## Шаг 4. Локальная проверка Docker Compose

### Что мы делаем

Перед публикацией в реестр полезно убедиться, что контейнеры локально вообще собираются и запускаются.

### Команды

```bash
docker compose build
docker compose up -d
docker compose ps
```

Проверки:

- frontend: `http://localhost`
- backend: `http://localhost:3001`
- список задач: `http://localhost:3001/api/tasks`

Логи:

```bash
docker compose logs db
docker compose logs server
docker compose logs client
```

Остановка:

```bash
docker compose down
```

### Подключение к базе через IntelliJ IDEA

Если используется локальный `docker-compose.yml`, у `db` опубликован порт:

```yaml
ports:
  - "5432:5432"
```

Параметры подключения из IDE:

- Host: `localhost`
- Port: `5432`
- Database: `taskmanager`
- User: `postgres`
- Password: `postgres`

## Шаг 5. Создание реестра Docker-образов в Yandex Cloud

### Что мы делаем

Создаем облачный registry, куда будут загружены готовые образы `server` и `client`.

### Команды

Создание реестра:

```bash
yc container registry create --name taskmanager-registry
```

Просмотр списка:

```bash
yc container registry list
```

Нужно запомнить `REGISTRY_ID`.

### Авторизация Docker в registry

Если используется IAM-токен:

```bash
yc iam create-token | docker login --username iam --password-stdin cr.yandex
```

Важно:

- здесь ничего не нужно подставлять вручную;
- команда сама берет токен из `yc iam create-token`;
- логин выполняется на той машине, где будет работать Docker.

Если ты логинишься на локальном Mac, это поможет локальному Docker.  
Если образы будет скачивать ВМ, то на ВМ тоже нужен отдельный `docker login`.

## Шаг 6. Сборка и публикация образов в Yandex Container Registry

### Важный момент про архитектуру

Если локальная машина — Mac на Apple Silicon, то обычный `docker build` может собрать образы под `arm64`.  
Yandex Cloud ВМ обычно работает на `amd64`, и тогда контейнеры упадут с ошибкой:

```text
exec format error
```

Поэтому для публикации в registry нужно собирать образы именно под `linux/amd64`.

### Подготовка buildx

```bash
docker buildx version
docker buildx create --use --name multiarch-builder
docker buildx inspect --bootstrap
```

### Задание переменных

Подставить свой `REGISTRY_ID`:

```bash
export YC_REGISTRY_ID=<REGISTRY_ID>
export IMAGE_TAG=v1
```

Важно: в `YC_REGISTRY_ID` нужно указывать только id, без `cr.yandex/`.

Правильно:

```bash
export YC_REGISTRY_ID=crp69j2m4uvnbtbseavv
```

Неправильно:

```bash
export YC_REGISTRY_ID=cr.yandex/crp69j2m4uvnbtbseavv
```

### Сборка и push

```bash
docker buildx build --platform linux/amd64 -t cr.yandex/$YC_REGISTRY_ID/taskmanager-server:$IMAGE_TAG ./server --push
docker buildx build --platform linux/amd64 -t cr.yandex/$YC_REGISTRY_ID/taskmanager-client:$IMAGE_TAG ./client --push
```

### Проверка

```bash
yc container image list --registry-id $YC_REGISTRY_ID
```

## Шаг 7. Запуск приложения на ВМ из Yandex Container Registry

### Что мы делаем

На ВМ будет запущен `docker-compose.prod.yml`, который скачивает `server` и `client` из `cr.yandex`, а `db` поднимает из публичного `postgres:16-alpine`.

### Скопировать compose-файл на ВМ

```bash
scp docker-compose.prod.yml ubuntu@<VM_PUBLIC_IP>:~
```

### Подключиться к ВМ

```bash
ssh ubuntu@<VM_PUBLIC_IP>
```

### Создать `.env` на ВМ

Подставить настоящий `REGISTRY_ID`:

```bash
cat > .env <<EOF
YC_REGISTRY_ID=<REGISTRY_ID>
IMAGE_TAG=v1
EOF
```

Проверка:

```bash
sed -n '1,5p' .env
```

Ожидаемый результат:

```env
YC_REGISTRY_ID=crp69j2m4uvnbtbseavv
IMAGE_TAG=v1
```

### Получить IAM-токен на локальной машине

На локальном Mac:

```bash
yc iam create-token
```

Скопировать токен.

### Выполнить `docker login` на ВМ

На ВМ:

```bash
docker login --username iam --password "<IAM_TOKEN>" cr.yandex
```

Этот шаг нужен, потому что Docker на ВМ должен получить доступ к приватным образам в registry.

### Запуск

```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps
```

## Шаг 8. Проверка работоспособности

### Проверка контейнеров

На ВМ:

```bash
docker compose -f docker-compose.prod.yml ps
```

Нужно увидеть:

- `db` — `Up (healthy)`
- `server` — `Up`
- `client` — `Up`

### Логи

```bash
docker compose -f docker-compose.prod.yml logs db
docker compose -f docker-compose.prod.yml logs server
docker compose -f docker-compose.prod.yml logs client
```

### Проверка backend на ВМ

```bash
curl http://localhost:3001/api/tasks
```

### Проверка frontend на ВМ

```bash
curl http://localhost
```

### Проверка из браузера

На локальной машине открыть:

```text
http://<VM_PUBLIC_IP>
```

Если все работает, откроется фронтенд, а запросы к `/api` будут проходить через Nginx в backend.

## Что делать при типовых ошибках

### `Image not found` в Terraform

Причина: устаревший `image_id`.  
Решение: использовать `data "yandex_compute_image"` с `family = "ubuntu-2204-lts"`.

### `Connection closed by ... port 22`

Причина: ВМ еще не успела до конца инициализироваться или есть проблема с ключом.  
Решение:

```bash
ssh -vvv -i ~/.ssh/id_rsa ubuntu@<VM_PUBLIC_IP>
```

### `EOF` при `terraform init` или `docker pull`

Причина: сетевые проблемы, VPN, proxy или ограничения сети.  
Решение:

- проверить интернет;
- временно отключить proxy;
- попробовать другую сеть;
- повторить команду.

### `exec format error`

Причина: образы собраны в `arm64`, а ВМ работает на `amd64`.  
Решение: пересобрать через `docker buildx build --platform linux/amd64 --push`.

### `Registry cr.yandex not found`

Причина: в `YC_REGISTRY_ID` ошибочно добавлен префикс `cr.yandex/`.  
Решение: использовать только id реестра.

### `unauthorized` при `docker login`

Причина: перепутан тип токена.  
Решение:

- если токен получен через `yc iam create-token`, то использовать `--username iam`;
- если используется OAuth-токен, тогда `--username oauth`.

## Что показать преподавателю

### 1. Terraform

Показать:

- содержимое `terraform/main.tf`
- команду:

```bash
terraform -chdir=terraform plan
terraform -chdir=terraform apply
terraform -chdir=terraform output
```

- публичный IP ВМ

### 2. Ansible

Показать:

- `ansible/inventory.yml`
- `ansible/playbook.yml`
- запуск:

```bash
ansible vm -i ansible/inventory.yml -m ping
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml
```

- проверку:

```bash
ssh ubuntu@<VM_PUBLIC_IP> "docker --version && docker compose version"
```

### 3. Docker

Показать:

- `server/Dockerfile`
- `client/Dockerfile`
- `docker-compose.yml`
- что в compose минимум 3 сервиса: `db`, `server`, `client`

### 4. Registry

Показать:

```bash
yc container registry list
yc container image list --registry-id <REGISTRY_ID>
```

### 5. Продовый запуск

Показать:

- `docker-compose.prod.yml`
- `.env` на ВМ
- логин в registry
- запуск:

```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps
```

### 6. Работоспособность приложения

Показать:

- `http://<VM_PUBLIC_IP>` в браузере
- `curl http://localhost:3001/api/tasks` на ВМ
- при необходимости логи:

```bash
docker compose -f docker-compose.prod.yml logs server
docker compose -f docker-compose.prod.yml logs client
```

## Итог

В рамках лабораторной работы реализован полный DevOps-сценарий:

1. инфраструктура описана как код через Terraform;
2. настройка ВМ автоматизирована через Ansible;
3. сервер и клиент упакованы в Docker-образы;
4. приложение запускается через Docker Compose из 3 сервисов;
5. образы публикуются в Yandex Container Registry;
6. приложение разворачивается на виртуальной машине в облаке.
