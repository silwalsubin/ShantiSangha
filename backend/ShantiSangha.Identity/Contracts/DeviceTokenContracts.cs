namespace ShantiSangha.Identity.Contracts;

public record RegisterDeviceTokenRequest(string Token, string Platform = "ios");
