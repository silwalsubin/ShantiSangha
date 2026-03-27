namespace ShantiSangha.Core.Models;

public class User
{
    public Guid Id { get; set; }
    public string ClerkId { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public Profile? Profile { get; set; }
    public ICollection<Conversation> Conversations { get; set; } = [];
    public ICollection<Journal> Journals { get; set; } = [];
    public ICollection<MoodCheckin> MoodCheckins { get; set; } = [];
    public ICollection<CopingSession> CopingSessions { get; set; } = [];
    public ICollection<SavedInsight> SavedInsights { get; set; } = [];
    public ICollection<VoiceEntry> VoiceEntries { get; set; } = [];
}
