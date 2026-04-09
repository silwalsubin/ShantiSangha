namespace ShantiSangha.Shared.Interfaces;

public record CurrentUserInfo(Guid Id, string Email);

public interface ICurrentUser
{
    Task<CurrentUserInfo?> GetAsync();
}
