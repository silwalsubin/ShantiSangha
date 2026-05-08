namespace ShantiSangha.Friends.Models;

/// <summary>
/// Directional grant: GrantorUserId has chosen to share their birth
/// details with GranteeUserId for the purpose of generating the
/// grantee's private Vedic chart reading. The grantee's raw birth data
/// never appears in any UI — only the synthesized reading. The grant
/// is one-way; reciprocation is a separate row. Untoggling deletes
/// the row, which invalidates the grantee's reading and chat history
/// about this person.
/// </summary>
public class BirthDetailShare
{
    public Guid Id { get; set; }
    public Guid GrantorUserId { get; set; }
    public Guid GranteeUserId { get; set; }
    public DateTime GrantedAt { get; set; }
}
