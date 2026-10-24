# ClubApi workshop

This workspace contains the ASP.NET Core API (`ClubApi`), its automated tests,
and an optional Azure Functions demo.

## Run locally

Open a PowerShell terminal in this workspace folder:

```powershell
cd C:\localdev\.Net\ms_club_api
```

### 1. Refresh the Azure SQL firewall rule

Azure SQL allows connections from the public IP address in its firewall rule.
On a campus or other network where that IP can change, run this script whenever
you reconnect or your public IP changes:

```powershell
az login
.\scripts\Update-SqlFirewall.ps1
```

If `az login` reports that you are already signed in, continue with the script.
It updates the dedicated `dev-laptop` firewall rule to your current public IP.
It can take a few minutes for the change to take effect.

If PowerShell blocks script execution, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Update-SqlFirewall.ps1
```

The API uses Microsoft Entra ID-only authentication through your Azure CLI
login. No SQL username or password is needed. The connection string is stored
in local .NET user-secrets, not in the project files.

### 2. Start the API

```powershell
dotnet run --project .\ClubApi\ClubApi.csproj --launch-profile https
```

Leave the terminal running. The API listens at `https://localhost:7240`.
Development OpenAPI JSON is available at:

<https://localhost:7240/openapi/v1.json>

Use `ClubApi\ClubApi.http` with the VS Code REST Client extension to try the
CRUD endpoints. Stop the API with **Ctrl+C**.

## Debug in VS Code

Debug settings are in `.vscode\launch.json` and `.vscode\tasks.json`. They
need the **C# Dev Kit** (or **C#**) extension.

The workspace loads `ClubApi.sln`, which includes the API, tests, and optional
Functions project. If VS Code still reports a missing `ms_club_api.csproj`
after the project rename, open the Command Palette (**Ctrl+Shift+P**) and run
**Developer: Reload Window** to reload the current solution.

1. Open the **Run and Debug** view (**Ctrl+Shift+D**).
2. Pick a configuration from the dropdown at the top:
   - **ClubApi (https)** builds and starts the API.
   - **ClubApi (https) + refresh firewall** updates the Azure SQL firewall
     rule to your current IP first, then builds and starts. Use this one
     after changing networks.
3. Press **F5**.

Set breakpoints by clicking left of a line number, for example in
`ClubApi\Controllers\ProjectsController.cs`. Then send a request from
`ClubApi\ClubApi.http`; execution pauses at the breakpoint.

- **F10** steps over, **F11** steps into, and **F5** continues.
- **Shift+F5** stops debugging.

You can also run the firewall update by itself: **Terminal → Run Task… →
Update SQL firewall (current IP)**.

If VS Code says the HTTPS certificate isn't trusted, run
`dotnet dev-certs https --trust` once and accept the prompt.

## Run tests

```powershell
dotnet test .\ClubApi.Tests\ClubApi.Tests.csproj
```

See [ClubApi/README.md](./ClubApi/README.md) for API routes, database
configuration, migration details, security notes, and troubleshooting.
