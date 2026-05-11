namespace ShantiSangha.Trading.Services;

/// <summary>
/// The "universe" the app knows about — the curated mega-cap ticker list
/// with hardcoded sector assignments. This used to live inside
/// PortfolioService but the daily refresh / signal jobs also need it
/// now that the watchlist is gone, so it's been promoted to a shared
/// static surface. Add tickers here and they automatically participate
/// in browse-mode search, daily bar refresh, and (eventually) precomputed
/// scoring.
/// </summary>
public static class TickerCatalog
{
    /// <summary>
    /// Sector overrides for common large-caps — instant resolution
    /// without a yfinance call. Tickers absent from this map fall
    /// through to the runtime resolver (cache / Lambda).
    /// </summary>
    public static readonly IReadOnlyDictionary<string, string> SectorOverrides
        = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        // Information Technology
        ["AAPL"] = "Information Technology",  ["MSFT"] = "Information Technology",
        ["NVDA"] = "Information Technology",  ["AMD"] = "Information Technology",
        ["INTC"] = "Information Technology",  ["AVGO"] = "Information Technology",
        ["CRM"] = "Information Technology",   ["ORCL"] = "Information Technology",
        ["ADBE"] = "Information Technology",  ["CSCO"] = "Information Technology",
        ["ACN"] = "Information Technology",   ["IBM"] = "Information Technology",
        ["QCOM"] = "Information Technology",  ["TXN"] = "Information Technology",
        ["NOW"] = "Information Technology",   ["PANW"] = "Information Technology",
        ["PLTR"] = "Information Technology",  ["SMCI"] = "Information Technology",
        // Health Care
        ["JNJ"] = "Health Care",  ["UNH"] = "Health Care",  ["PFE"] = "Health Care",
        ["LLY"] = "Health Care",  ["ABBV"] = "Health Care", ["MRK"] = "Health Care",
        ["TMO"] = "Health Care",  ["ABT"] = "Health Care",  ["DHR"] = "Health Care",
        ["BMY"] = "Health Care",  ["AMGN"] = "Health Care", ["CVS"] = "Health Care",
        ["ISRG"] = "Health Care",
        // Financials
        ["JPM"] = "Financials", ["BAC"] = "Financials", ["WFC"] = "Financials",
        ["GS"] = "Financials",  ["MS"] = "Financials",  ["C"] = "Financials",
        ["BLK"] = "Financials", ["BRK-A"] = "Financials", ["BRK-B"] = "Financials",
        ["BRK.A"] = "Financials", ["BRK.B"] = "Financials",
        ["V"] = "Financials",   ["MA"] = "Financials",  ["AXP"] = "Financials",
        ["SCHW"] = "Financials", ["COF"] = "Financials", ["USB"] = "Financials",
        // Consumer Discretionary
        ["HD"] = "Consumer Discretionary",   ["AMZN"] = "Consumer Discretionary",
        ["TSLA"] = "Consumer Discretionary", ["NKE"] = "Consumer Discretionary",
        ["MCD"] = "Consumer Discretionary",  ["SBUX"] = "Consumer Discretionary",
        ["LOW"] = "Consumer Discretionary",  ["BKNG"] = "Consumer Discretionary",
        ["ORLY"] = "Consumer Discretionary", ["TJX"] = "Consumer Discretionary",
        ["F"] = "Consumer Discretionary",    ["GM"] = "Consumer Discretionary",
        // Consumer Staples
        ["PG"] = "Consumer Staples",   ["KO"] = "Consumer Staples",
        ["PEP"] = "Consumer Staples",  ["WMT"] = "Consumer Staples",
        ["COST"] = "Consumer Staples", ["MO"] = "Consumer Staples",
        ["PM"] = "Consumer Staples",   ["CL"] = "Consumer Staples",
        ["MDLZ"] = "Consumer Staples", ["TGT"] = "Consumer Staples",
        // Communication Services
        ["VZ"] = "Communication Services",   ["T"] = "Communication Services",
        ["GOOGL"] = "Communication Services", ["GOOG"] = "Communication Services",
        ["META"] = "Communication Services", ["DIS"] = "Communication Services",
        ["NFLX"] = "Communication Services", ["CMCSA"] = "Communication Services",
        ["TMUS"] = "Communication Services",
        // Industrials
        ["CAT"] = "Industrials", ["BA"] = "Industrials", ["GE"] = "Industrials",
        ["HON"] = "Industrials", ["UPS"] = "Industrials", ["RTX"] = "Industrials",
        ["LMT"] = "Industrials", ["MMM"] = "Industrials", ["DE"] = "Industrials",
        ["UNP"] = "Industrials", ["FDX"] = "Industrials", ["NOC"] = "Industrials",
        // Energy
        ["XOM"] = "Energy", ["CVX"] = "Energy", ["COP"] = "Energy",
        ["EOG"] = "Energy", ["SLB"] = "Energy", ["OXY"] = "Energy",
        ["MPC"] = "Energy", ["PSX"] = "Energy",
        // Utilities
        ["NEE"] = "Utilities", ["DUK"] = "Utilities", ["SO"] = "Utilities",
        ["AEP"] = "Utilities", ["D"] = "Utilities",   ["EXC"] = "Utilities",
        // Materials
        ["APD"] = "Materials", ["LIN"] = "Materials", ["SHW"] = "Materials",
        ["ECL"] = "Materials", ["NEM"] = "Materials", ["FCX"] = "Materials",
        ["DD"] = "Materials",
        // Real Estate
        ["PLD"] = "Real Estate", ["AMT"] = "Real Estate", ["EQIX"] = "Real Estate",
        ["CCI"] = "Real Estate", ["O"] = "Real Estate",   ["SPG"] = "Real Estate",
    };

    /// <summary>
    /// One canonical ticker per GICS sector — the basket used by the
    /// portfolio plan to fill missing-sector recommendations.
    /// </summary>
    public static readonly IReadOnlyDictionary<string, string> SectorBasket
        = new Dictionary<string, string>
    {
        ["Information Technology"] = "AAPL",
        ["Health Care"]            = "JNJ",
        ["Financials"]             = "JPM",
        ["Consumer Discretionary"] = "HD",
        ["Consumer Staples"]       = "PG",
        ["Communication Services"] = "VZ",
        ["Industrials"]            = "CAT",
        ["Energy"]                 = "XOM",
        ["Utilities"]              = "NEE",
        ["Materials"]              = "APD",
    };
}
