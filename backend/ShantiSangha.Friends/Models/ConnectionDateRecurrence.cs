namespace ShantiSangha.Friends.Models;

/// How a `ConnectionDate` repeats. `Yearly` is the default — birthdays,
/// anniversaries, day-we-met all roll forward each year so reminders
/// and "Nth anniversary" math should ignore the original year. `Once`
/// pins the date to its absolute calendar slot (moved to NYC, started
/// new job) and never recurs.
public enum ConnectionDateRecurrence
{
    Yearly,
    Once
}
