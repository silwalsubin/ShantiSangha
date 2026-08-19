namespace ShantiSangha.Shared.Models;

/// One retrieved memory fragment. `OccurredAt` is when the user originally
/// wrote it (journal CreatedAt / message CreatedAt), so companion surfaces can
/// make dated callbacks ("back in July you wrote…").
public record MemoryHit(
    string SourceType,
    Guid SourceId,
    string Content,
    DateTime OccurredAt,
    double Distance);
