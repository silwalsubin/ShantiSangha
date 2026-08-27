using System.Text.Json;
using System.Text.Json.Serialization;

namespace ShantiSangha.Agent.Models;

/// <summary>
/// Shape of the JSON the assistant stores in the unified store's
/// Message.MetadataJson: the reminders a reply referenced and/or the S3 key
/// of a photo shared on a user turn. Superset of the legacy
/// AgentMessageAttachments shape, so migrated rows decode unchanged.
/// </summary>
public sealed record AgentMessageMetadata(
    [property: JsonPropertyName("reminderIds")] IReadOnlyList<Guid>? ReminderIds = null,
    [property: JsonPropertyName("imageObjectKey")] string? ImageObjectKey = null);

public static class AgentMessageMetadataCodec
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static string? Encode(AgentMessageMetadata value)
    {
        var hasReminders = value.ReminderIds is { Count: > 0 };
        if (!hasReminders && string.IsNullOrWhiteSpace(value.ImageObjectKey)) return null;
        return JsonSerializer.Serialize(
            hasReminders ? value : value with { ReminderIds = null }, Options);
    }

    public static AgentMessageMetadata? Decode(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize<AgentMessageMetadata>(json, Options); }
        catch { return null; }
    }
}
