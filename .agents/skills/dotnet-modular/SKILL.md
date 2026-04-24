---
name: dotnet-modular
description: "Enforces modular monolith architecture for the ASP.NET Core backend — separate projects per domain, RESTful controllers (not Minimal APIs), no cross-service data coupling, clean service boundaries. Use this skill whenever the user asks to add, modify, scaffold, or refactor any backend API endpoint, service, controller, model, or database entity. Also trigger when the user mentions backend architecture, project structure, new features that need API work, or anything touching the backend/ directory."
---

# .NET Modular Monolith Architecture

This skill enforces a modular monolith architecture where each business domain lives in its own project — fully self-contained with its own controllers, services, models, and data access. The API project is just a thin host: it starts the app, registers middleware, and discovers controllers from the domain projects. All API endpoints use RESTful controllers, not Minimal APIs.

The reason for this architecture: as the product grows, each domain (Goals, Chat, Journal, etc.) should be independently testable, deployable as a microservice if needed, and maintainable by different developers without merge conflicts or accidental coupling. When the controller lives in the same project as the service and data layer, the entire feature is one self-contained unit — you can lift it out into its own service with zero rewiring.

## Solution Structure

```
backend/
├── ShantiSangha.sln
├── ShantiSangha.Api/                    # Thin host — NO controllers here
│   ├── Middleware/                       # Auth, error handling, request logging
│   ├── Program.cs                       # Service registration, controller discovery, pipeline
│   └── ShantiSangha.Api.csproj          # References ALL domain projects
│
├── ShantiSangha.Shared/                 # Shared kernel — VERY thin
│   ├── Interfaces/
│   │   ├── ICurrentUser.cs              # User context (UserId, Email)
│   │   └── IEventBus.cs                 # Cross-service communication contract
│   ├── Models/
│   │   └── PagedResult.cs               # Generic pagination wrapper
│   ├── Extensions/
│   │   └── ServiceCollectionExtensions.cs
│   └── ShantiSangha.Shared.csproj       # NO project references, minimal packages
│
├── ShantiSangha.Goals/                  # Goals domain — fully self-contained
│   ├── Controllers/
│   │   └── GoalsController.cs           # REST controller lives WITH its domain
│   ├── Models/
│   │   ├── Goal.cs
│   │   ├── GoalCheckIn.cs
│   │   └── GoalActivity.cs
│   ├── Contracts/
│   │   ├── CreateGoalRequest.cs         # Request/response DTOs
│   │   ├── UpdateGoalRequest.cs
│   │   └── GoalResponse.cs
│   ├── Data/
│   │   ├── GoalsDbContext.cs             # Own DbContext, own tables only
│   │   └── Migrations/                  # Own migration history
│   ├── Services/
│   │   ├── IGoalService.cs              # Internal service interface
│   │   └── GoalService.cs               # Implementation
│   ├── Jobs/
│   │   └── GoalNudgeJob.cs              # Background jobs for this domain
│   ├── DependencyInjection.cs           # builder.Services.AddGoals()
│   └── ShantiSangha.Goals.csproj        # References: Shared only
│
├── ShantiSangha.Chat/                   # Chat domain
│   ├── Controllers/
│   │   └── ConversationsController.cs
│   ├── Models/
│   │   ├── Conversation.cs
│   │   └── Message.cs
│   ├── Contracts/
│   │   ├── CreateConversationRequest.cs
│   │   ├── SendMessageRequest.cs
│   │   └── ConversationResponse.cs
│   ├── Data/
│   │   ├── ChatDbContext.cs
│   │   └── Migrations/
│   ├── Services/
│   │   ├── IChatService.cs
│   │   └── ChatService.cs
│   ├── AI/
│   │   ├── SystemPrompt.cs
│   │   └── SupportResources.cs
│   ├── Safety/
│   │   ├── ISafetyService.cs
│   │   └── SafetyService.cs
│   ├── Jobs/
│   │   ├── GenerateSummaryJob.cs
│   │   ├── GenerateEmbeddingJob.cs
│   │   └── ExtractInsightsJob.cs
│   ├── DependencyInjection.cs
│   └── ShantiSangha.Chat.csproj         # References: Shared only
│
├── ShantiSangha.Journal/                # Journal domain
│   ├── Controllers/
│   │   └── JournalsController.cs
│   ├── Models/
│   │   └── Journal.cs
│   ├── Contracts/
│   │   ├── CreateJournalRequest.cs
│   │   └── JournalResponse.cs
│   ├── Data/
│   │   ├── JournalDbContext.cs
│   │   └── Migrations/
│   ├── Services/
│   │   ├── IJournalService.cs
│   │   └── JournalService.cs
│   ├── DependencyInjection.cs
│   └── ShantiSangha.Journal.csproj
│
├── ShantiSangha.Wellness/               # Mood + Coping + Voice (cohesive domain)
│   ├── Controllers/
│   │   ├── MoodsController.cs
│   │   ├── CopingController.cs
│   │   └── VoiceController.cs
│   ├── Models/
│   │   ├── MoodCheckin.cs
│   │   ├── CopingSession.cs
│   │   └── VoiceEntry.cs
│   ├── Contracts/
│   │   ├── MoodContracts.cs
│   │   ├── CopingContracts.cs
│   │   └── VoiceContracts.cs
│   ├── Data/
│   │   ├── WellnessDbContext.cs
│   │   └── Migrations/
│   ├── Services/
│   │   ├── IMoodService.cs
│   │   ├── MoodService.cs
│   │   ├── ICopingService.cs
│   │   ├── CopingService.cs
│   │   ├── IVoiceService.cs
│   │   └── VoiceService.cs
│   ├── Jobs/
│   │   └── TranscribeVoiceJob.cs
│   ├── DependencyInjection.cs
│   └── ShantiSangha.Wellness.csproj
│
├── ShantiSangha.Insights/               # Insights + Semantic Search
│   ├── Controllers/
│   │   ├── InsightsController.cs
│   │   └── SearchController.cs
│   ├── Models/
│   │   ├── SavedInsight.cs
│   │   └── Summary.cs
│   ├── Contracts/
│   │   ├── InsightContracts.cs
│   │   └── SearchContracts.cs
│   ├── Data/
│   │   ├── InsightsDbContext.cs
│   │   └── Migrations/
│   ├── Services/
│   │   ├── IInsightService.cs
│   │   ├── InsightService.cs
│   │   ├── ISemanticSearchService.cs
│   │   └── SemanticSearchService.cs
│   ├── DependencyInjection.cs
│   └── ShantiSangha.Insights.csproj
│
└── ShantiSangha.Identity/               # User management + Auth
    ├── Controllers/
    │   └── UsersController.cs
    ├── Models/
    │   ├── User.cs
    │   └── Profile.cs
    ├── Contracts/
    │   └── UserContracts.cs
    ├── Data/
    │   ├── IdentityDbContext.cs
    │   └── Migrations/
    ├── Services/
    │   ├── IUserService.cs
    │   └── UserService.cs
    ├── DependencyInjection.cs
    └── ShantiSangha.Identity.csproj
```

