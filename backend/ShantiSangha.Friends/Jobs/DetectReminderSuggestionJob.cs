using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Detection;
using ShantiSangha.Friends.Models;
using ShantiSangha.Friends.Realtime;

namespace ShantiSangha.Friends.Jobs;

/// <summary>
/// Stage 1 → Stage 2 → DB insert → realtime fan-out.
///
/// Runs once per text friend-message. Cheap regex pre-filter discards
/// most messages before the LLM ever sees them. On a high-confidence
/// extraction we write two FriendMessageSuggestion rows (one per
/// conversation participant) and immediately publish a
/// `suggestion_ready` event over the chat realtime hub so connected
/// iOS clients can attach the card inline without a refresh.
/// </summary>
public class DetectReminderSuggestionJob(
    FriendsDbContext db,
    IReminderExtractor extractor,
    IChatRealtimeHub realtime,
    ILogger<DetectReminderSuggestionJob> logger)
{
    public async Task RunAsync(Guid messageId)
    {
        var msg = await db.Messages.AsNoTracking()
            .FirstOrDefaultAsync(m => m.Id == messageId);
        if (msg is null) return;
        if (msg.Kind != FriendMessageKind.Text) return;
        if (string.IsNullOrWhiteSpace(msg.Body)) return;

        // Stage 1 — free regex filter. ~99% of messages stop here.
        if (!RegexPreFilter.LooksReminderShaped(msg.Body)) return;

        // Stage 2 — LLM call. Costs ~$0.0001 per fire.
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        ReminderExtraction? extraction;
        try
        {
            extraction = await extractor.ExtractAsync(msg.Body, today);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Reminder extraction failed for message {MessageId}", messageId);
            return;
        }
        if (extraction is null) return;

        // Resolve both participants of the conversation. The detector
        // writes one row per participant so each side has independent
        // dismiss / accept state.
        var friendship = await db.Friendships.AsNoTracking()
            .FirstOrDefaultAsync(f => f.Id == msg.FriendshipId);
        if (friendship is null) return;

        var participants = new[] { friendship.UserAId, friendship.UserBId };

        foreach (var userId in participants)
        {
            // Idempotency — if a previous run already inserted a row for
            // this (message, user), skip. The unique index would reject
            // it anyway, but checking is friendlier than catching.
            var exists = await db.MessageSuggestions
                .AnyAsync(s => s.FriendMessageId == messageId && s.UserId == userId);
            if (exists) continue;

            db.MessageSuggestions.Add(new FriendMessageSuggestion
            {
                Id = Guid.NewGuid(),
                FriendMessageId = messageId,
                UserId = userId,
                Kind = FriendMessageSuggestionKind.Reminder,
                Label = extraction.Label,
                WhenDate = extraction.Date,
                Recurrence = extraction.Recurrence,
                CreatedAt = DateTime.UtcNow,
            });
        }
        await db.SaveChangesAsync();

        // Realtime — fan a `suggestion_ready` event to every WebSocket
        // subscribed to this conversation. Each client looks up the
        // message by id and attaches the card inline. Best-effort.
        try
        {
            await realtime.PublishAsync(msg.FriendshipId, "suggestion_ready", new
            {
                conversationId = msg.FriendshipId,
                messageId,
                label = extraction.Label,
                date = extraction.Date.ToString("yyyy-MM-dd"),
                recurrence = extraction.Recurrence,
            });
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Realtime suggestion_ready publish failed for message {MessageId}", messageId);
        }
    }
}
