$target = Join-Path $PSScriptRoot "Update-SqlFirewall.ps1"
Add-Type -AssemblyName System.Data

if (-not ("SqlWarmupTestConnection" -as [type])) {
    Add-Type -ReferencedAssemblies System.Data -TypeDefinition @"
public class SqlWarmupTestConnection
{
    public static int OpenCount;
    public string ConnectionString { get; set; }
    public string AccessToken { get; set; }
    public System.Data.SqlClient.SqlException Failure { get; set; }
    public void Open()
    {
        OpenCount++;
        if (AccessToken != "test-token") throw new System.InvalidOperationException("Wrong access token.");
        if (Failure != null) throw Failure;
    }
}
"@
}

function az { throw "Azure CLI must be mocked in these tests." }

function New-TestSqlException([int]$Number) {
    $flags = [System.Reflection.BindingFlags]"Instance,NonPublic"
    $constructor = [System.Data.SqlClient.SqlError].GetConstructors($flags) |
        Where-Object { $_.GetParameters().Count -eq 8 } |
        Select-Object -First 1
    $lastArgument = if ($constructor.GetParameters()[7].ParameterType -eq [uint32]) { [uint32]0 } else { $null }
    $errorRecord = $constructor.Invoke(@($Number, [byte]0, [byte]16, "test-server", "Test SQL failure", "", 1, $lastArgument))
    $errors = [Activator]::CreateInstance([System.Data.SqlClient.SqlErrorCollection], $true)
    $null = $errors.GetType().GetMethod("Add", $flags).Invoke($errors, @($errorRecord))
    $factory = [System.Data.SqlClient.SqlException].GetMethods([System.Reflection.BindingFlags]"Static,NonPublic") |
        Where-Object { $_.Name -eq "CreateException" -and $_.GetParameters().Count -eq 2 } |
        Select-Object -First 1
    return $factory.Invoke($null, @($errors, "test"))
}