## Project Reference Rules

These rules are non-negotiable. They exist to prevent the data coupling that turns modular monoliths into distributed monoliths.

```
┌─────────────────────────────────────────────────┐
│                  ShantiSangha.Api                │
│   Thin host: startup, middleware, controller     │
│   discovery. NO controllers, NO business logic.  │
└────────┬────┬────┬────┬────┬────┬───────────────┘
         │    │    │    │    │    │
         ▼    ▼    ▼    ▼    ▼    ▼
      Goals  Chat  Journal  Wellness  Insights  Identity
      Each domain owns its controllers, services,
      models, data access, DTOs, and jobs.
         │    │    │    │    │    │
         ▼    ▼    ▼    ▼    ▼    ▼
┌─────────────────────────────────────────────────┐
│              ShantiSangha.Shared                 │
│     (ICurrentUser, IEventBus, base models)       │
└─────────────────────────────────────────────────┘
```

**Allowed references:**
- `Api` → any domain project (for DI registration and controller discovery)
- Any domain project → `Shared` only

**Forbidden references:**
- Domain project → another domain project (NEVER)
- `Shared` → any domain project (NEVER)
- Any project → `Api` (NEVER)

If a feature needs data from another domain, it must go through the `IEventBus` — not by adding a project reference.

### Controller Discovery in Program.cs

Since controllers live in domain projects, the API host must discover them from referenced assemblies:

