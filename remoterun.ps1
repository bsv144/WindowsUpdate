[cmdletbinding(DefaultParameterSetName="Host")]
Param(
	#Указываем группу хостов для которых нужно выполнить скрипт, если указано ALL, то скрпит выполняется для всех хостов с файла $path_hosts
	[Parameter(Mandatory = $true, ParameterSetName="Group")]
	[String[]]$group,
	##Если не задан параметр group, указываем список хостов для которых нужно выполнить скрипт
	[Parameter(Mandatory = $true, ParameterSetName="ComputerName")]
	[String[]]$computerName,
	#Путь к файлу со списком хостов
	[Parameter(Mandatory = $false)]
	[string]$hostfile = ".\Hosts.csv.hide",
	#Путь к файлу с паролем локального администратора удаленного хоста
	[Parameter(Mandatory = $false)]
	[string]$passfile = ".\passfile.hide",
	#Путь к xml файлу планировщика
	[Parameter(Mandatory = $false)]
	[string]$schedulerfile = ".\windowsupdate.xml",
	#Путь скрипту выполняющему одновление
	[Parameter(Mandatory = $false)]
	[string]$wupdatefile = ".\wupdate.ps1",
	#Признак необходимости обновления системы
	[Parameter(Mandatory = $false)]
	[switch]$wupdate = $false
)

Begin
{
  
	$hosts = @()
	#Импортируем список хостов из файла
	$importedhosts = Import-Csv $hostfile  -Delimiter ";"

	#Импортируем список логинов и паролей из файла
	$importedaccounts = Import-Csv $passfile  -Delimiter ";"

	#Создаём credential объект для локального администратора удалённого хоста
	$username = ($importedaccounts | where service -eq host).user
	$pass = ($importedaccounts | where service -eq host).hashpassword | ConvertTo-SecureString
	$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $pass
	$password = $cred.GetNetworkCredential().password

	#Получаем логин/пароль для ПО Rollback
	$UserRBId = ($importedaccounts | where service -eq rollback).user
	$pass = ($importedaccounts | where service -eq rollback).hashpassword | ConvertTo-SecureString
	$credRB = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserRBId, $pass
	$UserRBPassword = $credRB.GetNetworkCredential().password

	#Скрипт блок запускает откат удалённой системы к последней точке восстановления
	$sbRollbacRestore = {
        	param(
			[string] $UserRBId,
            		[string] $UserRBPassword
        	)
		#Add-Content -Path d:\out.txt -Value $process
		$process = Start-Process -FilePath $env:ProgramFiles\Shield\ShdCmd.exe -ArgumentList "/restore","/current","/u",$UserRBId,"/p","$UserRBPassword" 
		#-RedirectStandardError d:\rderr.txt -RedirectStandardOutput d:\rdout.txt -Wait -PassThru
		#Add-Content -Path d:\out.txt -Value $process.ExitCode
	} 

	#Скрипт блок создает задания планировщика по обновлению систему и запускает его
	$updateScript = Get-Content -Path $wupdatefile -Raw
	$schedulerxml = Get-Content -Path $schedulerfile | Out-String
	#TODO переносим логику обновления удалённого хоста сюда
	#Отказываемся от работы через планировщик windows
	$sbWupdate = {
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
		#Так как блок выполняется на удалённом хосте то запускаем обновление под учёткой 
		#Установка обновлений
		Get-WUInstall -AcceptAll -Install | ft -AutoSize | Out-String -Width 4096 | Out-File d:\windowsupdate.log -Append
		$process = Start-Process -FilePath $env:ProgramFiles\Shield\ShdCmd.exe -ArgumentList "" -Credential $Using:cred 
	}

	function write-log {
		param(
			[Parameter(Mandatory = $true)]
			[string]$ComputerName,
			[Parameter(Mandatory = $true)]
			[string]$message
		)
		$timestamp = Get-Date -Format g 
		write-host("{0} ;{1} ;{2}" -f $timestamp, $ComputerName, $message)
	}
	
	function send-wol {
		param(
		[Parameter(Mandatory = $true)]
		[string]$mac
		)
		begin{
			#Бродкаст адрес для интерфейса на который будет отправлен WOL
			$BroadcastProxy=[IPaddress]"172.25.75.255"
			$Ports = 0,7,9
			$synchronization = [byte[]](,0xFF * 6)
			$mac = $mac.replace('-','')
			#Есил длина mac не равна 12, выводим ошибку
			if ($mac.length -ne 12) {
				throw "Error mac address - $mac"
			}
			#Разбиваем mac на подстроки по два символа и преобразуем в строку byte
			foreach($i in (0..($mac.length-2)).Where({$_ % 2 -eq 0})){
				[byte[]] $bmac += [byte]('0x' + $mac.substring($i,2))
			}
			$packet = $synchronization + $bmac * 16
			#Write-Host $packet
			$UdpClient = New-Object System.Net.Sockets.UdpClient
			ForEach ($port in $Ports) {
				$UdpClient.Connect($BroadcastProxy, $port)
				$out = $UdpClient.Send($packet, $packet.Length)
				#Write-Host $out
			}
			$UdpClient.Close()
			Write-Log -ComputerName  $row.host -message "WOL send to $mac"			
		}
	}
}

Process
{
    <#
        Выполнение основной логики на удалённых хостах
    #>
	foreach($row in $importedhosts){
		if($group -contains $row.group -or $computerName -contains $row.host){
			Write-Host $row
			# 1. Пробуждаем хост
			Send-Wol -mac $row.mac
			#2. Ожидаем появление хоста в сети
			start-sleep -s 300
			try{
				Test-WSMan -ComputerName $row.host -ErrorAction Stop | out-null
			}catch{
				Write-Log -ComputerName  $row.host -message "WSMan don't accesss."	
				Breack
			}
			Write-Log -ComputerName  $row.host -message "WSMan accesss OK."	
			#3. Rollback системы 
            try{
			    Invoke-Command -ComputerName $row.host -Credential $cred -ScriptBlock $sbRollbacRestore -ArgumentList ($UserRBId, $UserRBPassword) -ErrorAction Stop
                write-log -ComputerName $row.host -message "Запущен процесс Rollback системы"
            } catch {
                write-log -ComputerName $row.host -message "На хосте необходимо выполнить команду Register-PSSessionConfiguration -Name Microsoft.PowerShell "
                
            }
            #4. Ожидаем отката системы (ожидаем перезагрузки системы)
            <#
                ##TODO - для точного мониторинга отката, перед откатом создаём файл. После отката проверяем.
                Если файл пропал то  значит откат произошол нормально.

            #>
            $count = 0
            do {
                start-sleep -s 60
                $count += 1 
                Write-host $count
                try{
				    Test-WSMan -ComputerName $row.host -ErrorAction Stop | out-null
				    $hostAccess = $true
			    }catch{
				    $hostAccess = $false
			    }
            } until ($hostAccess)
            #5. Проверяем необходимость установки обновлений системы
            if ($wupdate){
                ##5.1 Установка обновлений, через запуск задания планировщика
                <#
                -- Если при запуске планировщика произошла ошибка
                --- Записываем лог
                --- Завершаем работу хоста
                #>
                write-log -ComputerName $row.host -message "Установка обновлений системы"
                $out = Invoke-Command -ComputerName $row.host -Credential $cred -ScriptBlock $sbWupdate
                Write-Host $out
                #write-log -ComputerName $row.host -message ("{0}" -f $out)

            } else {
                #6. Выключаем компьютер
                write-log -ComputerName $row.host -message "Завершение работы системы"
                Stop-Computer -ComputerName $row.host -Force -Credential $cred
            }
		}
	}
}
