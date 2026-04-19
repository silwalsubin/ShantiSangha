using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace ShantiSangha.Jyotish.Controllers;

/// <summary>
/// Gates an endpoint behind a shared admin key. Requires the caller to pass
/// `X-Admin-Key` matching the JYOTISH_ADMIN_KEY env var. Fail-closed: if the
/// env var is unset or empty, every request is rejected.
///
/// Intended for the corpus ingestion endpoints during bootstrap. Will be
/// replaced with a Clerk role-based policy once the admin role exists.
/// </summary>
public class AdminKeyAuthorizeAttribute : Attribute, IAsyncAuthorizationFilter
{
    public const string HeaderName = "X-Admin-Key";
    public const string ConfigKey = "JYOTISH_ADMIN_KEY";

    public Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        var config = context.HttpContext.RequestServices.GetRequiredService<IConfiguration>();
        var expected = config[ConfigKey];

        if (string.IsNullOrWhiteSpace(expected))
        {
            context.Result = new ObjectResult(new { error = "ingest endpoint is not configured" })
                { StatusCode = 503 };
            return Task.CompletedTask;
        }

        if (!context.HttpContext.Request.Headers.TryGetValue(HeaderName, out var supplied)
            || !string.Equals(supplied.ToString(), expected, StringComparison.Ordinal))
        {
            context.Result = new UnauthorizedResult();
            return Task.CompletedTask;
        }

        return Task.CompletedTask;
    }
}