```csharp
// Program.cs — discover controllers from all domain assemblies
builder.Services.AddControllers()
    .AddApplicationPart(typeof(ShantiSangha.Goals.DependencyInjection).Assembly)
    .AddApplicationPart(typeof(ShantiSangha.Chat.DependencyInjection).Assembly)
    .AddApplicationPart(typeof(ShantiSangha.Journal.DependencyInjection).Assembly)
    .AddApplicationPart(typeof(ShantiSangha.Wellness.DependencyInjection).Assembly)
    .AddApplicationPart(typeof(ShantiSangha.Insights.DependencyInjection).Assembly)
    .AddApplicationPart(typeof(ShantiSangha.Identity.DependencyInjection).Assembly);
```

Each domain project's `.csproj` must include the ASP.NET Core framework reference so controllers compile:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <FrameworkReference Include="Microsoft.AspNetCore.App" />
    <ProjectReference Include="..\ShantiSangha.Shared\ShantiSangha.Shared.csproj" />
  </ItemGroup>
</Project>
```

## RESTful Controllers

All API endpoints use standard ASP.NET Core controllers with `[ApiController]` attribute. No Minimal APIs.

### Controller Template

Controllers live in their domain project, not in the API project. The namespace matches the domain.

```csharp
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Goals.Contracts;
using ShantiSangha.Goals.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Goals.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class GoalsController : ControllerBase
{
    private readonly IGoalService _goalService;
    private readonly ICurrentUser _currentUser;

    public GoalsController(IGoalService goalService, ICurrentUser currentUser)
    {
        _goalService = goalService;
        _currentUser = currentUser;
    }

    /// <summary>
    /// Get all goals for the current user.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<GoalResponse>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAll(CancellationToken ct)
    {
        var goals = await _goalService.GetAllAsync(_currentUser.UserId, ct);
        return Ok(goals);
    }

    /// <summary>
    /// Get a specific goal by ID.
    /// </summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(GoalResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var goal = await _goalService.GetByIdAsync(_currentUser.UserId, id, ct);
        if (goal is null) return NotFound();
        return Ok(goal);
    }

    /// <summary>
    /// Create a new goal.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(GoalResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Create([FromBody] CreateGoalRequest request, CancellationToken ct)
    {
        var goal = await _goalService.CreateAsync(_currentUser.UserId, request, ct);
        return CreatedAtAction(nameof(GetById), new { id = goal.Id }, goal);
    }

    /// <summary>
    /// Update an existing goal.
    /// </summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(GoalResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateGoalRequest request, CancellationToken ct)
    {
        var goal = await _goalService.UpdateAsync(_currentUser.UserId, id, request, ct);
        if (goal is null) return NotFound();
        return Ok(goal);
    }

    /// <summary>
    /// Delete a goal.
    /// </summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        var deleted = await _goalService.DeleteAsync(_currentUser.UserId, id, ct);
        if (!deleted) return NotFound();
        return NoContent();
    }
}
```

### RESTful Conventions

Follow these conventions for every controller. They exist because consistent APIs are easier to consume, test, and document.

**HTTP Verbs:**
| Action | Verb | Route | Response |
|--------|------|-------|----------|
| List all | `GET` | `/api/goals` | `200 OK` with array |
| Get one | `GET` | `/api/goals/{id}` | `200 OK` or `404` |
| Create | `POST` | `/api/goals` | `201 Created` with Location header |
| Full update | `PUT` | `/api/goals/{id}` | `200 OK` or `404` |
| Partial update | `PATCH` | `/api/goals/{id}` | `200 OK` or `404` |
| Delete | `DELETE` | `/api/goals/{id}` | `204 No Content` or `404` |

**Sub-resources:**
| Action | Verb | Route |
|--------|------|-------|
| Goal check-ins | `GET` | `/api/goals/{id}/checkins` |
| Create check-in | `POST` | `/api/goals/{id}/checkins` |
| Delete check-in | `DELETE` | `/api/goals/{id}/checkins/{date}` |
| Goal history | `GET` | `/api/goals/{id}/history` |

**Query parameters for filtering/pagination:**
```
GET /api/goals?type=recurring&archived=false
GET /api/journals?page=1&pageSize=20
GET /api/moods?from=2026-01-01&to=2026-03-31
```

**Response envelope — keep it flat, no wrappers:**
```json
// Good — return the resource directly
{ "id": "...", "title": "Meditate daily", "type": "Recurring" }

// Good — return array for lists
[{ "id": "...", "title": "..." }, ...]

