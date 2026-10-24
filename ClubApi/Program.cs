// Run from the repository root:
//   dotnet user-secrets set "ConnectionStrings:ClubDb" "<your SQL Server connection string>" --project ClubApi\ClubApi.csproj
//   dotnet ef database update --project ClubApi\ClubApi.csproj
//   dotnet run --project ClubApi\ClubApi.csproj
// In Development, open http://localhost:5090/scalar/v1 to explore and call the API.

using ClubApi.Data;
using ClubApi.Services;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

// Register the parts of the app that endpoints need: controllers, OpenAPI, error
// responses, and the database context/service. The connection string is named ClubDb.
builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddDbContext<ClubDb>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("ClubDb")));
builder.Services.AddScoped<ProjectService>();

// Allow browser-based frontends only from configured origins.
var allowedOrigins = builder.Configuration
    .GetSection("Cors:AllowedOrigins")
    .Get<string[]>() ?? [];
var frontendOrigin = builder.Configuration["FRONTEND_ORIGIN"];
if (!string.IsNullOrWhiteSpace(frontendOrigin))
{
    allowedOrigins = [.. allowedOrigins, frontendOrigin];
}

builder.Services.AddCors(options =>
{
    options.AddPolicy("Frontend", policy =>
    {
        if (allowedOrigins.Length > 0)
        {
            policy.WithOrigins(allowedOrigins)
                .AllowAnyHeader()
                .AllowAnyMethod();
        }
    });
});

var app = builder.Build();

// Middleware handles errors/status pages, HTTPS redirection, and frontend CORS.
app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseHttpsRedirection();
app.UseCors("Frontend");

if (app.Environment.IsDevelopment())
{
    // OpenAPI describes the routes; Scalar presents them in an interactive web page.
    app.MapOpenApi();
    app.MapScalarApiReference();
}

// Connect controller routes (such as /api/projects) to incoming HTTP requests.
app.MapControllers();

app.Run();

public partial class Program
{
}