Describe "SQL firewall update and database warm-up" {
    BeforeEach {
        $global:SqlFirewallTestState = @{
            Calls = New-Object "System.Collections.Generic.List[string]"
            Rules = '["dev-laptop","dev-old","ClientIPAddress_old","app-server","AllowAllWindowsAzureIps"]'
            FailOperation = ""
            Token = "test-token"
            DisposedConnections = 0
            DisposedCommands = 0
            Failures = 0
            Exception = $null
            QueryResult = 1
            ConnectionString = ""
            CommandText = ""
            CommandTimeout = 0
            HasConfig = $true
            InputConfig = '{"SubscriptionId":"11111111-1111-1111-1111-111111111111","ResourceGroup":"student-rg","ServerName":"msclub-server","DatabaseName":"msclub","RuleName":"dev-laptop"}'
            ExpectedSubscription = "11111111-1111-1111-1111-111111111111"
            Subscriptions = '[{"name":"Azure for Students","id":"11111111-1111-1111-1111-111111111111"}]'
            Answers = New-Object "System.Collections.Generic.Queue[string]"
            SavedJson = $null
        }
        [SqlWarmupTestConnection]::OpenCount = 0
        Mock Invoke-RestMethod { "203.0.113.42" }
        Mock Start-Sleep {}
        Mock Test-Path { $global:SqlFirewallTestState.HasConfig } -ParameterFilter { $LiteralPath -like "*sql-firewall.local.json" }
        Mock Get-Content { $global:SqlFirewallTestState.InputConfig } -ParameterFilter { $LiteralPath -like "*sql-firewall.local.json" }
        Mock Set-Content {
            $global:SqlFirewallTestState.SavedJson = $Value -join "`n"
        } -ParameterFilter { $LiteralPath -like "*sql-firewall.local.json" }
        Mock Read-Host {
            if ($global:SqlFirewallTestState.Answers.Count -eq 0) { throw "Unexpected terminal prompt." }
            return $global:SqlFirewallTestState.Answers.Dequeue()
        }
        Mock az {
            $state = $global:SqlFirewallTestState
            $operation = if ($args[0] -eq "account") {
                if ($args[1] -eq "get-access-token") { "token" } else { "account-$($args[1])" }
            } elseif ($args[1] -eq "db") {
                "db-$($args[2])"
            } elseif ($args[2] -eq "show") {
                "server-show"
            } else {
                $args[3]
            }
            if ($operation -ne "account-list") {
                $subscriptionIndex = [array]::IndexOf($args, "--subscription")
                if ($subscriptionIndex -lt 0 -or $args[$subscriptionIndex + 1] -ne $state.ExpectedSubscription) {
                    throw "Azure command did not explicitly target the selected subscription."
                }
            }
            $nameIndex = [array]::IndexOf($args, "-n")
            $name = if ($nameIndex -ge 0) { $args[$nameIndex + 1] } else { "" }
            $state.Calls.Add("${operation}:$name")
            $global:LASTEXITCODE = 0
            if ($operation -eq $state.FailOperation) {
                $global:LASTEXITCODE = 1
                return
            }
            if ($operation -eq "account-list") { return $state.Subscriptions }
            if ($operation -eq "account-show") { return "Azure for Students" }
            if ($operation -eq "server-show") { return "$name.database.windows.net" }
            if ($operation -eq "db-show") { return $name }
            if ($operation -eq "list") { return $state.Rules }
            if ($operation -in @("update", "create")) {
                foreach ($flag in @("--start-ip-address", "--end-ip-address")) {
                    $index = [array]::IndexOf($args, $flag)
                    if ($index -lt 0 -or $args[$index + 1] -ne "203.0.113.42") { throw "Wrong firewall IP." }
                }
            }
            if ($operation -in @("delete", "account-set")) { throw "Must not delete other rules or change the active subscription." }
            if ($operation -eq "token") {
                if (($args -join " ") -notmatch "https://database.windows.net/") {
                    throw "Wrong token resource."
                }
                return $state.Token
            }
        }
        Mock New-Object {
            $connection = New-Object SqlWarmupTestConnection
            if ([SqlWarmupTestConnection]::OpenCount -lt $global:SqlFirewallTestState.Failures) {
                $connection.Failure = $global:SqlFirewallTestState.Exception
            }
            $connection | Add-Member ScriptMethod CreateCommand {
                $command = [pscustomobject]@{ CommandText = ""; CommandTimeout = 0 }
                $command | Add-Member ScriptMethod ExecuteScalar {
                    $state = $global:SqlFirewallTestState
                    $state.CommandText = $this.CommandText
                    $state.CommandTimeout = $this.CommandTimeout
                    return $state.QueryResult
                }
                $command | Add-Member ScriptMethod Dispose { $global:SqlFirewallTestState.DisposedCommands++ }
                return $command
            }
            $connection | Add-Member ScriptMethod Dispose {
                $global:SqlFirewallTestState.ConnectionString = $this.ConnectionString
                $global:SqlFirewallTestState.DisposedConnections++
            }
            return $connection
        } -ParameterFilter { $TypeName -eq "System.Data.SqlClient.SqlConnection" }
    }

    AfterEach {
        Remove-Variable SqlFirewallTestState -Scope Global
    }

    It "reuses saved settings, preserves every other rule and executes a read-only probe" {
        & $target
        $state = $global:SqlFirewallTestState
        ($state.Calls -join ",") | Should Be "account-show:,server-show:msclub-server,db-show:msclub,list:,update:dev-laptop,token:"
        $state.CommandText | Should Be "SELECT 1"
        $state.CommandTimeout | Should Be 5
        [SqlWarmupTestConnection]::OpenCount | Should Be 1
        $state.DisposedConnections | Should Be 1
        $state.DisposedCommands | Should Be 1
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $state.ConnectionString
        $builder.DataSource | Should Be "tcp:msclub-server.database.windows.net,1433"
        $builder.InitialCatalog | Should Be "msclub"
        $builder.Encrypt | Should Be $true
        $builder.TrustServerCertificate | Should Be $false
        $builder.Pooling | Should Be $false
        $builder.ConnectTimeout | Should Be 15
        $builder.ConnectRetryCount | Should Be 0
        Assert-MockCalled Start-Sleep -Times 0 -Exactly -Scope It
        Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
        Assert-MockCalled Set-Content -Times 0 -Exactly -Scope It
    }

    It "creates a missing rule and supports a different server and database" {
        $global:SqlFirewallTestState.Rules = '[]'
        & $target -ServerName "another-server" -DatabaseName "another-db"
        ($global:SqlFirewallTestState.Calls -join ",") | Should Be "account-show:,server-show:another-server,db-show:another-db,list:,create:dev-laptop,token:"
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $global:SqlFirewallTestState.ConnectionString
        $builder.DataSource | Should Be "tcp:another-server.database.windows.net,1433"
        $builder.InitialCatalog | Should Be "another-db"
    }

    It "can skip database access entirely" {
        & $target -SkipDatabaseWarmup
        ($global:SqlFirewallTestState.Calls -join ",") | Should Not Match "token:"
        [SqlWarmupTestConnection]::OpenCount | Should Be 0
    }

    It "does not warm up after a firewall update failure" {
        $global:SqlFirewallTestState.FailOperation = "update"
        { & $target } | Should Throw "Failed to update the firewall rule"
        ($global:SqlFirewallTestState.Calls -join ",") | Should Be "account-show:,server-show:msclub-server,db-show:msclub,list:,update:dev-laptop"
        [SqlWarmupTestConnection]::OpenCount | Should Be 0
    }

    It "does not update the firewall when the selected server cannot be accessed" {
        $global:SqlFirewallTestState.FailOperation = "server-show"
        { & $target } | Should Throw "Cannot find SQL server"
        ($global:SqlFirewallTestState.Calls -join ",") | Should Be "account-show:,server-show:msclub-server"
        [SqlWarmupTestConnection]::OpenCount | Should Be 0
    }

    It "fails explicitly if token acquisition fails" {
        $global:SqlFirewallTestState.FailOperation = "token"
        { & $target } | Should Throw "could not get a SQL access token"
        [SqlWarmupTestConnection]::OpenCount | Should Be 0
    }

    It "rejects an empty token" {
        $global:SqlFirewallTestState.Token = ""
        { & $target } | Should Throw "could not get a SQL access token"
        [SqlWarmupTestConnection]::OpenCount | Should Be 0
    }

    It "retries transient SQL failures then succeeds" {
        $global:SqlFirewallTestState.Failures = 2
        $global:SqlFirewallTestState.Exception = New-TestSqlException 40613
        & $target
        [SqlWarmupTestConnection]::OpenCount | Should Be 3
        $global:SqlFirewallTestState.DisposedConnections | Should Be 3
        $global:SqlFirewallTestState.DisposedCommands | Should Be 1
        Assert-MockCalled Start-Sleep -Times 2 -Exactly -Scope It -ParameterFilter { $Seconds -eq 10 }
    }

    It "bounds retries and closes every connection on repeated timeouts" {
        $global:SqlFirewallTestState.Failures = 20
        $global:SqlFirewallTestState.Exception = New-TestSqlException -2
        { & $target } | Should Throw "database warm-up failed"
        [SqlWarmupTestConnection]::OpenCount | Should Be 12
        $global:SqlFirewallTestState.DisposedConnections | Should Be 12
        Assert-MockCalled Start-Sleep -Times 11 -Exactly -Scope It
    }

    It "does not retry SQL permission errors" {
        $global:SqlFirewallTestState.Failures = 20
        $global:SqlFirewallTestState.Exception = New-TestSqlException 18456
        { & $target } | Should Throw "database warm-up failed"
        [SqlWarmupTestConnection]::OpenCount | Should Be 1
        $global:SqlFirewallTestState.DisposedConnections | Should Be 1
        Assert-MockCalled Start-Sleep -Times 0 -Exactly -Scope It
    }

    It "rejects unexpected probe results and disposes both objects" {
        $global:SqlFirewallTestState.QueryResult = 0
        { & $target } | Should Throw "unexpected result"
        $global:SqlFirewallTestState.DisposedConnections | Should Be 1
        $global:SqlFirewallTestState.DisposedCommands | Should Be 1
        Assert-MockCalled Start-Sleep -Times 0 -Exactly -Scope It
    }

    It "prompts on first run and saves only confirmed resource settings" {
        $state = $global:SqlFirewallTestState
        $state.HasConfig = $false
        foreach ($answer in @($state.ExpectedSubscription, "student-rg", "student-sql", "student-db", "", "yes")) {
            $state.Answers.Enqueue($answer)
        }
        & $target -SkipDatabaseWarmup
        $saved = $state.SavedJson | ConvertFrom-Json
        $saved.SubscriptionId | Should Be $state.ExpectedSubscription
        $saved.ResourceGroup | Should Be "student-rg"
        $saved.ServerName | Should Be "student-sql"
        $saved.DatabaseName | Should Be "student-db"
        $saved.RuleName | Should Be "dev-$([Environment]::MachineName)"
        @($saved.PSObject.Properties).Count | Should Be 5
        ($state.Calls -join ",") | Should Be "account-list:,account-show:,server-show:student-sql,db-show:student-db,list:,create:dev-$([Environment]::MachineName)"
        Assert-MockCalled Read-Host -Times 6 -Exactly -Scope It
    }

    It "fails without prompting when unattended settings are missing" {
        $global:SqlFirewallTestState.HasConfig = $false
        { & $target -NonInteractive } | Should Throw "Run .\scripts\Update-SqlFirewall.ps1 -Configure"
        $global:SqlFirewallTestState.Calls.Count | Should Be 0
        Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
        Assert-MockCalled Set-Content -Times 0 -Exactly -Scope It
    }

    It "supports fully explicit unattended settings without a local file" {
        $global:SqlFirewallTestState.HasConfig = $false
        & $target -NonInteractive -SubscriptionId "11111111-1111-1111-1111-111111111111" `
            -ResourceGroup "student-rg" -ServerName "student-sql" -DatabaseName "student-db" -RuleName "student-laptop"
        ($global:SqlFirewallTestState.Calls -join ",") | Should Be "account-show:,server-show:student-sql,db-show:student-db,list:,create:student-laptop,token:"
        Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
        Assert-MockCalled Set-Content -Times 0 -Exactly -Scope It
    }

    It "allows an explicit subscription override without changing saved settings" {
        $global:SqlFirewallTestState.ExpectedSubscription = "22222222-2222-2222-2222-222222222222"
        & $target -SubscriptionId "22222222-2222-2222-2222-222222222222" -NonInteractive
        [SqlWarmupTestConnection]::OpenCount | Should Be 1
        Assert-MockCalled Set-Content -Times 0 -Exactly -Scope It
    }

    It "cancels first-run setup without writing settings or modifying Azure" {
        $state = $global:SqlFirewallTestState
        $state.HasConfig = $false
        foreach ($answer in @($state.ExpectedSubscription, "student-rg", "student-sql", "student-db", "", "n")) {
            $state.Answers.Enqueue($answer)
        }
        & $target
        ($state.Calls -join ",") | Should Be "account-list:,account-show:,server-show:student-sql,db-show:student-db"
        Assert-MockCalled Set-Content -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-RestMethod -Times 0 -Exactly -Scope It
        [SqlWarmupTestConnection]::OpenCount | Should Be 0
    }

    It "reconfigures even if the old settings file is malformed" {
        $state = $global:SqlFirewallTestState
        $state.InputConfig = "not json"
        foreach ($answer in @($state.ExpectedSubscription, "new-rg", "new-sql", "new-db", "new-laptop", "y")) {
            $state.Answers.Enqueue($answer)
        }
        & $target -Configure -SkipDatabaseWarmup
        ($state.SavedJson | ConvertFrom-Json).ServerName | Should Be "new-sql"
        Assert-MockCalled Get-Content -Times 0 -Exactly -Scope It
    }

    It "does not save or modify a target with a nonexistent database" {
        $global:SqlFirewallTestState.FailOperation = "db-show"
        { & $target } | Should Throw "Cannot find database"
        ($global:SqlFirewallTestState.Calls -join ",") | Should Be "account-show:,server-show:msclub-server,db-show:msclub"
        Assert-MockCalled Set-Content -Times 0 -Exactly -Scope It
        Assert-MockCalled Invoke-RestMethod -Times 0 -Exactly -Scope It
    }

    It "stops when no enabled subscription is available" {
        $global:SqlFirewallTestState.HasConfig = $false
        $global:SqlFirewallTestState.Subscriptions = "[]"
        { & $target } | Should Throw "No enabled subscriptions found"
        Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
        Assert-MockCalled Set-Content -Times 0 -Exactly -Scope It
    }

    It "rejects an invalid subscription before any resource operations" {
        { & $target -SubscriptionId "not-a-guid" } | Should Throw "Subscription ID must be a GUID"
        $global:SqlFirewallTestState.Calls.Count | Should Be 0
    }

    It "rejects incompatible setup switches without prompting" {
        { & $target -Configure -NonInteractive } | Should Throw "-Configure cannot be combined"
        Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
    }
}
