журнал ручных действий

Открыть console.yandex.cloud, выбрать каталог default.
Compute Cloud  Виртуальные машины  «Создать виртуальную машину».
Общая информация: имя vetrov-09-web-manual.
«Добавить метку»: created-by = console.
Образ загрузочного диска: Ubuntu 24.04.
Зона доступности: ru-central1-d.
Диски: тип HDD, размер 25 ГБ.
Вычислительные ресурсы: вкладка «Своя конфигурация».
Платформа: Intel Ice Lake.
vCPU: 2, гарантированная доля: 20 %.
RAM: 2 ГБ.
Отметить «Прерываемая».
Сеть: подсеть default в ru-central1-d.
Публичный IP: «Автоматически».
Доступ: SSH-ключ, логин student.
«Добавить ключ»: вставить содержимое id_ed25519.pub.
Имя ключа заменить на vetrov-09-wsl.
Выключить «Резервное копирование».
Проверить стоимость в правой колонке.
«Создать ВМ», дождаться статуса Running.
Скопировать публичный IP.
ssh student@<IP>, ответить yes на отпечаток.
sudo apt update, sudo apt install -y nginx, systemctl status nginx.
Открыть http://<IP> — стартовая страница nginx.
set +H, заменить «Welcome to nginx!» на cloudlab on $(hostname).
Обновить страницу,  cloudlab on vetrov-09-web-manual.
exit.
