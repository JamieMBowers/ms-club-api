using System.ComponentModel.DataAnnotations;

namespace ClubApi.Contracts;

/// <summary>JSON request body used to create a project, for example {"name":"Campus Finder"}.</summary>
public sealed record CreateProjectRequest
{
    [Required]
    [StringLength(100)]
    public required string Name { get; init; }
}
