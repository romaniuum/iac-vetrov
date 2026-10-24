# ДЗ 2. Стенд в манифесте Terraform

Ветров Р. А., вариант 09. Тот же стенд, что в ДЗ 1, но описан манифестом,
без сервера приложения и NAT-шлюза:

- сеть `vetrov-09-hw2-net`, подсети `10.19.1.0/24` (ru-central1-d) и `10.19.2.0/24` (ru-central1-e);
- веб-серверы `vetrov-09-hw2-web-N` (Debian 12, nginx на порту 8027), чередуются по зонам;
- целевая группа со всеми веб-серверами и сетевой балансировщик: принимает на 80, отдаёт на 8027.

Страница отвечает строкой `cloudlab on vetrov-09-hw2-web-N`.

| Файл | Что в нём |
|---|---|
| `versions.tf` | версия Terraform и провайдера, пустой блок `provider` |
| `main.tf` | весь стенд |
| `outputs.tf` | адрес балансировщика и адреса машин |
| `cloud-init.tpl.yaml` | настройка машины при первой загрузке (nginx, порт, страница) |
| `.terraform.lock.hcl` | зафиксированная версия провайдера, коммитится |

## Что нужно

- Terraform 1.6+ и `~/.terraformrc` с зеркалом `https://terraform-mirror.yandexcloud.net/`
  (реестр HashiCorp из России недоступен);
- `yc` с профилем, где заданы облако и каталог;
- ключ сервисного аккаунта с ролью `editor` на каталог.

## Поднять

Доступ к облаку идёт через переменные окружения, в файлах его нет.
Переменные живут до конца сеанса терминала: в новом окне их задают заново.

```bash
export YC_SERVICE_ACCOUNT_KEY_FILE=$HOME/.yc-keys/vetrov-09-key.json
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID=$(yc config get folder-id)
export YC_ZONE=ru-central1-d

cd hw-02
terraform init
terraform plan      # посмотреть, что создастся
terraform apply
```

Через 1–2 минуты после `apply` (nginx ставится при первой загрузке):

```bash
LB=$(terraform output -raw lb_url)
for i in $(seq 1 40); do curl -s "$LB/"; done | sort | uniq -c
```

Строк должно быть столько, сколько машин.

## Снести

```bash
terraform destroy
```

Удаляется только то, что есть в состоянии (`terraform.tfstate` в этом каталоге).
Созданное руками Terraform не видит: после `destroy` стоит проверить
`yc compute instance list` и `yc vpc address list`.

## Что менять

- **Число машин** — `count` в `resource "yandex_compute_instance" "web"`. Целевая группа
  подстроится сама. При уменьшении удаляются машины с конца (последний номер).
- **Свой вариант** — значения записаны прямо в `main.tf`: префикс `vetrov-09` в именах,
  зоны, диапазоны подсетей, порт (в `templatefile`, в `target_port` и в `healthcheck`),
  слово `cloudlab`, семейство образа `debian-12`.
- **Ключ SSH** — строка `SSH_KEY` в `main.tf`, вывод `cat ~/.ssh/id_ed25519.pub`.
  Вход: `ssh student@<адрес из terraform output web_public_ips>`.

Правка `cloud-init.tpl.yaml` на поднятом стенде сама не применяется: шаблон срабатывает
только при первой загрузке, а провайдер не показывает разницу в `user-data`. Машину
пересоздают явно: `terraform apply -replace='yandex_compute_instance.web[0]'`.

## Если страница не открылась

| Что видно | Что смотреть |
|---|---|
| `curl` висит или отказ | прошло меньше 2 минут после `apply`; подождать |
| цели UNHEALTHY | `yc load-balancer network-load-balancer target-states vetrov-09-hw2-lb --target-group-id $(yc load-balancer target-group get vetrov-09-hw2-tg --format json \| jq -r .id)`; на машине `sudo systemctl status nginx`, `sudo cloud-init status --long` |
| отвечает одна машина | вторая ещё ставит nginx; если все HEALTHY — это норма, балансировщик делит по соединениям, а не по кругу |
| таймаут снаружи при живом стенде в зоне ru-central1-a | плохой публичный адрес: `terraform apply -replace='yandex_compute_instance.web[1]'` |
| `apply`: нет прав или ключа | переменные `YC_*` не заданы в этом окне терминала |
| `Quota ... exceeded` | остались ресурсы прошлых работ, удалить через `yc` |
| машины пропали | они прерываемые, облако останавливает их не позже чем через сутки; `terraform apply` поднимет заново |

## Пайплайн

`.gitlab-ci.yml` в корне репозитория: `terraform-fmt` (формат всех `*.tf`) и
`terraform-validate` (разбор `hw-02`). В облако пайплайн ничего не применяет.
