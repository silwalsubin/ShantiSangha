using ShantiSangha.Jyotish.Services;
using Xunit;

namespace ShantiSangha.Jyotish.Tests;

/// <summary>
/// Pin the tara bala formula and the 9-tara cycle. The chart-chat AI used
/// to count nakshatras itself and got the count wrong (e.g. Hasta from
/// Mrigashirsha as the 8th instead of the 9th); we now precompute and
/// pass the value through. These tests guard against a regression in the
/// formula or the cycle table.
/// </summary>
public class VedicCalendarTaraBalaTests
{
    // Nakshatra indices (0-based, in standard order):
    //   0=Ashwini, 1=Bharani, 2=Krittika, 3=Rohini,
    //   4=Mrigashirsha, 5=Ardra, 6=Punarvasu, 7=Pushya,
    //   8=Ashlesha, 9=Magha, 10=Purva Phalguni, 11=Uttara Phalguni,
    //   12=Hasta, 13=Chitra, ...,
    //   26=Revati

    [Theory]
    [InlineData(4, 4, 1, 1, "Janma")]      // birth = today → position 1, Janma
    [InlineData(4, 5, 2, 2, "Sampat")]     // Mrigashirsha → Ardra: position 2, Sampat
    [InlineData(4, 12, 9, 9, "Atimitra")]  // Mrigashirsha → Hasta: position 9, Atimitra (the original AI miscount)
    [InlineData(4, 13, 10, 1, "Janma")]    // position 10 wraps to Janma in the 2nd cycle
    [InlineData(0, 26, 27, 9, "Atimitra")] // Ashwini → Revati: max position 27, Atimitra (end of 3rd cycle)
    [InlineData(26, 0, 2, 2, "Sampat")]    // Revati → Ashwini wraps back to position 2
    public void GetTaraBala_PinsClassicalCounts(
        int birthIdx, int currentIdx,
        int expectedPosition, int expectedNumber, string expectedName)
    {
        var (position, number, name, _) = VedicCalendar.GetTaraBala(birthIdx, currentIdx);
        Assert.Equal(expectedPosition, position);
        Assert.Equal(expectedNumber, number);
        Assert.Equal(expectedName, name);
    }

    [Theory]
    [InlineData(1, "neutral")]    // Janma
    [InlineData(2, "favorable")]  // Sampat
    [InlineData(3, "warning")]    // Vipat
    [InlineData(4, "favorable")]  // Kshema
    [InlineData(5, "warning")]    // Pratyak
    [InlineData(6, "favorable")]  // Sadhaka
    [InlineData(7, "warning")]    // Vadha
    [InlineData(8, "favorable")]  // Mitra
    [InlineData(9, "favorable")]  // Atimitra
    public void GetTaraBala_PolarityMatchesCycleSlot(int targetNumber, string expectedPolarity)
    {
        // birth=0 (Ashwini), current=targetNumber-1 → position=targetNumber → cycle slot=targetNumber.
        var (_, number, _, polarity) = VedicCalendar.GetTaraBala(0, targetNumber - 1);
        Assert.Equal(targetNumber, number);
        Assert.Equal(expectedPolarity, polarity);
    }
}
