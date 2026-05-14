namespace ShantiSangha.Agent.Models;

public enum AgentMessageRole { User, Assistant }

public class AgentMessage
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public AgentMessageRole Role { get; set; }
    public string Content { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
