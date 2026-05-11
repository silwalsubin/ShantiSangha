<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useApi } from '@/composables/useApi'
import { useLocalDate } from '@/composables/useLocalDate'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()
const { formatShortDate } = useLocalDate()

// --- Practices state ---
interface Practice {
  id: string
  title: string
  currentStreak: number
  longestStreak: number
}

interface PracticeHistory {
  practiceId: string
  days: { date: string; completed: boolean }[]
}

const practices = ref<Practice[]>([])
const practicesLoading = ref(true)
const weekHistory = ref<Record<string, PracticeHistory>>({})
const weekHistoryLoading = ref(true)

// --- Reminders state ---
interface ReminderItem {
  id: string
  label: string
  date: string
  completed: boolean
  daysRemaining: number
}

const reminders = ref<ReminderItem[]>([])
const remindersLoading = ref(true)

const conversationCount = ref(0)
const journalCount = ref(0)
const voiceCount = ref(0)
const statsLoading = ref(true)

// --- Data loaders ---
async function loadPractices() {
  practicesLoading.value = true
  try {
    const data = await api.get<any>('/practices')
    const items = Array.isArray(data) ? data : (data?.practices || data?.items || [])
    practices.value = items.map((p: any) => ({
      id: p.id,
      title: p.title,
      currentStreak: p.currentStreak ?? 0,
      longestStreak: p.longestStreak ?? 0,
    }))
  } catch {
    practices.value = []
  } finally {
    practicesLoading.value = false
  }
}

