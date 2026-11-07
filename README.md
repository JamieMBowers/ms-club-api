# Club projects: backend and student setup

Follow this guide to run the complete workshop app on your computer. You will
open a Blazor website in your browser, use its forms to call an ASP.NET Core
API, and save project records in your own Azure SQL database.

## How the two projects fit together

| Repository | What it contains | Where it runs during this workshop |
|---|---|---|
| [ms-club-api](https://github.com/JamieMBowers/ms-club-api) (this repository) | Backend API, database migrations, SQL readiness script, and API tests | Your computer, HTTPS port 7240 |
| [ms_club_blazor_frontend](https://github.com/JamieMBowers/ms_club_blazor_frontend) | Blazor forms, project list, API client, and frontend tests | Your computer, HTTPS port 7260 |
| Your Azure SQL database | Saved project IDs and names | Your Azure subscription |

```text
Browser -> Blazor frontend -> HTTP API -> Azure SQL database
           localhost:7260    localhost:7240
```

Clone **both repositories**. They are separate applications and need two
running terminals. You do not need to deploy either application to Azure.
Only the database is hosted there. The frontend never connects directly to SQL.

A "project" in the app is just a database record with an ID and a name.
**Add a project does not create a VS Code project or source-code folder.**

## 1. Install the tools

- [Git](https://git-scm.com/downloads).
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0), not just the runtime.
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli-windows).
- Windows PowerShell and a modern browser. Use **Windows PowerShell** for the
  supplied SQL readiness script.
- An Azure subscription where you can create/manage an Azure SQL database.
- Optional: VS Code with C# Dev Kit; REST Client lets you use
  [ClubApi.http](ClubApi/ClubApi.http).

Open a new terminal after installing tools. Check that they are available:

```powershell
git --version
dotnet --list-sdks
az --version
dotnet dev-certs https --trust
```

The SDK list must include a `10.0.x` SDK. Accept the certificate trust prompt;
this lets the browser and frontend trust the local HTTPS API.

## 2. Clone both repositories

Run this **once** in PowerShell. These commands create two sibling folders
under your home directory:

```powershell
New-Item -ItemType Directory -Force "$HOME\club-workshop" | Out-Null
Set-Location "$HOME\club-workshop"
git clone https://github.com/JamieMBowers/ms-club-api.git .\ms_club_api
git clone https://github.com/JamieMBowers/ms_club_blazor_frontend.git .\ms_club_blazor_frontend
```

```text
club-workshop
  ms_club_api
    ClubApi
    ClubApi.Tests
    scripts
  ms_club_blazor_frontend
    ClubWeb
    ClubWeb.Tests
```

Already cloned them? Do not clone again. Use your existing folders and adjust
the paths below. The backend clone is deliberately named `ms_club_api`
(underscores), even though its GitHub repository name uses hyphens.

## 3. Configure your Azure SQL database

This is first-time setup. **Do not skip it:** the apps contain no mock data,
and starting the API does not automatically create its database tables.

### A. Prepare your own database

In the [Azure portal](https://portal.azure.com/), create an **Azure SQL
Database** in your student subscription, with a resource group and a logical
SQL server. You can also use your own existing workshop database.

- Use Microsoft Entra authentication and set your student account as the
  server's **Microsoft Entra administrator**, or ask the instructor/admin to
  grant your account the required database permissions.
- For this local-development walkthrough, the server needs public network
  access with your laptop's IP allowed by a firewall rule. The script below
  manages that one rule; it does not enable public access on a private-only server.
- Select a service tier you can afford and review its estimated cost before
  creating it. Use a student/free offer if eligible; do not assume all options
  are free. The script does not create resources or change pricing tiers.
- Record your **subscription ID**, **resource group**, **server name**, and
  **database name**. Use your own values, not the instructor's.

Azure subscription access alone does **not** grant SQL data access. Your
account needs permission both to manage the firewall and to connect to the
database/create its tables.

### B. Sign in, allow your laptop, and wake the database

Run from the **backend repository root**:

```powershell
Set-Location "$HOME\club-workshop\ms_club_api"
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
.\scripts\Update-SqlFirewall.ps1
```

Replace every `<YOUR_...>` placeholder in this guide with your own value,
without the angle brackets.

On the first run, the terminal lists your enabled subscriptions and asks for:

1. **Subscription ID** (copy the ID for your own student subscription).
2. **Resource group**.
3. **SQL server name** (the short name, without `.database.windows.net`).
4. **Database name**.
5. **Firewall rule name**, defaulting to `dev-<computer-name>`. Keep this name
   unique to your laptop, especially if sharing a SQL server.

Confirm the target and wait for the **database-ready message** before
continuing. The script checks connectivity with `SELECT 1`; it does not create
the application's tables.

<details>
<summary>Firewall script reference: saved settings, retries, and advanced options</summary>

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

</details>

If script execution is blocked, use the `powershell -ExecutionPolicy Bypass`
command in the expandable reference above. If warm-up fails, resolve that error
before continuing.

### C. Tell the API which database to use

The API uses Microsoft Entra ID-only authentication through your Azure CLI
login. No SQL username or password is needed. The connection string is stored
in local .NET user-secrets, not in the project files. The script does **not**
configure the API connection string or apply database migrations.

Still in the backend repository root, run:

```powershell
dotnet user-secrets set "ConnectionStrings:ClubDb" "Server=tcp:<YOUR_SERVER>.database.windows.net,1433;Initial Catalog=<YOUR_DATABASE>;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" --project .\ClubApi\ClubApi.csproj
```

Use the **same server and database** you selected for the firewall script.
`<YOUR_SERVER>` is the short server name, without `.database.windows.net`.
Do not put the connection string in Git, the frontend, or an appsettings file.

### D. Create the tables using the existing migration

Install the EF Core tool once. The version below matches the backend's EF packages:

```powershell
dotnet tool install --global dotnet-ef --version 10.0.13
```

If the tool is already installed, use this instead:

```powershell
dotnet tool update --global dotnet-ef --version 10.0.13 --allow-downgrade
```

Apply the existing migration to **your own database**:

```powershell
dotnet ef database update --project .\ClubApi\ClubApi.csproj -- --environment Development
```

This builds the API, uses its Development configuration/user-secrets, and
creates the `Projects` table if the migration has not already been applied.
Wait for successful completion. Do **not** create another `InitialCreate`
migration or manually create the table. A new database starts with no projects;
that is normal. See the [database reference](ClubApi/README.md#configure-azure-sql-locally)
for more detail.

## 4. Run both apps

Open **two separate terminals**. Both must stay running while you use the app.

**Terminal 1 - backend API**, from the backend repository root:

```powershell
Set-Location "$HOME\club-workshop\ms_club_api"
.\scripts\Update-SqlFirewall.ps1
dotnet run --project .\ClubApi\ClubApi.csproj --launch-profile https
```

If your Azure login has expired, run `az login` and select the subscription
from step 3 again. Refreshing the firewall/waking SQL is useful after a network
change or an idle period; it does not replace the first-time setup.

Wait for the API's listening message. In a browser, open
<https://localhost:7240/api/projects>. A new database should return `[]`;
an existing database returns JSON records. An error here means the backend
needs attention before starting the frontend. The Scalar page alone loading
does not prove SQL connectivity.

**Terminal 2 - Blazor frontend**, from the frontend repository root:

```powershell
Set-Location "$HOME\club-workshop\ms_club_blazor_frontend"
dotnet watch --project .\ClubWeb\ClubWeb.csproj run --launch-profile https
```

Open **<https://localhost:7260/>**. You should see **Add a project** and the
projects list, not just an API endpoint picker. With a new database, the list
will be empty until you add a record.

| Browser address | What you should see |
|---|---|
| <https://localhost:7260/> | The app: forms and a searchable project list |
| <https://localhost:7240/scalar/v1> | Scalar: documentation and an API request tester |
| <https://localhost:7240/api/projects> | Raw project JSON, or `[]` for an empty database |
| <https://localhost:7240/openapi/v1.json> | The API's machine-readable description |

The API base address `https://localhost:7240/` has **no homepage** and returns
404; that is expected. The website is on **7260**, not 7240. Scalar and OpenAPI
are available only in Development, which both HTTPS launch profiles select.

The frontend already points to `https://localhost:7240/` in its Development
settings. No SQL credentials or CORS changes are needed in the frontend:
its API requests run on the Blazor server, not directly in browser JavaScript.
See the [frontend guide](https://github.com/JamieMBowers/ms_club_blazor_frontend#api-address)
if you need a different API address.

`dotnet watch` applies supported Razor, CSS, and C# edits with Hot Reload; it
prompts for a restart when necessary. Use `dotnet run` instead of watch for a
normal run. Stop each app with **Ctrl+C** in its own terminal.

## 5. See the full journey in your browser

1. In the frontend, expand **Behind the scenes: API activity**. The initial
   list load sends `GET /api/projects` and should return **200**.
2. Add a uniquely named disposable record, such as `My workshop demo 14-30`.
   Note the generated ID. This sends `POST /api/projects`, returning **201**;
   the UI then reloads the list.
3. Open or refresh <https://localhost:7240/api/projects> in another tab. Find
   the same ID/name. The website and API are showing the same database record.
4. Search for your record, select **View**, then **Rename** and **Save changes**.
   The rename sends `PUT /api/projects/{id}` and returns **204** (no body).
   Searching the already loaded list is local and sends no API request.
5. Refresh the frontend page. The new name should remain. For a stronger
   persistence check, stop/restart the API, then refresh the page again:
   the record is stored in SQL, not just in the page or API memory.
6. Select **Delete**, check the ID/name, then **Delete permanently**. This sends
   `DELETE /api/projects/{id}` and returns **204**. Refresh the JSON tab to
   confirm your record has gone. Only delete the record you created.

The activity panel keeps only the last six HTTP exchanges, so inspect it as
you go. Browser DevTools will not show direct fetches to the API because this
is Blazor **Interactive Server**. Use the activity panel or Scalar to inspect
the API calls.

Next time, repeat **step 4**, not cloning, installing tools, or creating another
migration. Keep your database and saved local settings; each student should
configure their own rather than copy another student's settings.

## Common setup problems

| Symptom | What to check |
|---|---|
| `dotnet` or `az` not found | Install the required tool and open a new terminal. Install the .NET SDK, not only the runtime. |
| HTTPS/certificate warning | Run `dotnet dev-certs https --trust`, accept the prompt, then restart both apps/browser. Do not disable certificate checks. |
| API root returns 404 | Expected. Use `/api/projects` or `/scalar/v1`; the website is on port 7260. |
| API returns 500 or SQL times out | Check Azure login, subscription, SQL permissions, the connection string, firewall, and database readiness. The API terminal has diagnostic details; do not share secrets in logs. |
| SQL reports an invalid/missing `Projects` table | Apply the existing migration to the same database used by the API (step 3D). |
| Frontend cannot load projects | First make `/api/projects` work in the browser. Then check both apps are running and frontend `ClubApi:BaseUrl` is the API root URL with a trailing slash. |
| Port already in use | Stop your older API/frontend instance in its terminal before starting another copy. |
| Blazor shows a disconnected/reconnect message | Keep the frontend terminal running; restart it if necessary and reload the page. |
| Write succeeded but the list could not refresh | Use **Refresh projects**; do not repeat the successful add/rename/delete. |

This is a teaching app with **no endpoint authentication or authorization**.
Do not expose it publicly or use it for sensitive data without adding security.

## Debug in VS Code

Debug settings are in `.vscode\launch.json` and `.vscode\tasks.json`. They
need the **C# Dev Kit** (or **C#**) extension.

The published backend solution, `ClubApi.sln`, includes the API and API tests.
The frontend has its own solution in the separate frontend repository.
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
