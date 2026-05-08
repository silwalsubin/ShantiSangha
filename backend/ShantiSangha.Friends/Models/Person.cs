namespace ShantiSangha.Friends.Models;

/// The "who" — biographical identity for a person someone has in their
/// circle. When `UserId` is set this Person IS a ShantiSangha user and
/// the row is a thin pointer; biographical fields fall back to the
/// user's `Identity.Profile` at query time. When `UserId` is null the
/// Person is local — the owner who created the corresponding
/// `Connection` row owns this Person too, and these fields are the
/// canonical truth.
public class Person
{
    public Guid Id { get; set; }
    public Guid? UserId { get; set; }
    public string DisplayName { get; set; } = string.Empty;
    public DateOnly? BirthDate { get; set; }
    public string? PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string? Country { get; set; }
    public string? State { get; set; }
    public string? City { get; set; }
    public string? Address { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
