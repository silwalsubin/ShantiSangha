using System.Text.Json;
using System.Text.Json.Serialization;

namespace ShantiSangha.Agent.Models;

/// <summary>
/// Shape of the JSON stored in <see cref="AgentMessage.Attachments"/>.
/// Currently holds reminder IDs only; future tool surfaces (circles,
/// journals) can add sibling arrays without a schema bump.
/// </summary>
public sealed record AgentMessageAttachments(
    [property: JsonPropertyName("reminderIds")] IReadOnlyList<Guid>? ReminderIds);

public static class AgentMessageAttachmentsCodec
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static string? Encode(AgentMessageAttachments value)
    {
        if (value.ReminderIds is null || value.ReminderIds.Count == 0) return null;
        return JsonSerializer.Serialize(value, Options);
    }

    public static AgentMessageAttachments? Decode(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize<AgentMessageAttachments>(json, Options); }
        catch { return null; }
    }
}
