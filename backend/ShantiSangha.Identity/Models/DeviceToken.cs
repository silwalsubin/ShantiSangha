namespace ShantiSangha.Identity.Models;

public class DeviceToken
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Token { get; set; } = string.Empty;
    public string Platform { get; set; } = "ios";
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
