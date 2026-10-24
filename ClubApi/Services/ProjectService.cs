using ClubApi.Data;
using ClubApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ClubApi.Services;

// The service contains the database operations used by the controller, keeping
// persistence logic separate from HTTP request/response handling.
public sealed class ProjectService(ClubDb db)
{
    // AsNoTracking is suitable for read-only queries and avoids change-tracking overhead.
    public Task<List<Project>> GetAllAsync(CancellationToken cancellationToken = default) =>
        db.Projects.AsNoTracking()
            .OrderBy(project => project.Id)
            .ToListAsync(cancellationToken);

    public Task<Project?> GetAsync(int id, CancellationToken cancellationToken = default) =>
        db.Projects.AsNoTracking()
            .SingleOrDefaultAsync(project => project.Id == id, cancellationToken);

    // Add marks a new row for insertion; SaveChangesAsync sends it to SQL Server.
    public async Task<Project> CreateAsync(
        string name,
        CancellationToken cancellationToken = default)
    {
        var item = new Project { Name = ValidateName(name) };
        db.Projects.Add(item);
        await db.SaveChangesAsync(cancellationToken);
        return item;
    }

    // FindAsync loads a row for editing; returning false lets the controller send 404.
    public async Task<bool> UpdateAsync(
        int id,
        string name,
        CancellationToken cancellationToken = default)
    {
        var item = await db.Projects.FindAsync([id], cancellationToken);
        if (item is null)
        {
            return false;
        }

        item.Name = ValidateName(name);
        await db.SaveChangesAsync(cancellationToken);
        return true;
    }

    // Remove marks a row for deletion; SaveChangesAsync persists the change.
    public async Task<bool> DeleteAsync(int id, CancellationToken cancellationToken = default)
    {
        var item = await db.Projects.FindAsync([id], cancellationToken);
        if (item is null)
        {
            return false;
        }

        db.Projects.Remove(item);
        await db.SaveChangesAsync(cancellationToken);
        return true;
    }

    // Keep names non-empty, trimmed, and within the database column's length limit.
    private static string ValidateName(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new ArgumentException("Name must not be empty or whitespace.", nameof(name));
        }

        var trimmedName = name.Trim();
        if (trimmedName.Length > 100)
        {
            throw new ArgumentException("Name must be 100 characters or fewer.", nameof(name));
        }

        return trimmedName;
    }
}
