# Telegram-бот для уведомлений CI/CD

Этот документ — пошаговая инструкция: как создать Telegram-бота,
получить токен и chat_id, как подключить их к GitHub Actions и
проверить, что бот реально пишет в чат статус пайплайна.

Сама интеграция в CI уже сделана — см. job `notify-telegram`
в файле `.github/workflows/ci.yml`. Job запускается **всегда**
(success / failure / cancelled) и шлёт агрегированный отчёт по
всем jobs пайплайна (server-test, sonarcloud-scan, docker-publish и т.д.).

---

## 1. Создать бота через @BotFather

1. Открыть в Telegram бота [@BotFather](https://t.me/BotFather).
2. Команда `/newbot`.
3. Указать имя (отображаемое) и username (должен заканчиваться на `bot`,
   например `taskmanager_ci_bot`).
4. BotFather пришлёт **токен** вида:

   ```
   1234567890:AAH...verylongstring...XYZ
   ```

   Это значение пойдёт в GitHub Secret `TELEGRAM_BOT_TOKEN`.

---

## 2. Узнать chat_id

### Вариант 1: личные уведомления (бот пишет лично вам)

1. Открыть своего нового бота в Telegram, нажать **Start**.
2. Открыть в браузере:

   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```

3. В JSON-ответе найти `"chat":{"id": 123456789, ...}` — это и есть
   ваш chat_id. Будет положительным числом.

### Вариант 2: групповой чат (бот пишет в общий чат команды)

1. Создать группу в Telegram, добавить бота в неё.
2. Дать боту права отправлять сообщения (BotFather → /mybots → выбрать
   бота → Bot Settings → Group Privacy → **Turn Off**, иначе он не
   увидит сообщения и getUpdates вернёт пусто).
3. Написать в группу любое сообщение, например `/start@taskmanager_ci_bot`.
4. Открыть `https://api.telegram.org/bot<TOKEN>/getUpdates`,
   взять `chat.id` (для групп это **отрицательное** число, например `-987654321`).

---

## 3. Добавить секреты в GitHub

В репозитории: `Settings → Secrets and variables → Actions → New repository secret`.

| Имя секрета            | Значение                            |
|------------------------|--------------------------------------|
| `TELEGRAM_BOT_TOKEN`   | токен от BotFather                  |
| `TELEGRAM_CHAT_ID`     | chat_id (личный или группы)         |

---

## 4. Проверка

1. Сделать любой commit + push в `main`.
2. Открыть `Actions → CI Pipeline → последний run`.
3. После завершения пайплайна (даже если что-то упало) в чат
   придёт сообщение типа:

   ```
   CI/CD PASSED
   Repo: vlad/devops
   Branch: main
   Commit: a1b2c3d by vlad
   Event: push

   Jobs:
   OK    server-test (success)
   OK    server-build (success)
   OK    client-test (success)
   OK    client-build (success)
   OK    sonarcloud-scan (success)
   SKIP  docker-publish (skipped)
   SKIP  bump-image-tag (skipped)

   Open run
   ```

Если что-то падает — будет пометка `FAIL` напротив упавшего job и
заголовок `CI/CD FAILED`.

---

## 5. Тонкости и устранение проблем

- Если бот не пишет в группу — Group Privacy в BotFather **должен быть Off**.
- Если `getUpdates` пустой — напишите боту любое сообщение и обновите URL.
- Если шаг `Send Telegram message` в Actions пропускается — проверьте,
  что добавлены **оба** секрета (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`):
  шаг выполняется только при их наличии.
- Telegram-боты Markdown 1.0 не поддерживают много символов. Если хочется
  более продвинутого форматирования — поменять `parse_mode=Markdown` на
  `MarkdownV2` и экранировать `_`, `*`, `[`, `]`, `(`, `)`, `~`, `>`, `#`,
  `+`, `-`, `=`, `|`, `{`, `}`, `.`, `!`.

---

## 6. (Опционально) Сделать «настоящего» бота с командами

Если хочется не только односторонних уведомлений, но и интерактива
(например, `/status` — узнать статус последнего деплоя), можно поднять
небольшой Spring Boot-компонент или отдельный сервис, который держит
long polling Telegram API и опрашивает GitHub Actions REST API.

В рамках лабораторной достаточно односторонних уведомлений из CI.
