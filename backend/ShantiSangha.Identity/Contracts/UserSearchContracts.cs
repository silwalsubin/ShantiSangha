namespace ShantiSangha.Identity.Contracts;

/// <summary>
/// One row in a user-search response. `AvatarUrl` is a short-lived presigned
/// GET URL generated at read time (same lifetime as the /me avatar URL —
/// ~1 hour) and may be null if the user hasn't uploaded an avatar or if URL
/// presigning failed. Clients fall back to a default initials circle in
/// either case.
/// </summary>
public record UserSearchResult(
    Guid UserId,
    string DisplayName,
    string? Country,
    string? State,
    string? City,
    string? AvatarKey,
    string? AvatarUrl);

public record UserSearchPage(
    int Page,
    int PageSize,
    int TotalCount,
    bool HasMore,
    List<UserSearchResult> Results);
