namespace ShantiSangha.Shared.Models;

public record SemanticSearchResultDto(
    Guid Id,
    string Type,
    string Content,
    double Distance,
    DateTime CreatedAt);
