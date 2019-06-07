Два файла ресурсов:
1. passfile.hide - Файл хранит логины и пароли для удалённого хоста и ПО rollback
Формат файла: service;uer;hashpassword
Первая строка должна быть - service;uer;hashpassword
Пароль храниться в формате Hash.
Для того чтобы получить хэш пароля выполняем
"P@ssword1" | ConvertTo-SecureString -AsPlainText -Force
затем полученный hash добавляем в файл passfile.hide

2. Hosts.csv.hide - Файл с информацией по хостам
Формат файла: group;host;mac
Первая строка должна быть - group;host;mac