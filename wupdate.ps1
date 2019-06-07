#-NoLogo -NonInteractive -WindowStyle Hidden -Command

#Регистрируем локальный репозиторий
try{
    Get-PSRepository -Name $repo.Name -ErrorAction Stop
}catch{
    $uri = 'http://RepoNuget.study.loc:5000'
    $repo = @{
        Name = 'MyRepository'
        SourceLocation = $uri
        PublishLocation = $uri
        InstallationPolicy = 'Trusted'
    }
    Register-PSRepository @repo
}

##Объект для данных из логфайла
#$objWULog = New-Object -TypeName PSObject


<#
Параметры аутентификации передавать с мастер скрипта во время формирования файла
#>
#Логин/пароль учётки под которой запускается задание планировщика
$UserId = 
$UserPassword = 

#Логин/пароль RollBack
$UserRBId = 
$UserRDPassword = 

#Логин/пароль MySql
$UserMysql = 
$PasswordMysql = 
$DBName = 
$MySqlServer = 

<#

TODO - Запись логов в MySql базу данных
#подключаем библиотеку MySql.Data.dll
Add-Type –Path ‘.\MySql.Data.dll'

# строка подключения к БД, server - имя севрера, uid - имя mysql пользователя, pwd- пароль, database - имя БД на сервере
$Connection = [MySql.Data.MySqlClient.MySqlConnection]@{ConnectionString="server=$MySqlServer;uid=$UserMysql;pwd=$PasswordMysql;database=$DBName"}
$Connection.Open()
$sql = New-Object MySql.Data.MySqlClient.MySqlCommand
$sql.Connection = $Connection

#записываем информацию о каждом пользователе в табдицу БД
$sql.CommandText = "INSERT INTO logs (host,message,status) VALUES ('c202pc16','WindowsUpdate Start','Ok')"
$sql.ExecuteNonQuery()

$Connection.Close()
#>

#Функция логирования событий
function out-log{
    param(
        $service,
        $message,
        $status
    )
    Begin{
        $d = Get-Date
        @($d,$service,$message,$status) -join '|' |  Out-File d:\update.log -Append
    }
}

