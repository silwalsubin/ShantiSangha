using Xunit;

namespace ShantiSangha.Jyotish.Tests;

/// <summary>
/// The Jyotish corpus moved from an in-memory JSON file to a pgvector-backed
/// Postgres store. These tests used to validate the embedded-resource loader
/// and need to be rewritten as integration tests against a real database.
///
/// TODO: rebuild as integration tests using WebApplicationFactory + Testcontainers
/// for Postgres with pgvector, or an EF Core in-memory provider stub.
/// </summary>
public class JyotishKnowledgeServiceTests
{
    [Fact(Skip = "Pending integration-test rewrite against DB-backed service")]
    public void PendingRewrite() { }
}
