using System.Globalization;

namespace ShantiSangha.Trading.Services;

public record IpoSeedRow(
    string Ticker,
    string Company,
    DateOnly IpoDate,
    string? FirstTradeTimeEt,
    string Exchange,
    double Latitude,
    double Longitude
);

/// <summary>
/// Reads `Data/ipo_first_trades.csv` once at startup. The file ships next to
/// the assembly via &lt;CopyToOutputDirectory&gt; in the csproj.
/// </summary>
public interface IIpoChartCsvLoader
{
    IReadOnlyDictionary<string, IpoSeedRow> Rows { get; }
}

public class IpoChartCsvLoader : IIpoChartCsvLoader
{
    public IReadOnlyDictionary<string, IpoSeedRow> Rows { get; }

    public IpoChartCsvLoader()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Data", "ipo_first_trades.csv");
        var rows = new Dictionary<string, IpoSeedRow>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(path))
        {
            Rows = rows;
            return;
        }

        var lines = File.ReadAllLines(path);
        if (lines.Length == 0)
        {
            Rows = rows;
            return;
        }

        // Header: ticker,company,ipo_date,first_trade_time_et,exchange,lat,lon,notes
        for (var i = 1; i < lines.Length; i++)
        {
            var line = lines[i].Trim();
            if (string.IsNullOrEmpty(line)) continue;

            var cols = ParseCsvRow(line);
            if (cols.Count < 7) continue;

            try
            {
                var row = new IpoSeedRow(
                    Ticker: cols[0].Trim().ToUpperInvariant(),
                    Company: cols[1].Trim(),
                    IpoDate: DateOnly.ParseExact(cols[2].Trim(), "yyyy-MM-dd", CultureInfo.InvariantCulture),
                    FirstTradeTimeEt: string.IsNullOrWhiteSpace(cols[3]) ? null : cols[3].Trim(),
                    Exchange: cols[4].Trim(),
                    Latitude: double.Parse(cols[5].Trim(), CultureInfo.InvariantCulture),
                    Longitude: double.Parse(cols[6].Trim(), CultureInfo.InvariantCulture)
                );
                rows[row.Ticker] = row;
            }
            catch
            {
                // skip malformed rows — a bad single row shouldn't stall startup
            }
        }

        Rows = rows;
    }

    private static List<string> ParseCsvRow(string line)
    {
        // minimal CSV parser — handles quoted fields containing commas
        var fields = new List<string>();
        var sb = new System.Text.StringBuilder();
        var inQuotes = false;
        foreach (var ch in line)
        {
            if (ch == '"')
            {
                inQuotes = !inQuotes;
            }
            else if (ch == ',' && !inQuotes)
            {
                fields.Add(sb.ToString());
                sb.Clear();
            }
            else
            {
                sb.Append(ch);
            }
        }
        fields.Add(sb.ToString());
        return fields;
    }
}
