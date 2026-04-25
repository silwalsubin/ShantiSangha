using System.Security.Cryptography;

namespace ShantiSangha.Friends.Services;

public static class InvitationTokenGenerator
{
    public static string Generate()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        return Convert.ToBase64String(bytes)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');
    }
}
