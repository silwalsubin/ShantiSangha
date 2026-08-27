using System.Runtime.CompilerServices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using ShantiSangha.Agent.Data;
using ShantiSangha.Agent.Contracts;
using ShantiSangha.Agent.Models;
using ShantiSangha.Reminders.Contracts;
using ShantiSangha.Reminders.Services;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Tools.AgentFeedback;
using ShantiSangha.Tools.Circles;
using ShantiSangha.Tools.Reminders;

namespace ShantiSangha.Agent.AI;

public class AgentOrchestrator(
    Kernel kernel,
    IServiceProvider services,
    ICurrentUser currentUser,
    IProfileQueryService profileQuery,
    IMemoryQueryService memoryQuery,
    IReminderService reminderService,
    RemindersListSink remindersSink,
    AgentTurnContext turnContext,
    AgentDbContext db,
    Storage.AgentMediaStorage mediaStorage,
    QuickActionSuggester quickActions)
{
    private static readonly TimeSpan LoopTimeout = TimeSpan.FromSeconds(45);
    private const int HistoryReplayCount = 20;

    public async IAsyncEnumerable<AgentStreamEvent> StreamAsync(
        string userMessage,
        byte[]? imageBytes = null,
        string? imageContentType = null,
        Guid? reminderId = null,
        IReadOnlyList<AgentChatTurn>? clientHistory = null,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var user = await currentUser.GetAsync()
            ?? throw new UnauthorizedAccessException("No authenticated user on this request.");

        string? displayName = null;
        try { displayName = await profileQuery.GetDisplayNameAsync(user.Id, cancellationToken); }
        catch { /* best-effort */ }

        string? timezone = null;
        try { timezone = await profileQuery.GetTimezoneAsync(user.Id, cancellationToken); }
        catch { /* best-effort */ }

        var trimmed = userMessage.Trim();

        // Scoped mode: the turn is about one specific reminder ("Plan with
        // assistant"). We load it for grounding, and the whole exchange is
        // ephemeral — no persistence, no global history replay — so it stays
        // out of the main assistant thread. Continuity comes from the
        // reminder's notes, which the assistant reads + rewrites via a tool.
        ReminderResponse? scopedReminder = null;
        if (reminderId is not null)
        {
            scopedReminder = await reminderService.GetByIdAsync(
                reminderId.Value, user.Id, date: null, cancellationToken);
        }
        var scoped = scopedReminder is not null;

        // Memory awareness (unscoped turns only — reminder-planning stays
        // focused). Best-effort like the profile lookups above.
        string? memories = null;
        if (!scoped)
        {
            try
            {
                var hits = await memoryQuery.SearchAsync(user.Id, trimmed, topK: 4, ct: cancellationToken);
                if (hits.Count > 0)
                {
                    memories = string.Join("\n", hits.Select(h =>
                    {
                        var flat = h.Content.ReplaceLineEndings(" ").Trim();
                        if (flat.Length > 300) flat = flat[..300] + "…";
                        return $"- [{(h.SourceType == "journal" ? "journal entry" : "reflection")}, {h.OccurredAt:MMMM d, yyyy}] {flat}";
                    }));
                }
            }
            catch { /* best-effort */ }
        }

        Guid userTurnId = Guid.Empty;
        if (scoped)
        {
            // Point the notes tool at this reminder; no persisted message id.
            turnContext.ScopedReminderId = reminderId;
        }
        else
        {
            // Persist the user turn FIRST so it survives an LLM failure
            // mid-stream. The image bytes are NOT persisted (they inform this
            // turn only); a text marker keeps history readable with no caption.
            var persistedContent = trimmed.Length > 0
                ? trimmed
                : (imageBytes is not null ? "[Shared a photo]" : trimmed);

            // Persist the photo to the media bucket so it survives a chat
            // reopen. Best-effort: a failed upload still lets the image inform
            // THIS turn's vision call below — it just won't replay later.
            string? imageObjectKey = null;
            if (imageBytes is not null)
            {
                imageObjectKey = $"agent/{user.Id}/{Guid.NewGuid()}.jpg";
                try
                {
                    await mediaStorage.UploadAsync(
                        imageObjectKey, imageBytes, imageContentType ?? "image/jpeg", cancellationToken);
                }
                catch
                {
                    imageObjectKey = null;
                }
            }

            userTurnId = Guid.NewGuid();
            db.AgentMessages.Add(new AgentMessage
            {
                Id = userTurnId,
                UserId = user.Id,
                Role = AgentMessageRole.User,
                Content = persistedContent,
                ImageObjectKey = imageObjectKey,
                CreatedAt = DateTime.UtcNow,
            });
            await db.SaveChangesAsync(cancellationToken);

            // Expose the user-turn id so AgentFeedbackTool can attribute any
            // feedback the LLM records during this turn back to the exact
            // message that triggered it.
            turnContext.CurrentUserMessageId = userTurnId;
        }

        var scopedKernel = kernel.Clone();
        scopedKernel.Plugins.AddFromObject(
            services.GetRequiredService<RemindersTool>(),
            pluginName: "reminders");
        scopedKernel.Plugins.AddFromObject(
            services.GetRequiredService<CirclesTool>(),
            pluginName: "circles");
        scopedKernel.Plugins.AddFromObject(
            services.GetRequiredService<AgentFeedbackTool>(),
            pluginName: "agent_feedback");

        var today = UserClock.TodayFor(timezone);
        var systemPrompt = scoped
            ? AgentSystemPrompt.BuildForReminder(today, displayName, scopedReminder!)
            : AgentSystemPrompt.Build(today, displayName, memories);
        var history = new ChatHistory(systemPrompt);

        if (scoped)
        {
            // Replay the in-session transcript the client sent (oldest-first,
            // excluding the current message). Scoped chats persist nothing
            // server-side, so this is the only source of within-session memory.
            if (clientHistory is not null)
            {
                foreach (var turn in clientHistory)
                {
                    if (string.IsNullOrWhiteSpace(turn.Content)) continue;
                    if (string.Equals(turn.Role, "assistant", StringComparison.OrdinalIgnoreCase))
                        history.AddAssistantMessage(turn.Content);
                    else
                        history.AddUserMessage(turn.Content);
                }
            }

            // The current turn, grounded by the scoped system prompt (which
            // carries the reminder + its current notes).
            if (imageBytes is not null)
            {
                var items = new ChatMessageContentItemCollection
                {
                    new TextContent(trimmed.Length > 0 ? trimmed : "Here's an image — take a look at what's in it."),
                    new ImageContent(imageBytes, imageContentType ?? "image/jpeg")
                };
                history.AddUserMessage(items);
            }
            else
            {
                history.AddUserMessage(trimmed.Length > 0 ? trimmed : "Help me plan this.");
            }
        }
        else
        {
            // Replay the last N turns (including the user message we just saved)
            // so the LLM can resolve references like "move that to next Friday".
            var recent = await db.AgentMessages
                .Where(m => m.UserId == user.Id)
                .OrderByDescending(m => m.CreatedAt)
                .Take(HistoryReplayCount)
                .OrderBy(m => m.CreatedAt)
                .ToListAsync(cancellationToken);

            foreach (var msg in recent)
            {
                if (msg.Role == AgentMessageRole.User)
                {
                    // Attach the photo to the current turn only, as a multimodal
                    // message (text + image), so GPT-4o vision can see it. Prior
                    // turns replay as text — we never stored their images.
                    if (msg.Id == userTurnId && imageBytes is not null)
                    {
                        var items = new ChatMessageContentItemCollection
                        {
                            new TextContent(trimmed.Length > 0 ? trimmed : "Here's an image — take a look at what's in it."),
                            new ImageContent(imageBytes, imageContentType ?? "image/jpeg")
                        };
                        history.AddUserMessage(items);
                    }
                    else
                    {
                        history.AddUserMessage(msg.Content);
                    }
                }
                else
                {
                    history.AddAssistantMessage(msg.Content);
                }
            }
        }

        var settings = new OpenAIPromptExecutionSettings
        {
            FunctionChoiceBehavior = FunctionChoiceBehavior.Auto(),
            Temperature = 0.2,
        };

        var completion = scopedKernel.GetRequiredService<IChatCompletionService>(AiModels.SmartServiceId);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(LoopTimeout);

        var assembled = new System.Text.StringBuilder();
        await foreach (var chunk in completion.GetStreamingChatMessageContentsAsync(
            history, settings, scopedKernel, timeout.Token))
        {
            var text = chunk.Content;
            if (string.IsNullOrEmpty(text)) continue;

            // Semantic Kernel's auto-invoke produces two assistant rounds
            // around a tool call (narration → tool → narration). The
            // streaming joins them without whitespace, so we get
            // "Let me do that now.Your reminder…". Detect the seam — prior
            // ends in sentence punctuation, next starts uppercase with no
            // leading whitespace — and insert a paragraph break.
            if (NeedsRoundBreak(assembled, text))
            {
                assembled.Append("\n\n");
                yield return new AgentStreamEvent.Text("\n\n");
            }

            assembled.Append(text);
            yield return new AgentStreamEvent.Text(text);
        }

        // After the LLM finishes (and any tool calls have completed), drain
        // the sink to learn which reminders the assistant referenced. Look
        // them up live so the cards reflect current state, not whatever the
        // LLM saw — by the time the user reads the reply, the relevant
        // truth is now, not the snapshot mid-loop.
        var attachedReminderIds = remindersSink.Drain();
        IReadOnlyList<ReminderResponse> attachedReminders = Array.Empty<ReminderResponse>();
        if (attachedReminderIds.Count > 0)
        {
            attachedReminders = await LookupRemindersAsync(user.Id, attachedReminderIds, cancellationToken);
            if (attachedReminders.Count > 0)
            {
                yield return new AgentStreamEvent.Reminders(attachedReminders);
            }
        }

        var assistantContent = assembled.ToString().Trim();

        // Cheap second pass: offer up to 3 tappable follow-ups so a lazy-typing
        // user can act with one tap. Runs after the reply has fully streamed, so
        // it never delays the prose; returns nothing on most turns. Ephemeral —
        // we don't persist chips, so they don't reappear on history reopen.
        if (assistantContent.Length > 0)
        {
            var actions = await quickActions.SuggestAsync(trimmed, assistantContent, cancellationToken);
            if (actions.Count > 0)
            {
                yield return new AgentStreamEvent.QuickActions(actions);
            }
        }

        // Scoped planning turns are ephemeral — don't persist to the main
        // thread. The durable artifact is the reminder's notes.
        if (!scoped && assistantContent.Length > 0)
        {
            db.AgentMessages.Add(new AgentMessage
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                Role = AgentMessageRole.Assistant,
                Content = assistantContent,
                Attachments = AgentMessageAttachmentsCodec.Encode(
                    new AgentMessageAttachments(
                        attachedReminders.Count > 0
                            ? attachedReminders.Select(r => r.Id).ToList()
                            : null)),
                CreatedAt = DateTime.UtcNow,
            });
            await db.SaveChangesAsync(CancellationToken.None);
        }
    }

    private async Task<IReadOnlyList<ReminderResponse>> LookupRemindersAsync(
        Guid userId, IReadOnlyList<Guid> ids, CancellationToken ct)
    {
        if (ids.Count == 0) return Array.Empty<ReminderResponse>();
        var all = await reminderService.ListAsync(userId, connectionId: null, date: null, ct);
        var byId = all.ToDictionary(r => r.Id);
        var ordered = new List<ReminderResponse>(ids.Count);
        foreach (var id in ids)
        {
            if (byId.TryGetValue(id, out var r)) ordered.Add(r);
        }
        return ordered;
    }

    private static bool NeedsRoundBreak(System.Text.StringBuilder soFar, string next)
    {
        if (soFar.Length == 0 || next.Length == 0) return false;
        var lastChar = soFar[soFar.Length - 1];
        if (lastChar != '.' && lastChar != '!' && lastChar != '?') return false;
        var firstChar = next[0];
        return char.IsLetter(firstChar) && char.IsUpper(firstChar);
    }
}
