using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ClubApi.Contracts;
using Xunit;

namespace ClubApi.Tests;

public sealed class ProjectsControllerTests
{
    [Fact]
    public async Task PostValidProjectReturnsCreated()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync(
            "/api/projects",
            new { name = "Campus Finder" });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var project = await response.Content.ReadFromJsonAsync<ProjectResponse>();
        Assert.NotNull(project);
        Assert.Equal("Campus Finder", project.Name);
    }

    [Fact]
    public async Task PostValidProjectReturnsLocationHeader()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync(
            "/api/projects",
            new { name = "Campus Finder" });

        Assert.NotNull(response.Headers.Location);
        Assert.EndsWith("/api/projects/1", response.Headers.Location!.ToString());
    }

    [Fact]
    public async Task PostEmptyNameReturnsBadRequest()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/projects", new { name = "" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task PostWhitespaceNameReturnsBadRequest()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/projects", new { name = "   " });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task GetExistingIdReturnsOk()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();
        var project = await CreateProjectAsync(client);

        var response = await client.GetAsync($"/api/projects/{project.Id}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<ProjectResponse>();
        Assert.Equal(project, result);
    }

    [Fact]
    public async Task GetMissingIdReturnsNotFound()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/projects/999999");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task PutExistingProjectReturnsNoContent()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();
        var project = await CreateProjectAsync(client);

        var response = await client.PutAsJsonAsync(
            $"/api/projects/{project.Id}",
            new { name = "Updated Project" });

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    [Fact]
    public async Task PutMissingProjectReturnsNotFound()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();

        var response = await client.PutAsJsonAsync(
            "/api/projects/999999",
            new { name = "Updated Project" });

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task DeleteExistingProjectReturnsNoContent()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();
        var project = await CreateProjectAsync(client);

        var response = await client.DeleteAsync($"/api/projects/{project.Id}");

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    [Fact]
    public async Task DeleteMissingProjectReturnsNotFound()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();

        var response = await client.DeleteAsync("/api/projects/999999");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task OpenApiDocumentIsAvailableInDevelopment()
    {
        using var factory = await CreateFactoryAsync();
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/openapi/v1.json");
        var document = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("/api/projects", document);
        Assert.Contains("/api/projects/{id}", document);
    }

    private static async Task<ClubApiFactory> CreateFactoryAsync()
    {
        var factory = new ClubApiFactory();
        _ = factory.CreateClient();
        await factory.InitializeDatabaseAsync();
        return factory;
    }

    private static async Task<ProjectResponse> CreateProjectAsync(HttpClient client)
    {
        var response = await client.PostAsJsonAsync(
            "/api/projects",
            new { name = "Campus Finder" });
        response.EnsureSuccessStatusCode();

        return (await response.Content.ReadFromJsonAsync<ProjectResponse>(
            new JsonSerializerOptions(JsonSerializerDefaults.Web)))!;
    }
}