async function loadWeekHistory() {
  weekHistoryLoading.value = true
  try {
    const histories: Record<string, PracticeHistory> = {}
    for (const p of practices.value) {
      try {
        const data = await api.get<any>(`/practices/${p.id}/history?days=7`)
        const items = Array.isArray(data) ? data : (data?.checkins || data?.checkIns || data?.items || [])
        histories[p.id] = {
          practiceId: p.id,
          days: buildWeekDays(items),
        }
      } catch {
        histories[p.id] = { practiceId: p.id, days: buildWeekDays([]) }
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

async function loadReminders() {
  remindersLoading.value = true
  try {
    const data = await api.get<any>('/reminders')
    const items = Array.isArray(data) ? data : (data?.reminders || data?.items || [])
    reminders.value = items
      .filter((r: any) => !r.connectionId)
      .map((r: any): ReminderItem => ({
        id: r.id,
        label: r.label,
        date: typeof r.date === 'string' ? r.date : String(r.date),
        completed: r.completedAt != null,
        daysRemaining: r.daysRemaining ?? 0,
      }))
  } catch {
    reminders.value = []
  } finally {
    remindersLoading.value = false
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

const upcomingReminders = computed(() =>
  [...reminders.value].sort((a, b) => {
    if (a.completed !== b.completed) return a.completed ? 1 : -1
    return a.daysRemaining - b.daysRemaining
  })
)

onMounted(async () => {
  await loadPractices()
  loadWeekHistory()
  loadReminders()
  loadStats()
})
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Header -->
    <p class="text-[13px] sm:text-sm text-sacred-text-secondary">See how you're growing over time.</p>

    <!-- Your Dharma (Practices) -->
    <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
      <div class="flex items-center gap-1.5">
        <SacredIcons name="flame" :size="14" class="text-sacred-gold" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Your Dharma</p>
      </div>

      <div v-if="practicesLoading" class="mt-4 space-y-3">
        <div v-for="i in 2" :key="i" class="h-16 animate-pulse rounded-2xl bg-sacred-bg-hover" />
      </div>

      <div v-else-if="practices.length === 0" class="mt-4 text-sm text-sacred-text-secondary">
        No practices yet. Set one from the home screen.
      </div>

      <ul v-else class="mt-4 space-y-2">
        <li
          v-for="p in practices"
          :key="p.id"
          class="cursor-pointer rounded-2xl border border-sacred-border-subtle bg-sacred-bg-card-inner px-4 py-3 transition duration-200 active:scale-[0.99]"
          @click="$router.push(`/app/journey/practices/${p.id}`)"
        >
          <div class="flex items-center justify-between">
            <p class="text-sm font-medium text-sacred-text">{{ p.title }}</p>
            <div class="flex items-center gap-3 shrink-0">
              <div class="flex items-center gap-1">
                <SacredIcons name="flame" :size="14" class="text-sacred-gold" />
                <span class="font-serif font-bold text-sacred-gold text-sm">{{ p.currentStreak }}</span>
                <span class="text-[10px] text-sacred-muted">days</span>
              </div>
            </div>
          </div>
          <div class="mt-1 flex items-center gap-3">
            <span class="text-[10px] uppercase tracking-[0.15em] text-sacred-label">
              Longest: {{ p.longestStreak }} days
            </span>
          </div>
        </li>
      </ul>
    </div>

    <!-- Dharma This Week (Practices only) -->
    <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Dharma This Week</p>

      <div v-if="practicesLoading || weekHistoryLoading" class="mt-4 space-y-3">
        <div v-for="i in 2" :key="i" class="h-12 animate-pulse rounded-2xl bg-sacred-bg-hover" />
      </div>

      <div v-else-if="practices.length === 0" class="mt-4 text-sm text-sacred-text-secondary">
        Set your practices to see your weekly progress here.
      </div>

      <div v-else class="mt-4 space-y-4">
        <div
          v-for="p in practices"
          :key="p.id"
        >
          <p class="text-xs font-medium text-sacred-text mb-2">{{ p.title }}</p>
          <div class="flex items-center gap-2">
            <div
              v-for="(day, idx) in (weekHistory[p.id]?.days || [])"
              :key="idx"
              class="flex flex-col items-center gap-1"
            >
              <div
                class="h-6 w-6 rounded-full flex items-center justify-center transition-all duration-200"
                :class="day.completed
                  ? 'bg-gradient-to-br from-sacred-gold to-sacred-gold-dark'
                  : 'border border-sacred-border-strong bg-sacred-bg-card-deep'"
              >
                <SacredIcons v-if="day.completed" name="check" :size="12" class="text-white" />
              </div>
              <span class="text-[9px] text-sacred-muted-light">{{ dayLabel(day.date) }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Reminders -->
    <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
      <div class="flex items-center gap-1.5">
        <SacredIcons name="target" :size="14" class="text-sacred-gold" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Reminders</p>
      </div>

      <div v-if="remindersLoading" class="mt-4 space-y-3">
        <div v-for="i in 2" :key="i" class="h-16 animate-pulse rounded-2xl bg-sacred-bg-hover" />
      </div>

      <div v-else-if="upcomingReminders.length === 0" class="mt-4 text-sm text-sacred-text-secondary">
        No reminders yet. Add one from the home screen.
      </div>

      <ul v-else class="mt-4 space-y-2">
        <li
          v-for="r in upcomingReminders"
          :key="r.id"
          class="rounded-2xl border border-sacred-border-subtle bg-sacred-bg-card-inner px-4 py-3"
        >
          <div class="flex items-center justify-between">
            <p class="text-sm font-medium text-sacred-text">{{ r.label }}</p>
            <div v-if="r.completed" class="shrink-0 rounded-full bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-2.5 py-0.5">
              <span class="text-[10px] font-semibold text-white">Completed</span>
            </div>
          </div>
          <div class="mt-1.5 flex items-center gap-3">
            <span class="font-serif text-xs text-sacred-gold">
              {{ formatShortDate(r.date) }}
              <template v-if="!r.completed">
                <template v-if="r.daysRemaining > 0">
                  — {{ r.daysRemaining }} days left
                </template>
                <template v-else-if="r.daysRemaining === 0">
                  — Due today
                </template>
                <template v-else>
                  — {{ Math.abs(r.daysRemaining) }} days overdue
                </template>
              </template>
            </span>
          </div>
        </li>
      </ul>
    </div>

    <!-- Practice Stats -->
    <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Practice Stats</p>

      <div v-if="statsLoading" class="mt-4 grid grid-cols-3 gap-3">
        <div v-for="i in 3" :key="i" class="h-20 animate-pulse rounded-2xl bg-sacred-bg-hover" />
      </div>

      <div v-else class="mt-4 grid grid-cols-3 gap-3">
        <div class="rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-sacred-gold-15 to-sacred-gold-05">
            <SacredIcons name="dialogue" :size="14" />
          </div>
          <p class="text-2xl font-bold text-sacred-gold">{{ conversationCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Conversations</p>
        </div>
        <div class="rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-sacred-gold-15 to-sacred-gold-05">
            <SacredIcons name="scroll" :size="14" />
          </div>
          <p class="text-2xl font-bold text-sacred-gold">{{ journalCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Journals</p>
        </div>
        <div class="rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-sacred-gold-15 to-sacred-gold-05">
            <SacredIcons name="shankha" :size="14" />
          </div>
          <p class="text-2xl font-bold text-sacred-gold">{{ voiceCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Voice Notes</p>
        </div>
      </div>
    </div>
  </div>
</template>