// Good — paginated responses use a standard shape
{ "items": [...], "totalCount": 42, "page": 1, "pageSize": 20 }
```

**Status codes:**
- `200 OK` — successful GET, PUT, PATCH
- `201 Created` — successful POST (include `Location` header via `CreatedAtAction`)
- `204 No Content` — successful DELETE
- `400 Bad Request` — validation failure (let `[ApiController]` handle model validation)
- `401 Unauthorized` — missing/invalid JWT
- `404 Not Found` — resource doesn't exist or doesn't belong to user
- `409 Conflict` — duplicate resource (e.g., goal with same title)
- `500 Internal Server Error` — unhandled exception (global error middleware)

## Service Project Pattern

Each domain project follows the same internal structure. This consistency makes it easy to navigate any domain once you know one.

### DependencyInjection.cs (Registration Entry Point)

Every service project exposes a single extension method for registration:

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace ShantiSangha.Goals;

public static class DependencyInjection
{
    public static IServiceCollection AddGoals(this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<GoalsDbContext>(opts =>
            opts.UseNpgsql(connectionString));

        services.AddScoped<IGoalService, GoalService>();

        return services;
    }
}
```

Then in `Program.cs`:
```csharp
builder.Services.AddGoals(connectionString);
builder.Services.AddChat(connectionString);
builder.Services.AddJournal(connectionString);
builder.Services.AddWellness(connectionString);
builder.Services.AddInsights(connectionString);
builder.Services.AddIdentity(connectionString);
```

### Own DbContext Per Domain

Each domain has its own `DbContext` that only knows about its own tables. This is the core of the isolation — no domain can query another domain's tables.

```csharp
using Microsoft.EntityFrameworkCore;

namespace ShantiSangha.Goals.Data;

public class GoalsDbContext : DbContext
{
    public GoalsDbContext(DbContextOptions<GoalsDbContext> options) : base(options) { }

    public DbSet<Goal> Goals => Set<Goal>();
    public DbSet<GoalCheckIn> CheckIns => Set<GoalCheckIn>();
    public DbSet<GoalActivity> Activities => Set<GoalActivity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // All entities in this context share a schema for clarity
        modelBuilder.HasDefaultSchema("goals");

        modelBuilder.Entity<Goal>(e =>
        {
            e.HasIndex(g => g.UserId);
            e.HasIndex(g => new { g.UserId, g.Title }).IsUnique();
        });

        modelBuilder.Entity<GoalCheckIn>(e =>
        {
            e.HasIndex(c => c.GoalId);
            e.HasIndex(c => new { c.GoalId, c.Date }).IsUnique();
        });

        modelBuilder.Entity<GoalActivity>(e =>
        {
            e.HasIndex(a => new { a.GoalId, a.CreatedAt });
        });
    }
}
```

**Important:** Use PostgreSQL schemas to namespace tables per domain:
- `goals.Goals`, `goals.GoalCheckIns`, `goals.GoalActivities`
- `chat.Conversations`, `chat.Messages`
- `journal.Journals`
- `wellness.MoodCheckins`, `wellness.CopingSessions`, `wellness.VoiceEntries`
- `insights.SavedInsights`, `insights.Summaries`
- `identity.Users`, `identity.Profiles`

### Service Interface Pattern

Each service exposes a clean interface with DTOs — never expose EF entities across the boundary.

```csharp
namespace ShantiSangha.Goals.Services;

public interface IGoalService
{
    Task<IReadOnlyList<GoalResponse>> GetAllAsync(Guid userId, CancellationToken ct = default);
    Task<GoalResponse?> GetByIdAsync(Guid userId, Guid goalId, CancellationToken ct = default);
    Task<GoalResponse> CreateAsync(Guid userId, CreateGoalRequest request, CancellationToken ct = default);
    Task<GoalResponse?> UpdateAsync(Guid userId, Guid goalId, UpdateGoalRequest request, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid userId, Guid goalId, CancellationToken ct = default);
}
```

**DTOs live in the domain project's `Contracts/` folder:**
```csharp
namespace ShantiSangha.Goals.Contracts;

public record CreateGoalRequest(
    string Title,
    string Type,
    string? Frequency = null,
    DateOnly? TargetDate = null,
    string? DeeperWhy = null);

public record UpdateGoalRequest(
    string? Title = null,
    bool? Archived = null,
    bool? Completed = null,
    int? Progress = null,
    DateOnly? DueDate = null);

public record GoalResponse(
    Guid Id,
    string Title,
    string Type,
    string? Frequency,
    DateOnly? TargetDate,
    string? DeeperWhy,
    int Progress,
    DateTime CreatedAt,
    DateTime? CompletedAt,
    DateTime? ArchivedAt);
```

