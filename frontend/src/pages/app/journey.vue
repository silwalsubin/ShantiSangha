<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()

// --- Goals state ---
interface Goal {
  id: string
  title: string
  type: 'Recurring' | 'OneTime'
  currentStreak: number
  longestStreak: number
  targetDate: string | null
  completedAt: string | null
  checkInCount: number
}

interface GoalHistory {
  goalId: string
  days: { date: string; completed: boolean }[]
}

const goals = ref<Goal[]>([])
const goalsLoading = ref(true)
const weekHistory = ref<Record<string, GoalHistory>>({})
const weekHistoryLoading = ref(true)

const recurringGoals = computed(() => goals.value.filter(g => g.type === 'Recurring'))
const oneTimeGoals = computed(() => goals.value.filter(g => g.type === 'OneTime'))

// --- Existing state ---
const insights = ref<any[]>([])
const insightsLoading = ref(true)

const conversationCount = ref(0)
const journalCount = ref(0)
const voiceCount = ref(0)
const statsLoading = ref(true)

// --- Data loaders ---
async function loadGoals() {
  goalsLoading.value = true
  try {
    const data = await api.get<any>('/goals')
    const items = Array.isArray(data) ? data : (data?.goals || data?.items || [])
    goals.value = items
      .filter((g: any) => !g.archivedAt && !g.archived_at)
      .map((g: any) => ({
        id: g.id,
        title: g.title,
        type: g.type ?? 'Recurring',
        currentStreak: g.currentStreak ?? g.current_streak ?? 0,
        longestStreak: g.longestStreak ?? g.longest_streak ?? 0,
        targetDate: g.targetDate ?? g.target_date ?? null,
        completedAt: g.completedAt ?? g.completed_at ?? null,
        checkInCount: g.checkInCount ?? g.check_in_count ?? g.progressNoteCount ?? g.progress_note_count ?? 0,
      }))
  } catch {
    goals.value = []
  } finally {
    goalsLoading.value = false
  }
}

async function loadWeekHistory() {
  weekHistoryLoading.value = true
  try {
    // Load history for each goal for the last 7 days
    const histories: Record<string, GoalHistory> = {}
    for (const goal of recurringGoals.value) {
      try {
        const data = await api.get<any>(`/goals/${goal.id}/history?days=7`)
        const items = Array.isArray(data) ? data : (data?.checkins || data?.checkIns || data?.items || [])
        histories[goal.id] = {
          goalId: goal.id,
          days: buildWeekDays(items),
        }
      } catch {
        histories[goal.id] = { goalId: goal.id, days: buildWeekDays([]) }
      }
    }
    weekHistory.value = histories
  } finally {
    weekHistoryLoading.value = false
  }
}

function buildWeekDays(checkins: any[]): { date: string; completed: boolean }[] {
  const days: { date: string; completed: boolean }[] = []
  const today = new Date()
  for (let i = 6; i >= 0; i--) {
    const d = new Date(today)
    d.setDate(d.getDate() - i)
    const dateStr = d.toISOString().split('T')[0]
    const checkin = checkins.find((c: any) => {
      const cDate = (c.date || c.created_at || c.createdAt || '').split('T')[0]
      return cDate === dateStr
    })
    days.push({
      date: dateStr,
      completed: checkin ? (checkin.completed ?? true) : false,
    })
  }
  return days
}

function dayLabel(dateStr: string): string {
  const d = new Date(dateStr + 'T12:00:00')
  return d.toLocaleDateString('en-US', { weekday: 'narrow' })
}

async function loadInsights() {
  insightsLoading.value = true
  try {
    const data = await api.get<any>('/insights?page=1')
    const items = Array.isArray(data) ? data : (data?.insights || data?.items || data?.results || [])
    insights.value = items.slice(0, 3)
  } catch {
    insights.value = []
  } finally {
    insightsLoading.value = false
  }
}

