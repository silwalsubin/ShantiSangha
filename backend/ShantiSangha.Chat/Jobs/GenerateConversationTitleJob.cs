using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Models;

namespace ShantiSangha.Chat.Jobs;

public class GenerateConversationTitleJob(
    ChatDbContext db,
    Kernel kernel,
    ILogger<GenerateConversationTitleJob> logger)
{
    public async Task RunAsync(Guid conversationId)
    {
        var conversation = await db.Conversations.FindAsync(conversationId);
        if (conversation is null) return;

        // Don't overwrite an existing title
        if (!string.IsNullOrWhiteSpace(conversation.Title)) return;

        var messages = await db.Messages
            .Where(m => m.ConversationId == conversationId)
            .OrderBy(m => m.CreatedAt)
            .Take(4)
            .ToListAsync();

        var userMessages = messages.Where(m => m.Role == MessageRole.User).ToList();
        if (userMessages.Count == 0) return;

        try
        {
            var chatCompletion = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory("""
                Generate a short, poetic title (3-6 words) for a spiritual conversation.
                The title should capture the essence of what the person is reflecting on.
                Use lowercase. No quotes. No punctuation at the end.
                Examples: "on patience and letting go", "finding peace in uncertainty",
                "the weight of expectations", "returning to stillness".
                Respond with ONLY the title, nothing else.
                """);

            var userContent = string.Join("\n", userMessages.Select(m => m.Content));
            history.AddUserMessage(userContent);

            var result = await chatCompletion.GetChatMessageContentAsync(history);
            var title = result.Content?.Trim().Trim('"').Trim();

            if (!string.IsNullOrWhiteSpace(title))
            {
                conversation.Title = title;
                await db.SaveChangesAsync();
                logger.LogDebug("Generated title for conversation {Id}: {Title}", conversationId, title);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate title for conversation {Id}", conversationId);
        }
    }
}
