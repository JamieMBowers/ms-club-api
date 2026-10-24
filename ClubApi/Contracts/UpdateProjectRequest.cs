using System.ComponentModel.DataAnnotations;

namespace ClubApi.Contracts;

/// <summary>JSON request body used to replace a project's editable values.</summary>
public sealed record UpdateProjectRequest
{
    [Required]
    [StringLength(100)]
    public required string Name { get; init; }
}
