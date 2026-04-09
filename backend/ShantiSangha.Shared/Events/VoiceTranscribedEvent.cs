namespace ShantiSangha.Shared.Events;

public record VoiceTranscribedEvent(
    Guid VoiceEntryId,
    Guid UserId,
    string Transcript,
    DateTime CreatedAt);