## Cross-Domain Communication

When one domain needs to notify another (e.g., Chat creates a summary that Insights needs to index), use an in-process event bus — not direct project references.

### IEventBus (in Shared)

```csharp
namespace ShantiSangha.Shared.Interfaces;

public interface IEventBus
{
    Task PublishAsync<T>(T @event, CancellationToken ct = default) where T : class;
    void Subscribe<T>(Func<T, CancellationToken, Task> handler) where T : class;
}
```

### Example: Chat publishes, Insights subscribes

```csharp
// In ShantiSangha.Chat — after generating a summary
await _eventBus.PublishAsync(new SummaryCreatedEvent(
    UserId: userId,
    SourceType: "Conversation",
    SourceId: conversationId,
    Content: summaryText), ct);

// In ShantiSangha.Insights — DependencyInjection.cs
eventBus.Subscribe<SummaryCreatedEvent>(async (e, ct) =>
{
    await insightService.ExtractFromSummaryAsync(e.UserId, e.SourceType, e.SourceId, e.Content, ct);
});
```

**Event contracts live in Shared:**
```csharp
namespace ShantiSangha.Shared.Events;

public record SummaryCreatedEvent(Guid UserId, string SourceType, Guid SourceId, string Content);
public record VoiceTranscribedEvent(Guid UserId, Guid VoiceEntryId, string Transcript);
public record UserCreatedEvent(Guid UserId, string Email);
```

This keeps the boundary clean: Chat doesn't know Insights exists, it just publishes an event. Tomorrow you could swap the in-process bus for RabbitMQ/Kafka and extract Insights into a real microservice with zero changes to Chat.

## Database Migration Strategy

With separate DbContexts, each domain manages its own migrations independently.

```bash
# Generate migration for a specific domain
dotnet ef migrations add AddCategoryToGoals \
  --project ShantiSangha.Goals \
  --startup-project ShantiSangha.Api \
  --context GoalsDbContext

# Apply all migrations on startup (Program.cs)
using var scope = app.Services.CreateScope();
await scope.ServiceProvider.GetRequiredService<GoalsDbContext>().Database.MigrateAsync();
await scope.ServiceProvider.GetRequiredService<ChatDbContext>().Database.MigrateAsync();
await scope.ServiceProvider.GetRequiredService<JournalDbContext>().Database.MigrateAsync();
// ... etc
```

Each domain's migrations are in its own `Migrations/` folder. No conflicts when two developers are adding migrations to different domains.

## Checklist When Adding a New Feature

1. **Which domain does it belong to?** If it doesn't fit an existing one, create a new project.
2. **Controller goes in the domain project.** Not in the API project. Namespace: `ShantiSangha.{Domain}.Controllers`.
3. **Does it need data from another domain?** Use the event bus — never add a cross-project reference.
4. **Controller or sub-resource?** New entity = new controller. Sub-entity = sub-resource on existing controller.
5. **RESTful verbs?** GET for reads, POST for creates, PUT/PATCH for updates, DELETE for deletes. No `POST /goals/{id}/reset` — use `DELETE /goals/{id}/checkins` or `PUT /goals/{id}` with a reset flag.
6. **DTOs in Contracts/.** Never return EF entities from controllers. Map to request/response records in the `Contracts/` folder.
7. **Own DbContext?** New domain = new DbContext with its own schema and migrations.
8. **Registration?** Add `builder.Services.AddNewDomain(connectionString)` and `.AddApplicationPart()` in Program.cs.
9. **CancellationToken?** Pass it through every async call.
10. **FrameworkReference?** New domain project needs `<FrameworkReference Include="Microsoft.AspNetCore.App" />` in .csproj.

## What NOT to Do

- **No `AppDbContext` god-object** — each domain owns its data exclusively
- **No Minimal APIs** — use `[ApiController]` controllers with proper routing attributes
- **No service-to-service project references** — use IEventBus for cross-domain communication
- **No EF entities in API responses** — always map to DTOs/records
- **No business logic in controllers** — controllers are thin, services do the work
- **No `DateTime.Now`** — use `DateTime.UtcNow` or inject `TimeProvider`
- **No catching generic exceptions in services** — let them bubble to the global error handler
- **No hardcoded strings for event types** — use strongly-typed event records
