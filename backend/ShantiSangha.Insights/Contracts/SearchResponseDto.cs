using ShantiSangha.Shared.Models;

namespace ShantiSangha.Insights.Contracts;

public record SearchResponseDto(
    string Query,
    string Type,
    IReadOnlyList<SemanticSearchResultDto> Results);
