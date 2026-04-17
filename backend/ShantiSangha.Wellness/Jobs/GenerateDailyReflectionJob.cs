using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Jobs;

public class GenerateDailyReflectionJob(
    WellnessDbContext db,
    Kernel kernel,
    IGoalQueryService goalQuery,
    ISummaryQueryService summaryQuery,
    IInsightQueryService insightQuery,
    IProfileQueryService profileQuery,
    IJyotishContextService jyotishService,
    IPushNotificationService pushService,
    ILogger<GenerateDailyReflectionJob> logger)
{
    public async Task RunAsync(Guid userId, DateOnly? localDate = null)
    {
        var today = localDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        var exists = await db.DailyReflections.AnyAsync(r => r.UserId == userId && r.Date == today);
        if (exists) return;

        try
        {
            var displayName = await profileQuery.GetDisplayNameAsync(userId);
            var goals = await goalQuery.GetActiveGoalsForContextAsync(userId, today);
            var summaries = await summaryQuery.GetRecentSummariesAsync(userId, 5);
            var journalSummaries = await summaryQuery.GetRecentJournalSummariesAsync(userId, 5);
            var insights = await insightQuery.GetRecentInsightsAsync(userId, 5);

            // Get previous reflections — now used for CONTINUITY, not just deduplication
            var previousReflections = await db.DailyReflections
                .Where(r => r.UserId == userId)
                .OrderByDescending(r => r.Date)
                .Take(5)
                .Select(r => new PreviousReflection(r.Content, r.Type, r.Date))
                .ToListAsync();

            // Determine today's narrative mode
            var reflectionType = DetermineReflectionType(previousReflections);

            // Build rich context
            var contextParts = new List<string>();

            if (displayName is not null)
                contextParts.Add($"Their name is {displayName}.");

            // Goals with pattern data
            var milestoneThresholds = new HashSet<int> { 7, 14, 30, 60, 100, 365 };
            var milestonesHitToday = new List<string>();
            foreach (var g in goals)
            {
                var streak = g.CurrentStreak > 0 ? $" (current streak: {g.CurrentStreak} days, longest: {g.LongestStreak})" : " (no active streak)";
                var why = !string.IsNullOrWhiteSpace(g.DeeperWhy) ? $" Their deeper why: \"{g.DeeperWhy}\"" : "";
                var checkedIn = g.CheckedInToday switch
                {
                    true => " — completed today",
                    false => " — not yet done today",
                    _ => ""
                };
                contextParts.Add($"- {g.Type} goal: {g.Title}{streak}{checkedIn}{why}");

                if (g.CheckedInToday == true && milestoneThresholds.Contains(g.CurrentStreak))
                {
                    milestonesHitToday.Add($"{g.Title} reached {g.CurrentStreak} days today");
                }
            }

            if (milestonesHitToday.Count > 0)
                contextParts.Add($"MILESTONE(S) HIT TODAY:\n{string.Join("\n", milestonesHitToday.Select(m => $"  - {m}"))}");

            if (summaries.Count > 0)
                contextParts.Add($"Recent conversation themes:\n{string.Join("\n", summaries.Select(s => $"  - {s}"))}");

            if (journalSummaries.Count > 0)
                contextParts.Add($"Recent journal reflections:\n{string.Join("\n", journalSummaries.Select(s => $"  - {s}"))}");

            if (insights.Count > 0)
                contextParts.Add($"Patterns from their reflections:\n{string.Join("\n", insights.Select(i => $"  - {i}"))}");

            // Check days since last visit
            var lastReflection = previousReflections.FirstOrDefault();
            if (lastReflection is not null)
            {
                var daysSince = today.DayNumber - lastReflection.Date.DayNumber;
                if (daysSince > 1)
                    contextParts.Add($"They haven't opened the app in {daysSince} days.");
            }
            else
            {
                contextParts.Add("This is their first day using the app.");
            }

            // Previous reflections — for continuity AND deduplication
            if (previousReflections.Count > 0)
            {
                var prevLines = previousReflections.Select(r =>
                    $"  - [{r.Date.ToString("yyyy-MM-dd")}] ({r.Type}) \"{r.Content}\"");
                contextParts.Add($"Previous reflections (use for continuity, avoid repeating themes):\n{string.Join("\n", prevLines)}");
            }

            // Vedic astrology context (invisible — enriches the reflection voice)
            try
            {
                var jyotish = await jyotishService.GetContextAsync(userId, today);
                if (jyotish is not null)
                    contextParts.Add(jyotish.FormatForPrompt());
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to load Jyotish context for user {UserId} — continuing without it", userId);
            }

            // Narrative threading instruction based on mode
            var narrativeInstruction = GetNarrativeInstruction(reflectionType, previousReflections);
            contextParts.Add($"NARRATIVE MODE: {reflectionType}\n{narrativeInstruction}");

            var context = contextParts.Count > 0
                ? string.Join("\n\n", contextParts)
                : "No context available yet — they are new.";

            var chatCompletion = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory(BuildSystemPrompt());

            history.AddUserMessage($"Context about this person:\n{context}");

            var result = await chatCompletion.GetChatMessageContentAsync(history);
            var reflection = result.Content?.Trim().Trim('"').Trim();

            if (!string.IsNullOrWhiteSpace(reflection))
            {
                db.DailyReflections.Add(new DailyReflection
                {
                    Id = Guid.NewGuid(),
                    UserId = userId,
                    Date = today,
                    Content = reflection,
                    Type = reflectionType,
                    CreatedAt = DateTime.UtcNow
                });
                await db.SaveChangesAsync();
                logger.LogInformation("Generated {Type} reflection for user {UserId}", reflectionType, userId);

                await pushService.SendSilentPushAsync(userId, new Dictionary<string, string> { ["type"] = "reflection" });
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate daily reflection for user {UserId}", userId);
        }
    }

    /// <summary>
    /// Determines today's reflection mode using weighted random selection.
    /// If yesterday was a Seed, today MUST be a Followup.
    /// Otherwise: 70% Regular, 20% Seed, 10% Callback.
    /// Callbacks require 7+ days of history. Seeds require 3+ days.
    /// </summary>
    private static ReflectionType DetermineReflectionType(
        IReadOnlyList<PreviousReflection> previousReflections)
    {
        // Rule 1: If yesterday was a Seed, today must follow up
        if (previousReflections.Count > 0)
        {
            var yesterday = previousReflections[0];
            if (yesterday.Type == ReflectionType.Seed)
                return ReflectionType.Followup;
        }

        var totalDays = previousReflections.Count;

        // Don't do narrative tricks in the first 3 days — let the user settle in
        if (totalDays < 3)
            return ReflectionType.Regular;

        // Callbacks need enough history to reference something meaningful
        var canCallback = totalDays >= 7;

        var roll = Random.Shared.NextDouble();

        if (canCallback && roll < 0.10)
            return ReflectionType.Callback;
        if (roll < 0.30) // 0.10 to 0.30 = 20%
            return ReflectionType.Seed;

        return ReflectionType.Regular;
    }

    private static string GetNarrativeInstruction(
        ReflectionType type,
        IReadOnlyList<PreviousReflection> previousReflections)
    {
        return type switch
        {
            ReflectionType.Seed => """
                TODAY'S MODE: SEED-PLANTING
                Your job today is to plant curiosity. Notice something that is
                forming — a pattern, a shift, a connection between two parts of
                their practice — but DON'T resolve it. Leave it open.

                End with something that makes them want to come back tomorrow:
                "I'm watching something form." or "This might be clearer tomorrow."

                The seed must be grounded in real data — don't fabricate patterns.
                But you can notice something genuinely emerging and name it as
                unresolved. The user should think about this during their day.
                """,

            ReflectionType.Followup => $"""
                TODAY'S MODE: FOLLOWUP
                Yesterday's reflection planted a seed. Here it is:
                "{previousReflections[0].Content}"

                Today you MUST continue that thread. Resolve it, deepen it, or
                reveal what you were noticing. The user came back specifically to
                see what you'd say next — deliver on that promise.

                Don't repeat yesterday's exact language. Advance the observation.
                Show them what you see now that you have one more day of data.
                """,

            ReflectionType.Callback => $"""
                TODAY'S MODE: CALLBACK
                Reference something from their past — a reflection, a pattern, or
                a moment from their earlier practice — and connect it to where they
                are now. This creates a "the app remembers my story" feeling.

                Use their previous reflections as source material. Find a specific
                one from at least 4 days ago and show how something has shifted,
                grown, or proved true since then.

                Pattern: "X days ago, [what was true then]. Look at today. [what
                changed]." Be specific. Name dates or timeframes.
                """,

            _ => """
                TODAY'S MODE: REGULAR
                Write a warm, specific observation about their current practice.
                Ground it in their actual data. Notice something they might not
                have seen about their own patterns.

                This is the standard reflection — no narrative tricks. Just a
                clear, honest mirror.
                """
        };
    }

    private static string BuildSystemPrompt()
    {
        return """
            You write a single daily reflection for a person using a spiritual
            wellness app. This reflection appears when they open the app — it is
            the first meaningful thing they read.

            Your job is to NOTICE something. Not to advise. Not to motivate.
            Not to teach. To observe something about their patterns, their
            practice, their journey that they might not have seen themselves.

            Rules:
            - Maximum 50 words. Two to three SHORT sentences. Never more.
            - Be SPECIFIC. Reference actual data — their streaks, their journal
              themes, their patterns. A reflection that could apply to anyone is
              worthless.
            - ONLY speak to what they HAVE done, never what they haven't.
              Do not mention incomplete goals, dormant commitments, or missed
              days. If a goal has no activity, ignore it completely.
            - Never give advice or instructions. No "try to..." or "consider..."
            - Never use exclamation marks. Never be peppy.
            - Never judge, evaluate, or imply they should do more.
            - If they've been away, welcome them without guilt.
            - If you notice a pattern in what they DO, NAME it.
            - If a MILESTONE is noted in the context (a streak threshold crossed
              today — 7, 14, 30, 60, 100, or 365 days), acknowledge it simply.
              No gamification language. No "congrats" or "achievement." Observe
              what this number means about them. Example: "Thirty days of
              meditation. The practice has become a person, not a task."
            - At 14+ day milestones, use IDENTITY language. Not "great streak"
              but "this is who you are now." The practice is part of them.
            - Read the NARRATIVE MODE instruction carefully. It tells you whether
              to write a regular observation, plant a seed, follow up on
              yesterday's seed, or callback to something from their past. Follow
              it precisely — broken narrative promises destroy trust.
            - Do not repeat themes from their previous reflections.
            - Tone: observant, warm, unhurried.
            - Do not use their name.
            - Do not use quotation marks around the reflection.

            Respond with ONLY the reflection. Nothing else.
            """;
    }

    private record PreviousReflection(string Content, ReflectionType Type, DateOnly Date);
}
