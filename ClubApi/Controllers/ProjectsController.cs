using ClubApi.Contracts;
using ClubApi.Services;
using Microsoft.AspNetCore.Mvc;

namespace ClubApi.Controllers;

// A controller groups related HTTP endpoints. [ApiController] binds JSON request
// bodies to DTOs and automatically validates data annotations. This route prefix
// combines with each action's [HttpGet], [HttpPost], etc. to form the full URL.
[ApiController]
[Route("api/projects")]
// ASP.NET Core injects the registered service through this constructor.
public sealed class ProjectsController(ProjectService service) : ControllerBase
{
    // GET /api/projects: return every project.
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<ProjectResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ProjectResponse>>> GetAll(
        CancellationToken cancellationToken)
    {
        var projects = await service.GetAllAsync(cancellationToken);
        return Ok(projects.Select(project => new ProjectResponse(project.Id, project.Name)).ToArray());
    }

    // GET /api/projects/{id}: return one project, or 404 if it does not exist.
    [HttpGet("{id:int}", Name = nameof(GetById))]
    [ProducesResponseType(typeof(ProjectResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ProjectResponse>> GetById(
        int id,
        CancellationToken cancellationToken)
    {
        var project = await service.GetAsync(id, cancellationToken);
        return project is null
            ? NotFound()
            : Ok(new ProjectResponse(project.Id, project.Name));
    }

    // POST /api/projects: read JSON into a request DTO, save it, and return 201 Created.
    [HttpPost]
    [ProducesResponseType(typeof(ProjectResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<ProjectResponse>> Create(
        CreateProjectRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
        {
            ModelState.AddModelError(nameof(request.Name), "Name must not be empty or whitespace.");
            return ValidationProblem(ModelState);
        }

        var project = await service.CreateAsync(request.Name, cancellationToken);
        var response = new ProjectResponse(project.Id, project.Name);
        return CreatedAtAction(nameof(GetById), new { id = project.Id }, response);
    }

    // PUT /api/projects/{id}: replace the project's editable data.
    [HttpPut("{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Update(
        int id,
        UpdateProjectRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
        {
            ModelState.AddModelError(nameof(request.Name), "Name must not be empty or whitespace.");
            return ValidationProblem(ModelState);
        }

        var updated = await service.UpdateAsync(id, request.Name, cancellationToken);
        return updated ? NoContent() : NotFound();
    }

    // DELETE /api/projects/{id}: remove the project.
    [HttpDelete("{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(int id, CancellationToken cancellationToken)
    {
        var deleted = await service.DeleteAsync(id, cancellationToken);
        return deleted ? NoContent() : NotFound();
    }
}
