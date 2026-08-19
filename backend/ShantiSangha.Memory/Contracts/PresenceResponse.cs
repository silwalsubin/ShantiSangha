namespace ShantiSangha.Memory.Contracts;

/// How many of the last `WindowDays` local days the user reflected on
/// (wrote a journal, voice note, or substantive companion message).
public record PresenceResponse(int DaysReflected, int WindowDays, bool ReflectedToday);
