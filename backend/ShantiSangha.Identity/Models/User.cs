namespace ShantiSangha.Identity.Models;

public class User
{
    public Guid Id { get; set; }
    public string ClerkId { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public Profile? Profile { get; set; }
}
