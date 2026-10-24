# ClubApi

ClubApi is a beginner-friendly ASP.NET Core 10 controller API for creating,
reading, updating, and deleting projects stored in Azure SQL Database.

## Architecture

`Client → ProjectsController → ProjectService → ClubDb → Azure SQL`

The controller handles HTTP and validation. The service contains the database
operations. `ClubDb` maps the `Project` entity to the `Projects` table. The API
returns response DTOs rather than exposing EF Core entities.

## Required software

- .NET 10 SDK
- Visual Studio Code
- Azure SQL Database and permission to connect to it
- VS Code REST Client extension (optional, for `ClubApi.http`)
- EF Core command-line tool for migrations: `dotnet tool install --global dotnet-ef`

The project targets `net10.0`. Its EF Core SQL Server, Design, and Tools packages
are all version `10.0.13`. To install them manually from the workspace root:

```powershell
dotnet add .\ClubApi\ClubApi.csproj package Microsoft.EntityFrameworkCore.SqlServer --version 10.0.13
dotnet add .\ClubApi\ClubApi.csproj package Microsoft.EntityFrameworkCore.Design --version 10.0.13
dotnet add .\ClubApi\ClubApi.csproj package Microsoft.EntityFrameworkCore.Tools --version 10.0.13
```

The built-in OpenAPI endpoint is available in Development at
`https://localhost:7240/openapi/v1.json`. Built-in OpenAPI generation does not
include a Swagger browser UI.

## Configure Azure SQL locally

The Azure SQL server uses **Microsoft Entra ID-only authentication**, so there
is no SQL username or password. The app signs in as whoever is logged in to the
Azure CLI (`az login`) via `Authentication=Active Directory Default`. The
connection string contains no secrets, but it is still kept in user-secrets so
configuration stays out of source files:

```powershell
az login
dotnet user-secrets set "ConnectionStrings:ClubDb" "Server=tcp:<YOUR_SERVER>.database.windows.net,1433;Initial Catalog=<YOUR_DATABASE>;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" --project .\ClubApi\ClubApi.csproj
```

The signed-in account must have access to the database (here, it is the
server's Entra admin). Do not put connection strings in `appsettings.json`,
`appsettings.Development.json`, source code, or `ClubApi.http`.

### Azure SQL firewall (changing IP addresses)

Azure SQL only accepts connections from public IP addresses listed in its
firewall. On networks where the public IP changes (such as a campus network),
run this script from the workspace root before working or presenting:

```powershell
.\scripts\Update-SqlFirewall.ps1
```

It replaces a single rule named `dev-laptop` with your current public IP, so
old addresses do not accumulate. It may take a few minutes to take effect. If
PowerShell blocks the script, run
`powershell -ExecutionPolicy Bypass -File .\scripts\Update-SqlFirewall.ps1`.

The firewall and authentication are separate: the firewall decides which
network can reach the server, and Entra ID decides who can log in.

### Migrations

The `InitialCreate` migration creates the `Projects` table (identity `Id`
primary key, required `Name` up to 100 characters) and **has been applied** to
the Azure SQL database. Do not run `migrations add InitialCreate` again. To
apply migrations to a fresh database:

```powershell
dotnet ef database update --project .\ClubApi\ClubApi.csproj
```

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
OpenAPI JSON in Development: `https://localhost:7240/openapi/v1.json`.

For a browser frontend, configure an explicit allowed origin. Set
`FRONTEND_ORIGIN` in the API process environment, or configure
`Cors:AllowedOrigins` in the host's environment/configuration. In PowerShell,
for the current session:

```powershell
$env:FRONTEND_ORIGIN = "<YOUR_FRONTEND_URL>"
```

With no allowed origin configured, browser cross-origin requests are denied.
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

## Optional Azure Functions demo

`ClubFunctions` is a separate isolated-worker demonstration; it is not part of
the CRUD API. Install Azure Functions Core Tools v4, then run:

```powershell
func start --script-root .\ClubFunctions
```

With the default Functions route prefix, the demo is
`GET http://localhost:7071/api/projects/ping` and returns
`{"message":"Club API ready"}`. The ASP.NET Core API remains the main CRUD
service.

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
- Host the ASP.NET Core API on Azure App Service. Host the optional demonstration
  separately on Azure Functions only if needed.

## Automated tests

Tests are in the separate `ClubApi.Tests` project and use a private in-memory
SQLite database. SQLite is test-only; the API uses SQL Server.

```powershell
dotnet test .\ClubApi.Tests\ClubApi.Tests.csproj
```
