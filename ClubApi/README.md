# ClubApi

ClubApi is a beginner-friendly ASP.NET Core 10 controller API for creating,
reading, updating, and deleting projects stored in Azure SQL Database.

**New to the workshop? Start with the [complete student setup guide](../README.md).**
It covers cloning both repositories, preparing your own database, starting the
two apps, and a browser exercise. This file is the backend reference.

## Architecture

`Client → ProjectsController → ProjectService → ClubDb → Azure SQL`

The controller handles HTTP and validation. The service contains the database
operations. `ClubDb` maps the `Project` entity to the `Projects` table. The API
returns response DTOs rather than exposing EF Core entities.

## Required software

- .NET 10 SDK (not just the runtime)
- Git, Azure CLI, Windows PowerShell, and a browser
- Visual Studio Code (optional)
- Azure SQL Database and permission to connect to it
- VS Code REST Client extension (optional, for `ClubApi.http`)
- EF Core command-line tool for migrations:
  `dotnet tool install --global dotnet-ef --version 10.0.13`

The project targets `net10.0`. Its EF Core SQL Server, Design, and Tools packages
are all version `10.0.13` and are already declared in the project. Normal
build/run commands restore them; students do not need to add the packages again.
If `dotnet-ef` is already installed, the
[student setup guide](../README.md#d-create-the-tables-using-the-existing-migration)
shows how to select the matching tool version.

All commands in this file run from the **backend repository root**, the folder
containing `ClubApi.sln`, not from inside the `ClubApi` subfolder.

In Development, this app provides a
[Scalar interactive API page](https://localhost:7240/scalar/v1) for exploring
and calling endpoints, backed by the
[OpenAPI JSON document](https://localhost:7240/openapi/v1.json).

## Configure Azure SQL locally

Create or select your own Azure SQL database first; see
[step 3 of the student guide](../README.md#3-configure-your-azure-sql-database).
The app and firewall script do not provision Azure resources.

The Azure SQL server uses **Microsoft Entra ID-only authentication**, so there
is no SQL username or password. The app signs in as whoever is logged in to the
Azure CLI (`az login`) via `Authentication=Active Directory Default`. The
connection string contains no secrets, but it is still kept in user-secrets so
configuration stays out of source files:

```powershell
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
dotnet user-secrets set "ConnectionStrings:ClubDb" "Server=tcp:<YOUR_SERVER>.database.windows.net,1433;Initial Catalog=<YOUR_DATABASE>;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" --project .\ClubApi\ClubApi.csproj
```

The signed-in account must have access to the database, for example as the
server's configured Entra admin. Azure subscription ownership alone does not
grant SQL data access. Students must use their own server/database names and
apply the existing migrations to their new database. Do not put connection strings in `appsettings.json`,
`appsettings.Development.json`, source code, or `ClubApi.http`.

### Azure SQL firewall (changing IP addresses)

Azure SQL only accepts connections from public IP addresses listed in its
firewall. On networks where the public IP changes (such as a campus network),
run this script from the workspace root before working or presenting:

```powershell
.\scripts\Update-SqlFirewall.ps1
```

The first run prompts for your subscription ID, resource group, SQL server,
database, and a laptop-specific firewall rule name (default `dev-<computer-name>`).
It validates the selected target and asks for confirmation, then saves the
resource identifiers in the Git-ignored
[`scripts/sql-firewall.local.json`](../scripts/sql-firewall.local.json).
Later runs reuse that file; `-Configure` starts setup again.

It updates only your named rule to your current public IPv4 address.
**All other firewall rules are preserved**, including other students' rules
and manually added client rules. Remove obsolete rules manually if needed.
The script explicitly scopes Azure commands and token acquisition to the
selected subscription; it does not switch the CLI's active subscription,
create resources, or update the API's user-secrets.
See the [student setup instructions](../README.md#b-sign-in-allow-your-laptop-and-wake-the-database)
for parameters and non-interactive use.

It may take a few minutes for firewall changes to take effect. If
PowerShell blocks the script, run
`powershell -ExecutionPolicy Bypass -File .\scripts\Update-SqlFirewall.ps1`.

After updating the firewall, the script uses your Azure CLI login to run a
read-only `SELECT 1` against your selected database, waking it if paused. The API does not
need to be running. Wait for the database-ready message before sending API
requests. Transient SQL errors are retried up to 12 attempts, 10 seconds apart;
other errors stop immediately. A failed warm-up leaves the firewall update
in place.

The free offer and auto-pause settings are unchanged. Warm-up consumes some
free monthly compute allowance and cannot bypass a pause due to exhaustion
of that allowance. The probe closes its connection so auto-pause still works.
Use `-SkipDatabaseWarmup` for firewall-only updates. The VS Code firewall task
also performs this warm-up, but does not prompt: run the **Configure SQL
firewall and warm-up** task first to save your settings.

The firewall and authentication are separate: the firewall decides which
network can reach the server, and Entra ID decides who can log in.

### Migrations

The `InitialCreate` migration creates the `Projects` table (identity `Id`
primary key, required `Name` up to 100 characters). It has already been
applied to the instructor's database, but students must apply it to their own
database. Do not run `migrations add InitialCreate` again. After configuring
your own connection string, apply the existing migrations:

```powershell
dotnet ef database update --project .\ClubApi\ClubApi.csproj -- --environment Development
```

The explicit Development environment loads the API's local user-secrets.
The API does not apply migrations on startup. A new database has an empty
`Projects` table; adding records through the frontend is part of the exercise.

Never use `EnsureDeleted`, do not use `EnsureCreated` with Azure SQL, and do
not roll back migrations or drop tables without reviewing the effect first.

## Run the API

After setting user-secrets and confirming database/schema readiness:

```powershell
dotnet restore .\ClubApi\ClubApi.csproj
dotnet build .\ClubApi\ClubApi.csproj
dotnet run --project .\ClubApi\ClubApi.csproj --launch-profile https
```

The existing HTTPS launch profile uses port `7240`; HTTP uses port `5090`.
Open <https://localhost:7240/scalar/v1> in your browser to try the API in
Development. Raw OpenAPI JSON is at <https://localhost:7240/openapi/v1.json>.
The base address `https://localhost:7240/` has no homepage and returns
**404 Not Found**; this is expected and does not indicate a startup failure.

Check <https://localhost:7240/api/projects> as well: `[]` or an array of records
confirms a successful database read. Loading Scalar alone does not check the
database. Next, start the separate
[Blazor frontend](https://github.com/JamieMBowers/ms_club_blazor_frontend)
and open <https://localhost:7260/> for the forms and list.

### CORS and the Blazor frontend

The workshop frontend uses **Blazor Interactive Server**. Its API client runs
on the server, so **no CORS configuration is needed for this frontend**.
It needs only the API base URL, never a SQL connection string.

For a different frontend that calls the API directly from browser JavaScript,
configure an explicit allowed origin. Set
`FRONTEND_ORIGIN` in the API process environment, or configure
`Cors:AllowedOrigins` in the host's environment/configuration. In PowerShell,
for the current session:

```powershell
$env:FRONTEND_ORIGIN = "<YOUR_FRONTEND_URL>"
```

With no allowed origin configured, direct browser cross-origin requests are denied.
The app never enables `AllowAnyOrigin`.

## Try the API

Open `ClubApi.http` with VS Code REST Client and send requests individually.
Its base URL matches the HTTPS launch profile. The route/response contract is:

| Method | Route | Success | Other documented result |
|---|---|---|---|
| GET | `/api/projects` | 200 + list | — |
| GET | `/api/projects/{id}` | 200 + record | 404 if missing |
| POST | `/api/projects` | 201 + record + `Location` | 400 for invalid input |
| PUT | `/api/projects/{id}` | 204 | 400 for invalid input; 404 if missing |
| DELETE | `/api/projects/{id}` | 204 | 404 if missing |

The POST and PUT JSON bodies use a `name` string. Empty, whitespace-only, or
longer-than-100-character names receive a 400 validation response. The
unsupported-content-type example demonstrates a possible 415 response.

To verify database persistence: POST a project, record its returned `id`, stop
the API, restart it, then GET `/api/projects/{id}` and confirm it is still
present.

## Troubleshooting

- **404:** Check the URL and integer ID, the controller's route attribute, and
  that `app.MapControllers()` is configured.
- **400:** Check validation details and that the JSON field is named `name`.
- **415:** Send `Content-Type: application/json` for JSON request bodies.
- **Connection failure:** Check that the API is running, use the correct HTTP or
  HTTPS port, trust the local HTTPS development certificate, and verify the
  connection string, credentials, and Azure SQL firewall rule.
- **Database error:** Check the SQL Server provider, actual table/schema, whether
  the approved migration has been applied, the database user's table
  permissions, and Azure SQL permissions.

## Security and production notes

- HTTPS is enabled in the development launch profiles.
- Input validation and response DTOs restrict accepted and returned fields.
- CORS uses explicitly configured origins only.
- Exception responses use ProblemDetails and do not return exception details.
- Do not log passwords, tokens, connection strings, or sensitive request bodies.
- Use local user-secrets for development. For Azure App Service, prefer a
  system-assigned or user-assigned managed identity and grant that identity
  least-privilege Azure SQL database access. Configure the App Service connection
  string using an Azure SQL-compatible managed-identity authentication mode
  (for example, `Authentication=Active Directory Managed Identity`) or load it
  from Key Vault. Environment/App Service connection-string configuration can
  use the `ConnectionStrings:ClubDb` key; never put credentials in source
  control.
- Username/password authentication is a local-development fallback, not the
  preferred production approach.
- Authentication and authorization are not implemented. Add Microsoft Entra ID
  authentication and endpoint authorization as a deliberate next step; no fake
  authentication is used here.
- Host the ASP.NET Core API on Azure App Service.

## Automated tests

Tests are in the separate `ClubApi.Tests` project and use a private in-memory
SQLite database. SQLite is test-only; the API uses SQL Server.

```powershell
dotnet test .\ClubApi.Tests\ClubApi.Tests.csproj
```
