namespace ClubApi.Models;

// Database entity: EF Core maps each Project object to a row in Projects.
public sealed class Project
{
    public int Id { get; set; }

    public required string Name { get; set; }
}
