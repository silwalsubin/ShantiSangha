using ShantiSangha.Goals.Models;

namespace ShantiSangha.Goals.Contracts;

public record CreateGoalRequest(
    string Title,
    GoalType Type = GoalType.Recurring,
    GoalFrequency? Frequency = null,
    int? FrequencyTarget = null,
    string? TargetDate = null,
    string? DeeperWhy = null);

public record UpdateGoalRequest(
    string? Title,
    bool? Archived,
    bool? Completed,
    string? DeeperWhy = null,
    int? Progress = null,
    string? TargetDate = null);

public record CheckInRequest(bool Completed, string? Note, string? Date = null);
