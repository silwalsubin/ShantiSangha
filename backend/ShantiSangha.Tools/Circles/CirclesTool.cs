using System.ComponentModel;
using Microsoft.SemanticKernel;
using ModelContextProtocol.Server;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Services;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Tools.Internal;

namespace ShantiSangha.Tools.Circles;

[McpServerToolType]
public sealed class CirclesTool(IConnectionsService connections, ICurrentUser currentUser)
{
    [McpServerTool(Name = "list_connections")]
    [KernelFunction("list_connections")]
    [Description(
        "Return everyone in the user's circle — the people they keep track of, " +
        "with their display name and which sub-circles (inner / close / outer, " +
        "or any custom labels) they belong to. " +
        "Use this when the user asks who they're connected to, who's in their circle, " +
        "or before referring to a person by name. " +
        "Never read raw ids back to the user — use display names.")]
    public async Task<object> ListConnections(CancellationToken ct = default)
    {
        var user = await RequireUserAsync();
        var all = await connections.ListAsync(user.Id, ct);

        var projected = all.Select(Project).ToList();
        return new { connections = projected, count = projected.Count };
    }

    [McpServerTool(Name = "add_connection")]
    [KernelFunction("add_connection")]
    [Description(
        "Add a new person to the user's circle. Use when the user says " +
        "things like 'add Aarav to my circle' or 'I want to track my " +
        "cousin Priya'. The circle parameter is the sub-grouping (e.g. " +
        "'close', 'inner', 'outer', or any free-form label the user mentions). " +
        "If unsure which circle, pass null — the user can move them later.")]
    public async Task<object> AddConnection(
        [Description("The person's display name. Required.")] string name,
        [Description("Optional sub-circle label, e.g. 'close', 'inner', 'outer', or any free-form tag. Comma-separated to put them in multiple circles.")] string? circle = null,
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();

        if (string.IsNullOrWhiteSpace(name))
            return Error("A name is required to add someone to your circle.");

        var circles = SplitCircles(circle);

        try
        {
            var created = await connections.CreateLocalAsync(
                user.Id,
                new CreateConnectionRequest(DisplayName: name.Trim(), Circles: circles),
                ct);

            return new { created = Project(created) };
        }
        catch (Exception ex)
        {
            return Error(ex.Message);
        }
    }

    [McpServerTool(Name = "update_connection_circles")]
    [KernelFunction("update_connection_circles")]
    [Description(
        "Change which sub-circles a person belongs to. The user refers to " +
        "them by name — fuzzy matching is supported. If the name is " +
        "ambiguous (matches more than one person), this tool returns an " +
        "ambiguity list — present the choices to the user and ask which " +
        "they meant before calling again with a more specific name.")]
    public async Task<object> UpdateConnectionCircles(
        [Description("Name or partial name of the person to update.")] string name,
        [Description("New sub-circle label(s). Comma-separated for multiple. Pass an empty string to remove from all sub-circles.")] string circles,
        CancellationToken ct = default)
    {
        var user = await RequireUserAsync();

        var all = await connections.ListAsync(user.Id, ct);
        var lookup = LabeledLookup.FindByLabel(all, c => c.Person.DisplayName, name);

        if (lookup.Outcome == LookupOutcome.None)
            return Error($"No one in your circle matches '{name}'.");
        if (lookup.Outcome == LookupOutcome.Ambiguous)
            return Ambiguous(lookup.Candidates);

        var newCircles = SplitCircles(circles) ?? new List<string>();

        try
        {
            var updated = await connections.UpdateAsync(
                user.Id, lookup.Match!.Id,
                new UpdateConnectionRequest(Circles: newCircles),
                ct);

            return updated is null
                ? Error("That person is no longer in your circle.")
                : new { updated = Project(updated) };
        }
        catch (Exception ex)
        {
            return Error(ex.Message);
        }
    }

    private async Task<CurrentUserInfo> RequireUserAsync()
    {
        var user = await currentUser.GetAsync();
        return user ?? throw new UnauthorizedAccessException("No authenticated user on this request.");
    }

    private static List<string>? SplitCircles(string? input)
    {
        if (input is null) return null;
        var parts = input
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(s => s.Length > 0)
            .ToList();
        return parts;
    }

    private static object Project(ConnectionResponse c) => new
    {
        id = c.Id,
        name = c.Person.DisplayName,
        nickname = c.Nickname,
        circles = c.Circles,
        messageable = c.Messageable,
    };

    private static object Error(string message) => new { error = message };

    private static object Ambiguous(IReadOnlyList<ConnectionResponse> candidates) => new
    {
        ambiguous = true,
        message = "More than one person matches that name. Ask the user which they meant.",
        candidates = candidates.Select(Project).ToList(),
    };
}
