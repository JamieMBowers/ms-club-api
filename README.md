# ClubApi workshop

This workspace contains the ASP.NET Core API (`ClubApi`) and its automated tests.

## Run locally

Open a Windows PowerShell terminal in your cloned repository folder.

### 1. Refresh the Azure SQL firewall rule and wake the database

Each student needs the Azure CLI, their own Azure subscription, and an existing
Azure SQL server/database configured for Microsoft Entra authentication. The
signed-in account must be allowed to manage the server's firewall and connect
to the database. This script does not create resources or change pricing tiers.

Sign in with your student account, then run:

```powershell
az login
.\scripts\Update-SqlFirewall.ps1
```

On the first run, the terminal lists your enabled subscriptions and asks for:

1. **Subscription ID** (copy the ID for your own student subscription).
2. **Resource group**.
3. **SQL server name** (the short name, without `.database.windows.net`).
4. **Database name**.
5. **Firewall rule name**, defaulting to `dev-<computer-name>`. Keep this name
   unique to your laptop, especially if sharing a SQL server.

The script checks that the target server/database exists, shows the selected
target, and asks for confirmation before saving or changing anything. It stores
only these resource identifiers in
[`scripts/sql-firewall.local.json`](scripts/sql-firewall.local.json), which is
Git-ignored. No passwords or access tokens are saved. Do not share this local
file with students; everyone should run their own setup.

Later runs reuse those settings without prompts. Run the script whenever you
change networks or want to wake the database. It updates only your named rule
to your current public IPv4 address and **preserves every other firewall rule**,
including other `dev-*` and `ClientIPAddress_*` rules. Stale rules with other
names must be removed manually if no longer needed. Changes can take a few
minutes to take effect.

The script then uses your Azure CLI login to connect to the selected database and run a
read-only `SELECT 1`. This wakes a paused serverless database without needing
the API to be running. Wait for the **database-ready message** before starting
the API. Temporary SQL errors (including wake-up timeouts and firewall
propagation) are retried up to 12 attempts, with 10 seconds between attempts.
Other errors stop immediately; a failed warm-up does not undo the firewall
update. Your signed-in account must have access to the database.

This does not change the free offer, compute tier, or auto-pause settings.
Waking the database consumes some of its free monthly compute allowance; it
does not bypass a pause caused by exhausting that allowance. The connection
is closed afterward so the database can auto-pause normally.

To replace saved settings, run:

```powershell
.\scripts\Update-SqlFirewall.ps1 -Configure
```

Use `-SkipDatabaseWarmup` to update only the firewall. Use `-NonInteractive`
for tasks/automation: it fails with setup instructions instead of prompting
if settings are missing. Explicit parameters override saved settings for that
run without rewriting the local file. For example, an unattended run without
a local settings file can supply all target details:

```powershell
.\scripts\Update-SqlFirewall.ps1 -NonInteractive `
    -SubscriptionId "<YOUR_SUBSCRIPTION_ID>" -ResourceGroup "<YOUR_RESOURCE_GROUP>" `
    -ServerName "<YOUR_SERVER>" -DatabaseName "<YOUR_DATABASE>" `
    -RuleName "dev-my-laptop"
```

All resource operations and SQL token acquisition explicitly use the selected
subscription. The script does not change the Azure CLI's active subscription.

If PowerShell blocks script execution, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Update-SqlFirewall.ps1
```

The API uses Microsoft Entra ID-only authentication through your Azure CLI
login. No SQL username or password is needed. The connection string is stored
in local .NET user-secrets, not in the project files. The script does **not**
configure the API connection string or apply database migrations. Follow
[Configure Azure SQL locally](ClubApi/README.md#configure-azure-sql-locally)
to point the API at the same server/database and select the matching CLI
subscription before running the API.

### 2. Start the API

```powershell
dotnet run --project .\ClubApi\ClubApi.csproj --launch-profile https
```

Leave the terminal running. Open the **Scalar interactive API page** in your
browser to explore and try the CRUD endpoints:

<https://localhost:7240/scalar/v1>

The base address `https://localhost:7240/` has no homepage and returns **404
Not Found**; that is expected, not a startup failure. Scalar and the raw
[OpenAPI JSON](https://localhost:7240/openapi/v1.json) are available only in
Development.

Alternatively, use [ClubApi\ClubApi.http](ClubApi/ClubApi.http) with the VS Code
REST Client extension to send requests. Stop the API with **Ctrl+C**.

## Debug in VS Code

Debug settings are in `.vscode\launch.json` and `.vscode\tasks.json`. They
need the **C# Dev Kit** (or **C#**) extension.

The workspace loads `ClubApi.sln`, which includes the API and tests.
If VS Code still reports a missing `ms_club_api.csproj`
after the project rename, open the Command Palette (**Ctrl+Shift+P**) and run
**Developer: Reload Window** to reload the current solution.

1. Open the **Run and Debug** view (**Ctrl+Shift+D**).
2. Pick a configuration from the dropdown at the top:
   - **ClubApi (https)** builds and starts the API.
   - **ClubApi (https) + refresh firewall** updates the Azure SQL firewall
     rule to your current IP and waits for the database to be ready, then
     builds and starts. Use this one after changing networks or a long idle
     period.
3. Press **F5**.

Set breakpoints by clicking left of a line number, for example in
`ClubApi\Controllers\ProjectsController.cs`. Then send a request from
`ClubApi\ClubApi.http`; execution pauses at the breakpoint.

- **F10** steps over, **F11** steps into, and **F5** continues.
- **Shift+F5** stops debugging.

You can also run the firewall update by itself: **Terminal → Run Task… →
Update SQL firewall (current IP)**. This task is non-interactive. Before using
it or the firewall-refresh debug configuration for the first time, run
**Configure SQL firewall and warm-up** from the same task menu (or run the
script in a terminal). The configure task prompts for your Azure settings.

If VS Code says the HTTPS certificate isn't trusted, run
`dotnet dev-certs https --trust` once and accept the prompt.

## Run tests

```powershell
dotnet test .\ClubApi.Tests\ClubApi.Tests.csproj
```

Firewall/setup tests use Pester (tested with Windows PowerShell's Pester 3.4)
and mock Azure, SQL, prompts, and local settings writes:

```powershell
Invoke-Pester -Script .\scripts\Update-SqlFirewall.Tests.ps1
```

See [ClubApi/README.md](./ClubApi/README.md) for API routes, database
configuration, migration details, security notes, and troubleshooting.