async function loadStats() {
  statsLoading.value = true
  try {
    const [convData, journalData, voiceData] = await Promise.all([
      api.get<any>('/conversations'),
      api.get<any>('/journals'),
      api.get<any>('/voice/entries'),
    ])
    const convItems = Array.isArray(convData) ? convData : (convData?.conversations || convData?.items || [])
    const journalItems = Array.isArray(journalData) ? journalData : (journalData?.journals || journalData?.items || [])
    const voiceItems = Array.isArray(voiceData) ? voiceData : (voiceData?.entries || voiceData?.items || [])
    conversationCount.value = convItems.length
    journalCount.value = journalItems.length
    voiceCount.value = voiceItems.length
  } catch {
    // leave at 0
  } finally {
    statsLoading.value = false
  }
}

// --- Helpers ---
function daysRemaining(dateStr: string | null): number | null {
  if (!dateStr) return null
  const target = new Date(dateStr + 'T00:00:00')
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const diff = Math.ceil((target.getTime() - today.getTime()) / 86400000)
  return diff
}

function formatTargetDate(dateStr: string | null): string {
  if (!dateStr) return ''
  const d = new Date(dateStr + 'T12:00:00')
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

function sourceLabel(s: string) {
  const map: Record<string, string> = {
    conversation: 'Conversation',
    journal: 'Journal',
  }
  return map[s] || s || 'Unknown'
}

onMounted(async () => {
  await loadGoals()
  loadWeekHistory()
  loadInsights()
  loadStats()
})
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Header -->
    <p class="text-[13px] sm:text-sm text-[#6b5740]">See how you're growing over time.</p>

    <!-- Your Dharma (Recurring Goals) -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <div class="flex items-center gap-1.5">
        <SacredIcons name="flame" :size="14" class="text-[#c4873b]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Your Dharma</p>
      </div>

      <div v-if="goalsLoading" class="mt-4 space-y-3">
        <div v-for="i in 2" :key="i" class="h-16 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else-if="recurringGoals.length === 0" class="mt-4 text-sm text-[#6b5740]">
        No tasks yet. Set one from the Sacred Scrolls.
      </div>

      <ul v-else class="mt-4 space-y-2">
        <li
          v-for="goal in recurringGoals"
          :key="goal.id"
          class="rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3"
        >
          <div class="flex items-center justify-between">
            <p class="text-sm font-medium text-[#2b1e10]">{{ goal.title }}</p>
            <div class="flex items-center gap-3 shrink-0">
              <div class="flex items-center gap-1">
                <SacredIcons name="flame" :size="14" class="text-[#c4873b]" />
                <span class="font-serif font-bold text-[#c4873b] text-sm">{{ goal.currentStreak }}</span>
                <span class="text-[10px] text-[#9a8568]">days</span>
              </div>
            </div>
          </div>
          <div class="mt-1 flex items-center gap-3">
            <span class="text-[10px] uppercase tracking-[0.15em] text-[#a38d6d]">
              Longest: {{ goal.longestStreak }} days
            </span>
          </div>
        </li>
      </ul>
    </div>

    <!-- Dharma This Week (Recurring only) -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Dharma This Week</p>

      <div v-if="goalsLoading || weekHistoryLoading" class="mt-4 space-y-3">
        <div v-for="i in 2" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else-if="recurringGoals.length === 0" class="mt-4 text-sm text-[#6b5740]">
        Set your tasks to see your weekly progress here.
      </div>

      <div v-else class="mt-4 space-y-4">
        <div
          v-for="goal in recurringGoals"
          :key="goal.id"
        >
          <p class="text-xs font-medium text-[#2b1e10] mb-2">{{ goal.title }}</p>
          <div class="flex items-center gap-2">
            <div
              v-for="(day, idx) in (weekHistory[goal.id]?.days || [])"
              :key="idx"
              class="flex flex-col items-center gap-1"
            >
              <div
                class="h-6 w-6 rounded-full flex items-center justify-center transition-all duration-200"
                :class="day.completed
                  ? 'bg-gradient-to-br from-[#c4873b] to-[#8b5a1b]'
                  : 'border border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.6)]'"
              >
                <SacredIcons v-if="day.completed" name="check" :size="12" class="text-white" />
              </div>
              <span class="text-[9px] text-[#b5996f]">{{ dayLabel(day.date) }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Milestones (OneTime Goals) -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <div class="flex items-center gap-1.5">
        <SacredIcons name="target" :size="14" class="text-[#c4873b]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Milestones</p>
      </div>

      <div v-if="goalsLoading" class="mt-4 space-y-3">
        <div v-for="i in 2" :key="i" class="h-16 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else-if="oneTimeGoals.length === 0" class="mt-4 text-sm text-[#6b5740]">
        No milestones yet. Set one from the Sacred Scrolls.
      </div>

      <ul v-else class="mt-4 space-y-2">
        <li
          v-for="goal in oneTimeGoals"
          :key="goal.id"
          class="cursor-pointer rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3 transition duration-200 active:scale-[0.99]"
          @click="$router.push(`/app/journey/goals/${goal.id}`)"
        >
          <div class="flex items-center justify-between">
            <p class="text-sm font-medium text-[#2b1e10]">{{ goal.title }}</p>
            <div v-if="goal.completedAt" class="shrink-0 rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-2.5 py-0.5">
              <span class="text-[10px] font-semibold text-white">Completed</span>
            </div>
          </div>
          <div class="mt-1.5 flex items-center gap-3">
            <span v-if="goal.targetDate" class="font-serif text-xs text-[#c4873b]">
              {{ formatTargetDate(goal.targetDate) }}
              <template v-if="!goal.completedAt && daysRemaining(goal.targetDate) !== null">
                <template v-if="(daysRemaining(goal.targetDate) ?? 0) > 0">
                  — {{ daysRemaining(goal.targetDate) }} days left
                </template>
                <template v-else-if="(daysRemaining(goal.targetDate) ?? 0) === 0">
                  — Due today
                </template>
                <template v-else>
                  — {{ Math.abs(daysRemaining(goal.targetDate) ?? 0) }} days overdue
                </template>
              </template>
            </span>
            <span v-if="goal.checkInCount > 0" class="text-[10px] uppercase tracking-[0.15em] text-[#a38d6d]">
              {{ goal.checkInCount }} {{ goal.checkInCount === 1 ? 'note' : 'notes' }}
            </span>
          </div>
        </li>
      </ul>
    </div>

    <!-- Practice Stats -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Practice Stats</p>

      <div v-if="statsLoading" class="mt-4 grid grid-cols-3 gap-3">
        <div v-for="i in 3" :key="i" class="h-20 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else class="mt-4 grid grid-cols-3 gap-3">
        <div class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-[rgba(196,135,59,0.15)] to-[rgba(196,135,59,0.05)]">
            <SacredIcons name="dialogue" :size="14" />
          </div>
          <p class="text-2xl font-bold text-[#c4873b]">{{ conversationCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Conversations</p>
        </div>
        <div class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-[rgba(196,135,59,0.15)] to-[rgba(196,135,59,0.05)]">
            <SacredIcons name="scroll" :size="14" />
          </div>
          <p class="text-2xl font-bold text-[#c4873b]">{{ journalCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Journals</p>
        </div>
        <div class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-[rgba(196,135,59,0.15)] to-[rgba(196,135,59,0.05)]">
            <SacredIcons name="shankha" :size="14" />
          </div>
          <p class="text-2xl font-bold text-[#c4873b]">{{ voiceCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Voice Notes</p>
        </div>
      </div>
    </div>

    <!-- Recent Insights -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <div class="flex items-center justify-between">
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Recent Insights</p>
        <router-link
          to="/app/journey/insights"
          class="min-h-[44px] flex items-center text-xs font-medium text-[#c4873b] transition duration-200 hover:text-[#8b5a1b]"
        >
          View all
        </router-link>
      </div>

      <div v-if="insightsLoading" class="mt-3 space-y-2">
        <div v-for="i in 3" :key="i" class="h-16 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else-if="insights.length === 0" class="mt-3 text-sm text-[#6b5740]">
        No insights yet. They are generated during conversations and journal sessions.
      </div>

      <ul v-else class="mt-3 space-y-2">
        <li
          v-for="insight in insights"
          :key="insight.id"
          class="rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3"
        >
          <p class="text-sm leading-relaxed text-[#2b1e10]">{{ insight.content }}</p>
          <p class="mt-1.5 text-[10px] uppercase tracking-[0.15em] text-[#a38d6d]">{{ sourceLabel(insight.source) }}</p>
        </li>
      </ul>
    </div>
  </div>
</template>