#Скрипт блок включает либо выключает триггер планировщика
function Set-SchTaskTrigger {
    param(
        [switch] $triggerstatus
    )
    #https://ubuntugeeks.com/questions/836887/toggling-enabled-disabled-on-specific-triggers-in-a-task-in-the-task-scheduler-u
    #Если триггер включен, то отключаем его и ноборот.
    $TaskScheduler = New-Object -COMObject Schedule.Service
    $TaskScheduler.Connect()
    $TaskFolder = $TaskScheduler.GetFolder("\") # If your task is in the root "folder"
    $Task = $TaskFolder.GetTask("WindowsUpdate")
    $Definition = $Task.Definition
    $Definition.Triggers.Item(1).Enabled = $triggerstatus
    <#
    if ($Definition.Triggers.Item(1).Enabled) {
        $Definition.Triggers.Item(1).Enabled = $False
    } else {
        $Definition.Triggers.Item(1).Enabled = $True
    }
    #>
    Write-Host $Task.Definition.Principal.LogonType
    $TaskFolder.RegisterTaskDefinition($Task.Name, $Definition,6,$UserId,$UserPassword,1,$null)
}

#Скрипт блок выполняется при окончании процедуры установки обновлений
$sbLogAndExit = {
    #Если нужно перезагрузиться, таки перезагрузись, не держи в себе
    if (Get-WURebootStatus -Silent){
        Restart-Computer
    }
    #Отключаем триггер по загрузке
    ##Invoke-Command -ScriptBlock $Using:sbSchTaskTrigger -ArgumentList $false
    Set-SchTaskTrigger -triggerstatus:$false
    ## Производим очистку системы
    Stop-Service wuauserv -Force
    Start-Sleep  -Seconds 5
    Remove-Item C:\Windows\SoftwareDistribution -Recurse -Force
    Start-Service wuauserv
    #Если файл windowsupdate.log отсутствует снэпшот не делаем
    if (Test-Path D:\windowsupdate.log){
        #Отправляем лог по обновлениям
        ###
        #ToDo подготовить список установленных обновлений
        ###
        if (Test-Path D:\windowsupdate.log){
            #Ищим записи о последних обновлениях
            $content = Get-Content D:\windowsupdate.log
            #Ищем в лог фале устанавливалось ли обновление и какой был результат обновления обновления 
            #Если для всех текущиех обновлений результат был Failed более двух раз, тогда заврешаем скрипт
            foreach($s in $content){
                #Если мы находим в лог фале запись для текущего обновления и результат его выполнения был Failed, то увеличиваем значение 
                #хэштаблицы на единицу
                if (($s -match 'Failed') -or ($s -match 'Installed')){
                    $updateslist = $updateslist + '\n' + $s
                }
            }
        } else {
            $updateslist = "Обновление не требуется"
        }

        out-log -service "WindowsUpdate" -message $updateslist -status "OK"
        #Удаляем файл windowsupdate.log 
        Remove-Item D:\windowsupdate.log -Force
        #снимок системы
        $err = $Error.Count
        & $env:ProgramFiles\Shield\ShdCmd.exe /snapshot /n "WSUS" /overwrite /u $UserRBId /p $UserRDPassword
        if ($Error.Count -eq $err){
            out-log -service "RollBack" -message "New Snapshot" -status "OK"
        } else {
            out-log -service "RollBack" -message "New Snapshot" -status "Error"
        }
    } else {
        out-log -service "WindowsUpdate" -message "Обновление не требуется" -status "OK"
    }
    #Завершаем выполнение скрипта
    Stop-Computer -Force
    #[Environment]::Exit(0)
    #$maincycle = $false
}
        
########
#### Main block
########

#Обновляем модуль до последней версии, если модуль ещё не установлен на хосте устанавливаем его
try{
    Update-Module -Name "PSWindowsUpdate" -Force -ErrorAction Stop
}catch{
    Install-Module -Name "PSWindowsUpdate"  -Repository  MyRepository
}
#Подключаем требуемый модуль
try {
    Import-Module PSWindowsUpdate
} 
catch {
    out-log -service "Script" -message "Ошибка импорта модуля PSWindowsUpdate" -status "Error"
    [Environment]::Exit(1)
}

#Включаем триггер запуска задачи при загрузке хоста
Set-SchTaskTrigger -triggerstatus:$true

$maincycle = $true
while ($maincycle){
    #Проверяем наличие обновлений
    $wulist = Get-WUList
    if ((($wulist).Title).Length -gt 0) {
        #Обновления есть
        #Если файл D:\windowsupdate.log отсутствует, значит скрипт обновления запускается первый раз
        #Если файл присутствует и в нем остались обновления только в статусе Failed, тогда отпарвляем логи и завершаем работу скрипта
        if (Test-Path D:\windowsupdate.log){
            #Ищим записи о последних обновлениях
            $content = Get-Content D:\windowsupdate.log
            $htwulist = @{}
            foreach($wu in ($wulist).Title){
                #Инициируем хэш таблицу
                $htwulist[$wu] = 0
                #Ищем в лог фале устанавливалось ли обновление и какой был результат обновления обновления 
                #Если для всех текущиех обновлений результат был Failed более двух раз, тогда заврешаем скрипт
                foreach($s in $content){
                    #Если мы находим в лог фале запись для текущего обновления и результат его выполнения был Failed, то увеличиваем значение 
                    #хэштаблицы на единицу
                    if ($s.Contains($wu) -and ($s -match 'Failed')){
                        ++$htwulist[$wu]
                    }
                }
            }
            #Если значение для какого либо элемента меньше 2, выполняем установку обновлений ещё раз.
            $maincycle = $false
            foreach($i in $htwulist.Values){
                if($i -lt 2){
                    $maincycle = $true
                }
            }
            if(! $maincycle){
                #Отправляем лог и завершаем скрипт
                & $sbLogAndExit
            }
        } 
        #Установка обновлений
        Get-WUInstall -AcceptAll -Install | ft -AutoSize | Out-String -Width 4096 | Out-File d:\windowsupdate.log -Append
        <#
        Реализация создания лог файла через работу со свойствами объекта
        $out = Get-WUInstall -AcceptAll -IgnoreReboot -Install 
        foreach ($s in $out){
            $st.ComputerName
            $st.Status
            $st.Title
        }
        #>

        if (Get-WURebootStatus -Silent){
            Restart-Computer
        }
        #Если после установки обновлений система не перезагрузится, скрипт будет выполнятся 
        #по основному цыклу пока не будут установленны все обновления
    } 
    else {
        #Обновлений нет
        & $sbLogAndExit
    }
}