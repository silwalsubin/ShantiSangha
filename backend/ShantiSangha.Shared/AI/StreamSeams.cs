using System.Text;

namespace ShantiSangha.Shared.AI;

public static class StreamSeams
{
    /// <summary>
    /// Semantic Kernel's auto-invoke produces two assistant rounds around a
    /// tool call (narration → tool → narration). The streaming joins them
    /// without whitespace, so we get "Let me do that now.Your reminder…".
    /// Detect the seam — prior ends in sentence punctuation, next starts
    /// uppercase with no leading whitespace — so the caller can insert a
    /// paragraph break.
    /// </summary>
    public static bool NeedsRoundBreak(StringBuilder soFar, string next)
    {
        if (soFar.Length == 0 || next.Length == 0) return false;
        var lastChar = soFar[soFar.Length - 1];
        if (lastChar != '.' && lastChar != '!' && lastChar != '?') return false;
        var firstChar = next[0];
        return char.IsLetter(firstChar) && char.IsUpper(firstChar);
    }
}
