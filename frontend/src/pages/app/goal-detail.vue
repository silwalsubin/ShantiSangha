<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const route = useRoute()
const router = useRouter()
const api = useApi()

const goalId = computed(() => route.params.id as string)

interface Goal {
  id: string
  title: string
  type: 'Recurring' | 'OneTime'
  deeperWhy: string | null
  currentStreak?: number
  longestStreak?: number
  frequency?: string
  frequencyTarget?: number
  targetDate?: string | null
  completedAt?: string | null
  daysRemaining?: number | null
  noteCount?: number
  createdAt: string
}

interface CheckIn {
  id: string
  date: string
  completed: boolean
  note: string | null
}

const goal = ref<Goal | null>(null)
const checkIns = ref<CheckIn[]>([])
const loading = ref(true)
const calendarLoading = ref(false)
const togglingDate = ref<string | null>(null)
const bulkActioning = ref(false)
const showResetConfirm = ref(false)
const resetting = ref(false)

const editingWhy = ref(false)
const whyInput = ref('')
const savingWhy = ref(false)

// Calendar state — year/month of the currently displayed month
const now = new Date()
const calYear = ref(now.getFullYear())
const calMonth = ref(now.getMonth()) // 0-indexed

const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

const todayStr = computed(() => {
  const n = new Date()
  return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}-${String(n.getDate()).padStart(2, '0')}`
})

const monthLabel = computed(() => {
  const d = new Date(calYear.value, calMonth.value, 1)
  return d.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
})

const goalCreatedDate = computed(() => {
  if (!goal.value) return ''
  return goal.value.createdAt.includes('T')
    ? goal.value.createdAt.split('T')[0]
    : goal.value.createdAt.slice(0, 10)
})

// Can navigate to previous month? Only if goal was created before this month
const canGoPrev = computed(() => {
  if (!goal.value) return false
  const [y, m] = goalCreatedDate.value.split('-').map(Number)
  return calYear.value > y || (calYear.value === y && calMonth.value > m - 1)
})

// Can navigate to next month? Only up to current month
const canGoNext = computed(() => {
  const n = new Date()
  return calYear.value < n.getFullYear() || (calYear.value === n.getFullYear() && calMonth.value < n.getMonth())
})

function prevMonth() {
  if (!canGoPrev.value) return
  if (calMonth.value === 0) { calYear.value--; calMonth.value = 11 }
  else calMonth.value--
}

function nextMonth() {
  if (!canGoNext.value) return
  if (calMonth.value === 11) { calYear.value++; calMonth.value = 0 }
  else calMonth.value++
}

// Build the calendar grid for the current month
interface CalDay {
  date: string       // yyyy-MM-dd
  day: number        // day of month
  checkin: CheckIn | null
  isToday: boolean
  isFuture: boolean
  isBeforeCreation: boolean
  isCurrentMonth: boolean
}

const checkinMap = computed(() => {
  const m = new Map<string, CheckIn>()
  for (const ci of checkIns.value) m.set(ci.date, ci)
  return m
})

const calendarDays = computed((): CalDay[] => {
  const firstDay = new Date(calYear.value, calMonth.value, 1)
  const startDow = firstDay.getDay() // 0=Sun
  const daysInMonth = new Date(calYear.value, calMonth.value + 1, 0).getDate()
  const today = todayStr.value
  const created = goalCreatedDate.value

  const days: CalDay[] = []

  // Leading blanks
  for (let i = 0; i < startDow; i++) {
    days.push({ date: '', day: 0, checkin: null, isToday: false, isFuture: true, isBeforeCreation: true, isCurrentMonth: false })
  }

  for (let d = 1; d <= daysInMonth; d++) {
    const dateStr = `${calYear.value}-${String(calMonth.value + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`
    days.push({
      date: dateStr,
      day: d,
      checkin: checkinMap.value.get(dateStr) ?? null,
      isToday: dateStr === today,
      isFuture: dateStr > today,
      isBeforeCreation: dateStr < created,
      isCurrentMonth: true,
    })
  }

  return days
})

// Count of checked-in days and actionable days in visible month
const checkedInCount = computed(() => calendarDays.value.filter(d => d.isCurrentMonth && d.checkin).length)
const actionableDays = computed(() => calendarDays.value.filter(d => d.isCurrentMonth && !d.isFuture && !d.isBeforeCreation))

// Fetch check-ins for the displayed month
async function loadCheckIns() {
  if (!goal.value) return
  calendarLoading.value = true
  try {
    const from = `${calYear.value}-${String(calMonth.value + 1).padStart(2, '0')}-01`
    const lastDay = new Date(calYear.value, calMonth.value + 1, 0).getDate()
    const to = `${calYear.value}-${String(calMonth.value + 1).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`
    const items = await api.get<any[]>(`/goals/${goal.value.id}/checkins?from=${from}&to=${to}`)
    checkIns.value = (items ?? []).map((c: any) => ({
      id: c.id,
      date: c.date,
      completed: c.completed ?? false,
      note: c.note ?? null,
    }))
  } catch {
    checkIns.value = []
  } finally {
    calendarLoading.value = false
  }
}

// Reload check-ins when month changes
watch([calYear, calMonth], () => { loadCheckIns() })

async function toggleDay(day: CalDay) {
  if (!goal.value || day.isFuture || day.isBeforeCreation || !day.isCurrentMonth) return
  togglingDate.value = day.date
  try {
    if (day.checkin) {
      await api.delete(`/goals/${goal.value.id}/checkin?date=${day.date}`)
      checkIns.value = checkIns.value.filter(c => c.date !== day.date)
    } else {
      const result = await api.post<any>(`/goals/${goal.value.id}/checkin`, {
        completed: true,
        date: day.date,
      })
      checkIns.value.push({
        id: result.id,
        date: result.date,
        completed: result.completed,
        note: result.note ?? null,
      })
    }
    await refreshStreaks()
  } finally {
    togglingDate.value = null
  }
}

async function checkAllMonth() {
  if (!goal.value) return
  bulkActioning.value = true
  try {
    const unchecked = actionableDays.value.filter(d => !d.checkin)
    for (const day of unchecked) {
      const result = await api.post<any>(`/goals/${goal.value.id}/checkin`, {
        completed: true,
        date: day.date,
      })
      checkIns.value.push({
        id: result.id,
        date: result.date,
        completed: result.completed,
        note: result.note ?? null,
      })
    }
    await refreshStreaks()
  } finally {
    bulkActioning.value = false
  }
}

async function uncheckAllMonth() {
  if (!goal.value) return
  bulkActioning.value = true
  try {
    const checked = actionableDays.value.filter(d => d.checkin)
    for (const day of checked) {
      await api.delete(`/goals/${goal.value.id}/checkin?date=${day.date}`)
      checkIns.value = checkIns.value.filter(c => c.date !== day.date)
    }
    await refreshStreaks()
  } finally {
    bulkActioning.value = false
  }
}

async function refreshStreaks() {
  if (!goal.value || goal.value.type !== 'Recurring') return
  try {
    const data = await api.get<any>(`/goals/${goal.value.id}`)
    goal.value.currentStreak = data.currentStreak ?? data.current_streak ?? 0
    goal.value.longestStreak = data.longestStreak ?? data.longest_streak ?? 0
  } catch { /* ignore */ }
}

async function resetHistory() {
  if (!goal.value) return
  resetting.value = true
  try {
    await api.post(`/goals/${goal.value.id}/reset`)
    // Reload everything — createdAt, streaks, and check-ins all change
    await loadGoal()
    // Reset calendar to current month
    const now = new Date()
    calYear.value = now.getFullYear()
    calMonth.value = now.getMonth()
  } finally {
    resetting.value = false
    showResetConfirm.value = false
  }
}

async function loadGoal() {
  loading.value = true
  try {
    const data = await api.get<any>(`/goals/${goalId.value}`)
    goal.value = {
      id: data.id,
      title: data.title,
      type: data.type ?? 'Recurring',
      deeperWhy: data.deeperWhy ?? data.deeper_why ?? null,
      currentStreak: data.currentStreak ?? data.current_streak ?? 0,
      longestStreak: data.longestStreak ?? data.longest_streak ?? 0,
      frequency: data.frequency ?? null,
      frequencyTarget: data.frequencyTarget ?? data.frequency_target ?? null,
      targetDate: data.targetDate ?? data.target_date ?? null,
      completedAt: data.completedAt ?? data.completed_at ?? null,
      daysRemaining: data.daysRemaining ?? data.days_remaining ?? null,
      noteCount: data.noteCount ?? data.note_count ?? 0,
      createdAt: data.createdAt ?? data.created_at ?? '',
    }
    whyInput.value = goal.value.deeperWhy ?? ''
    await loadCheckIns()
  } catch {
    goal.value = null
  } finally {
    loading.value = false
  }
}

async function saveDeeperWhy() {
  if (!goal.value) return
  savingWhy.value = true
  try {
    await api.patch(`/goals/${goal.value.id}`, { deeperWhy: whyInput.value })
    goal.value.deeperWhy = whyInput.value || null
    editingWhy.value = false
  } catch {
    // keep editing
  } finally {
    savingWhy.value = false
  }
}

function startEditWhy() {
  whyInput.value = goal.value?.deeperWhy ?? ''
  editingWhy.value = true
}

function formatDate(dateStr: string): string {
  if (!dateStr) return ''
  const d = new Date(dateStr.includes('T') ? dateStr : dateStr + 'T12:00:00')
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function daysSinceCreated(): number {
  if (!goal.value) return 0
  const created = new Date(goal.value.createdAt)
  const now = new Date()
  return Math.floor((now.getTime() - created.getTime()) / 86400000)
}

onMounted(() => {
  loadGoal()
})
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Back button -->
    <button
      class="flex min-h-[44px] items-center gap-1.5 text-sm font-medium text-sacred-gold transition duration-200 hover:text-sacred-gold-dark"
      @click="router.push('/app/journey')"
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M12 19l-7-7 7-7"/></svg>
      Journey
    </button>

    <!-- Loading -->
    <div v-if="loading" class="space-y-4">
      <div class="h-8 w-3/4 animate-pulse rounded-xl bg-sacred-bg-hover-strong" />
      <div class="h-32 animate-pulse rounded-2xl bg-sacred-bg-hover" />
    </div>

    <!-- Not found -->
    <div v-else-if="!goal" class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-6 text-center">
      <p class="text-sm text-sacred-text-secondary">Task not found.</p>
    </div>

    <template v-else>
      <!-- Header card -->
      <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
        <div class="flex items-start gap-2">
          <SacredIcons :name="goal.type === 'Recurring' ? 'flame' : 'target'" :size="18" class="mt-0.5 text-sacred-gold" />
          <div class="flex-1">
            <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">
              {{ goal.type === 'Recurring' ? 'Daily Practice' : 'Milestone' }}
            </p>
            <h1 class="mt-1 font-serif text-xl font-bold text-sacred-text">{{ goal.title }}</h1>
          </div>
        </div>

        <!-- Stats -->
        <div class="mt-5 flex gap-3">
          <template v-if="goal.type === 'Recurring'">
            <div class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
              <p class="text-2xl font-bold text-sacred-gold">{{ goal.currentStreak }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Current Streak</p>
            </div>
            <div class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
              <p class="text-2xl font-bold text-sacred-gold">{{ goal.longestStreak }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Longest Streak</p>
            </div>
            <div class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
              <p class="text-2xl font-bold text-sacred-gold">{{ daysSinceCreated() }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Days Active</p>
            </div>
          </template>
          <template v-else>
            <div class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
              <p class="text-2xl font-bold text-sacred-gold">
                {{ goal.completedAt ? 'Done' : goal.daysRemaining != null ? goal.daysRemaining : '--' }}
              </p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">
                {{ goal.completedAt ? 'Completed' : 'Days Left' }}
              </p>
            </div>
            <div class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
              <p class="text-2xl font-bold text-sacred-gold">{{ goal.noteCount ?? 0 }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Progress Notes</p>
            </div>
            <div v-if="goal.targetDate" class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
              <p class="font-serif text-sm font-bold text-sacred-gold">{{ formatDate(goal.targetDate) }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Target Date</p>
            </div>
          </template>
        </div>

        <!-- Created date -->
        <p class="mt-4 text-[10px] uppercase tracking-[0.15em] text-sacred-label">
          Started {{ formatDate(goal.createdAt) }}
        </p>
      </div>

      <!-- Deeper Why -->
      <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <SacredIcons name="lotus" :size="14" class="text-sacred-gold" />
            <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">The Deeper Why</p>
          </div>
          <button
            v-if="!editingWhy"
            class="min-h-[44px] text-xs font-medium text-sacred-gold transition duration-200 hover:text-sacred-gold-dark"
            @click="startEditWhy"
          >
            {{ goal.deeperWhy ? 'Edit' : 'Add' }}
          </button>
        </div>

        <div v-if="editingWhy" class="mt-3">
          <textarea
            v-model="whyInput"
            rows="3"
            class="w-full rounded-xl border border-sacred-border-strong bg-sacred-bg-card-deep px-3 py-2 text-sm text-sacred-text placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold-30"
            placeholder="Why does this task matter to you? What deeper intention does it serve?"
          />
          <div class="mt-2 flex gap-2 justify-end">
            <button
              class="min-h-[44px] rounded-xl px-4 text-sm font-medium text-sacred-text-secondary transition duration-200 hover:bg-sacred-bg-hover"
              @click="editingWhy = false"
            >
              Cancel
            </button>
            <button
              class="min-h-[44px] rounded-xl bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-4 text-sm font-medium text-white shadow-sm transition duration-200 active:scale-[0.98] disabled:opacity-50"
              :disabled="savingWhy"
              @click="saveDeeperWhy"
            >
              Save
            </button>
          </div>
        </div>

        <p v-else-if="goal.deeperWhy" class="mt-3 font-serif text-sm italic leading-relaxed text-sacred-text">
          "{{ goal.deeperWhy }}"
        </p>

        <p v-else class="mt-3 text-sm text-sacred-muted">
          What draws you to this task? Understanding the deeper intention behind your commitments can transform discipline into devotion.
        </p>
      </div>

      <!-- Calendar Check-ins -->
      <div v-if="goal.type === 'Recurring'" class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
        <!-- Month header -->
        <div class="flex items-center justify-between">
          <button
            class="flex h-10 w-10 items-center justify-center rounded-full transition duration-150"
            :class="canGoPrev ? 'text-sacred-gold hover:bg-sacred-bg-hover active:scale-95' : 'text-sacred-muted-light pointer-events-none'"
            @click="prevMonth"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>
          </button>
          <p class="font-serif text-sm font-semibold text-sacred-text">{{ monthLabel }}</p>
          <button
            class="flex h-10 w-10 items-center justify-center rounded-full transition duration-150"
            :class="canGoNext ? 'text-sacred-gold hover:bg-sacred-bg-hover active:scale-95' : 'text-sacred-muted-light pointer-events-none'"
            @click="nextMonth"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg>
          </button>
        </div>

        <!-- Day-of-week labels -->
        <div class="mt-3 grid grid-cols-7 gap-1">
          <div v-for="label in DAY_LABELS" :key="label" class="py-1 text-center text-[9px] font-bold uppercase tracking-[0.15em] text-sacred-muted">
            {{ label }}
          </div>
        </div>

        <!-- Calendar grid -->
        <div class="mt-1 grid grid-cols-7 gap-1" :class="calendarLoading || bulkActioning ? 'opacity-50 pointer-events-none' : ''">
          <div
            v-for="(day, i) in calendarDays"
            :key="i"
            class="flex aspect-square items-center justify-center"
          >
            <button
              v-if="day.isCurrentMonth"
              class="relative flex h-10 w-10 items-center justify-center rounded-full text-xs font-medium transition duration-150"
              :class="[
                day.isFuture || day.isBeforeCreation
                  ? 'text-sacred-muted-light/40 cursor-default'
                  : day.checkin?.completed
                    ? 'bg-gradient-to-br from-sacred-gold to-sacred-gold-dark text-white shadow-sm cursor-pointer active:scale-90'
                    : day.checkin
                      ? 'bg-sacred-muted/10 text-sacred-muted cursor-pointer active:scale-90'
                      : 'text-sacred-text hover:bg-sacred-bg-hover cursor-pointer active:scale-90',
                day.isToday && !day.checkin ? 'ring-1 ring-sacred-gold/40' : '',
                togglingDate === day.date ? 'opacity-40 pointer-events-none' : '',
              ]"
              :disabled="day.isFuture || day.isBeforeCreation"
              @click="toggleDay(day)"
            >
              {{ day.day }}
              <span v-if="day.isToday" class="absolute -bottom-0.5 left-1/2 h-1 w-1 -translate-x-1/2 rounded-full bg-sacred-gold" />
            </button>
          </div>
        </div>

        <!-- Bulk actions -->
        <div class="mt-4 flex items-center justify-between border-t border-sacred-border-light pt-3">
          <p class="text-[10px] text-sacred-muted">
            {{ checkedInCount }} / {{ actionableDays.length }} days
          </p>
          <div class="flex gap-2">
            <button
              v-if="checkedInCount < actionableDays.length"
              class="min-h-[36px] rounded-lg px-3 text-[11px] font-medium text-sacred-gold transition duration-150 hover:bg-sacred-bg-hover active:scale-[0.97] disabled:opacity-50"
              :disabled="bulkActioning"
              @click="checkAllMonth"
            >
              Check all
            </button>
            <button
              v-if="checkedInCount > 0"
              class="min-h-[36px] rounded-lg px-3 text-[11px] font-medium text-sacred-text-secondary transition duration-150 hover:bg-sacred-bg-hover active:scale-[0.97] disabled:opacity-50"
              :disabled="bulkActioning"
              @click="uncheckAllMonth"
            >
              Uncheck all
            </button>
          </div>
        </div>

        <!-- Reset history -->
        <div class="mt-4 flex justify-center">
          <button
            v-if="!showResetConfirm"
            class="min-h-[36px] text-[11px] font-medium text-sacred-text-secondary/60 transition duration-150 hover:text-sacred-text-secondary"
            @click="showResetConfirm = true"
          >
            Reset history
          </button>
          <div v-else class="flex flex-col items-center gap-3 rounded-xl border border-red-200/50 bg-red-50/30 px-5 py-4">
            <p class="text-center text-xs text-sacred-text-secondary">
              This will delete all check-in records and reset the start date to today. This cannot be undone.
            </p>
            <div class="flex gap-2">
              <button
                class="min-h-[36px] rounded-lg px-4 text-xs font-medium text-sacred-text-secondary transition duration-150 hover:bg-sacred-bg-hover"
                @click="showResetConfirm = false"
              >
                Cancel
              </button>
              <button
                class="min-h-[36px] rounded-lg bg-red-500/90 px-4 text-xs font-medium text-white transition duration-150 active:scale-[0.97] disabled:opacity-50"
                :disabled="resetting"
                @click="resetHistory"
              >
                {{ resetting ? 'Resetting...' : 'Reset' }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
