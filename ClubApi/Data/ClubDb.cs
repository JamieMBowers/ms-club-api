using ClubApi.Models;
using Microsoft.EntityFrameworkCore;

namespace ClubApi.Data;

// EF Core uses this context to query and save data. A DbSet represents a table.
public sealed class ClubDb(DbContextOptions<ClubDb> options) : DbContext(options)
{
    public DbSet<Project> Projects => Set<Project>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Configure the Projects table to match the model and initial migration.
        modelBuilder.Entity<Project>(entity =>
        {
            entity.ToTable("Projects");
            entity.HasKey(project => project.Id);
            entity.Property(project => project.Id).ValueGeneratedOnAdd();
            entity.Property(project => project.Name)
                .IsRequired()
                .HasMaxLength(100);
        });
    }
}
