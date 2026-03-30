/**
 * Timezone-safe date utilities.
 *
 * The backend stores dates in UTC, but users interact with "today"
 * in their local timezone. This composable provides the local date
 * string (YYYY-MM-DD) to send to the API so that check-ins and
 * queries use the user's actual day, not the server's UTC day.
 */

export function useLocalDate() {
  function today(): string {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }

  function daysRemaining(dateStr: string | null): number | null {
    if (!dateStr) return null
    const target = new Date(dateStr + 'T00:00:00')
    const now = new Date()
    now.setHours(0, 0, 0, 0)
    return Math.ceil((target.getTime() - now.getTime()) / 86400000)
  }

  function formatDate(dateStr: string): string {
    if (!dateStr) return ''
    const d = new Date(dateStr.includes('T') ? dateStr : dateStr + 'T12:00:00')
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
  }

  function formatShortDate(dateStr: string): string {
    if (!dateStr) return ''
    const d = new Date(dateStr.includes('T') ? dateStr : dateStr + 'T12:00:00')
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
  }

  return { today, daysRemaining, formatDate, formatShortDate }
}
