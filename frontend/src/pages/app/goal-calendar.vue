<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const route = useRoute()
const router = useRouter()
const api = useApi()

const goalId = computed(() => route.params.id as string)

interface GoalInfo {
  id: string
  title: string
  currentStreak: number
  longestStreak: number
  createdAt: string
}

interface CheckIn {
  id: string
  date: string
  completed: boolean
  note: string | null
}

interface CalDay {
  date: string
  day: number
  checkin: CheckIn | null
  isToday: boolean
  isFuture: boolean
  isBeforeCreation: boolean
  isCurrentMonth: boolean
}

const goalInfo = ref<GoalInfo | null>(null)
const checkIns = ref<CheckIn[]>([])
const loading = ref(true)
const calendarLoading = ref(false)
const togglingDate = ref<string | null>(null)
const bulkActioning = ref(false)
const showCheckAllConfirm = ref(false)
const showUncheckAllConfirm = ref(false)
const showResetConfirm = ref(false)
const resetting = ref(false)

const now = new Date()
const calYear = ref(now.getFullYear())
const calMonth = ref(now.getMonth())

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
  if (!goalInfo.value) return ''
  const ca = goalInfo.value.createdAt
  return ca.includes('T') ? ca.split('T')[0] : ca.slice(0, 10)
})

const canGoPrev = computed(() => {
  if (!goalInfo.value) return false
  const [y, m] = goalCreatedDate.value.split('-').map(Number)
  return calYear.value > y || (calYear.value === y && calMonth.value > m - 1)
})

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

const checkinMap = computed(() => {
  const m = new Map<string, CheckIn>()
  for (const ci of checkIns.value) m.set(ci.date, ci)
  return m
})

const calendarDays = computed((): CalDay[] => {
  const firstDay = new Date(calYear.value, calMonth.value, 1)
  const startDow = firstDay.getDay()
  const daysInMonth = new Date(calYear.value, calMonth.value + 1, 0).getDate()
  const today = todayStr.value
  const created = goalCreatedDate.value

  const days: CalDay[] = []
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

const checkedInCount = computed(() => calendarDays.value.filter(d => d.isCurrentMonth && d.checkin).length)
const actionableDays = computed(() => calendarDays.value.filter(d => d.isCurrentMonth && !d.isFuture && !d.isBeforeCreation))

async function loadCheckIns() {
  if (!goalInfo.value) return
  calendarLoading.value = true
  try {
    const from = `${calYear.value}-${String(calMonth.value + 1).padStart(2, '0')}-01`
    const lastDay = new Date(calYear.value, calMonth.value + 1, 0).getDate()
    const to = `${calYear.value}-${String(calMonth.value + 1).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`
    const items = await api.get<any[]>(`/goals/${goalInfo.value.id}/checkins?from=${from}&to=${to}`)
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

watch([calYear, calMonth], () => { loadCheckIns() })

async function toggleDay(day: CalDay) {
  if (!goalInfo.value || day.isFuture || day.isBeforeCreation || !day.isCurrentMonth) return
  togglingDate.value = day.date
  try {
    if (day.checkin) {
      await api.delete(`/goals/${goalInfo.value.id}/checkin?date=${day.date}`)
      checkIns.value = checkIns.value.filter(c => c.date !== day.date)
    } else {
      const result = await api.post<any>(`/goals/${goalInfo.value.id}/checkin`, { completed: true, date: day.date })
      checkIns.value.push({ id: result.id, date: result.date, completed: result.completed, note: result.note ?? null })
    }
    await refreshStreaks()
  } finally {
    togglingDate.value = null
  }
}

async function checkAllMonth() {
  if (!goalInfo.value) return
  bulkActioning.value = true
  try {
    for (const day of actionableDays.value.filter(d => !d.checkin)) {
      const result = await api.post<any>(`/goals/${goalInfo.value.id}/checkin`, { completed: true, date: day.date })
      checkIns.value.push({ id: result.id, date: result.date, completed: result.completed, note: result.note ?? null })
    }
    await refreshStreaks()
  } finally {
    bulkActioning.value = false
  }
}

async function uncheckAllMonth() {
  if (!goalInfo.value) return
  bulkActioning.value = true
  try {
    for (const day of actionableDays.value.filter(d => d.checkin)) {
      await api.delete(`/goals/${goalInfo.value.id}/checkin?date=${day.date}`)
      checkIns.value = checkIns.value.filter(c => c.date !== day.date)
    }
    await refreshStreaks()
  } finally {
    bulkActioning.value = false
  }
}

async function refreshStreaks() {
  if (!goalInfo.value) return
  try {
    const data = await api.get<any>(`/goals/${goalInfo.value.id}?date=${todayStr.value}`)
    goalInfo.value.currentStreak = data.currentStreak ?? data.current_streak ?? 0
    goalInfo.value.longestStreak = data.longestStreak ?? data.longest_streak ?? 0
  } catch { /* ignore */ }
}

async function resetHistory() {
  if (!goalInfo.value) return
  resetting.value = true
  try {
    await api.post(`/goals/${goalInfo.value.id}/reset`)
    const data = await api.get<any>(`/goals/${goalInfo.value.id}?date=${todayStr.value}`)
    goalInfo.value = {
      id: data.id,
      title: data.title,
      currentStreak: data.currentStreak ?? 0,
      longestStreak: data.longestStreak ?? 0,
      createdAt: data.createdAt ?? '',
    }
    const now = new Date()
    calYear.value = now.getFullYear()
    calMonth.value = now.getMonth()
    await loadCheckIns()
  } finally {
    resetting.value = false
    showResetConfirm.value = false
  }
}

async function load() {
  loading.value = true
  try {
    const data = await api.get<any>(`/goals/${goalId.value}?date=${todayStr.value}`)
    goalInfo.value = {
      id: data.id,
      title: data.title,
      currentStreak: data.currentStreak ?? data.current_streak ?? 0,
      longestStreak: data.longestStreak ?? data.longest_streak ?? 0,
      createdAt: data.createdAt ?? data.created_at ?? '',
    }
    await loadCheckIns()
  } catch {
    goalInfo.value = null
  } finally {
    loading.value = false
  }
}

onMounted(() => { load() })
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Back button -->
    <button
      class="flex min-h-[44px] items-center gap-1.5 text-sm font-medium text-sacred-gold transition duration-200 hover:text-sacred-gold-dark"
      @click="router.back()"
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M12 19l-7-7 7-7"/></svg>
      Back
    </button>

    <!-- Loading -->
    <div v-if="loading" class="space-y-4">
      <div class="h-8 w-3/4 animate-pulse rounded-xl bg-sacred-bg-hover-strong" />
      <div class="h-64 animate-pulse rounded-2xl bg-sacred-bg-hover" />
    </div>

    <template v-else-if="goalInfo">
      <!-- Title + streaks -->
      <div class="text-center">
        <h1 class="font-serif text-lg font-bold text-sacred-text">{{ goalInfo.title }}</h1>
        <div class="mt-2 flex justify-center gap-6">
          <div>
            <span class="text-lg font-bold text-sacred-gold">{{ goalInfo.currentStreak }}</span>
            <span class="ml-1 text-[10px] uppercase tracking-[0.15em] text-sacred-muted">current</span>
          </div>
          <div>
            <span class="text-lg font-bold text-sacred-gold">{{ goalInfo.longestStreak }}</span>
            <span class="ml-1 text-[10px] uppercase tracking-[0.15em] text-sacred-muted">longest</span>
          </div>
        </div>
      </div>

      <!-- Reset history (global action) -->
      <div class="flex justify-center">
        <button
          class="flex items-center gap-1.5 text-[11px] font-medium text-sacred-text-secondary/50 transition duration-150 hover:text-sacred-text-secondary"
          @click="showResetConfirm = true"
        >
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>
          Reset history
        </button>
      </div>

      <!-- Calendar -->
      <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
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
                  ? 'text-sacred-muted/50 cursor-default'
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

        <!-- Footer -->
        <div class="mt-4 flex items-center justify-between border-t border-sacred-border-light pt-3">
          <p class="text-[10px] text-sacred-muted">
            {{ checkedInCount }} / {{ actionableDays.length }} days
          </p>
          <div class="flex gap-3">
            <button
              v-if="checkedInCount < actionableDays.length"
              class="text-[11px] font-medium text-sacred-gold transition duration-150 hover:text-sacred-gold-dark disabled:opacity-40"
              :disabled="bulkActioning"
              @click="showCheckAllConfirm = true"
            >
              Check all
            </button>
            <button
              v-if="checkedInCount > 0"
              class="text-[11px] font-medium text-sacred-text-secondary transition duration-150 hover:text-sacred-text disabled:opacity-40"
              :disabled="bulkActioning"
              @click="showUncheckAllConfirm = true"
            >
              Uncheck all
            </button>
          </div>
        </div>
      </div>

      <!-- Confirmation dialogs -->
      <div v-if="showCheckAllConfirm" class="rounded-xl border border-sacred-gold/20 bg-sacred-gold/5 px-5 py-4">
        <p class="text-center text-xs text-sacred-text-secondary">
          Mark all remaining days in {{ monthLabel }} as completed?
        </p>
        <div class="mt-3 flex justify-center gap-2">
          <button
            class="min-h-[36px] rounded-lg px-4 text-xs font-medium text-sacred-text-secondary transition duration-150 hover:bg-sacred-bg-hover"
            @click="showCheckAllConfirm = false"
          >
            Cancel
          </button>
          <button
            class="min-h-[36px] rounded-lg bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-4 text-xs font-medium text-white transition duration-150 active:scale-[0.97] disabled:opacity-50"
            :disabled="bulkActioning"
            @click="showCheckAllConfirm = false; checkAllMonth()"
          >
            Confirm
          </button>
        </div>
      </div>

      <div v-if="showUncheckAllConfirm" class="rounded-xl border border-red-200/50 bg-red-50/30 px-5 py-4">
        <p class="text-center text-xs text-sacred-text-secondary">
          Remove all check-ins for {{ monthLabel }}?
        </p>
        <div class="mt-3 flex justify-center gap-2">
          <button
            class="min-h-[36px] rounded-lg px-4 text-xs font-medium text-sacred-text-secondary transition duration-150 hover:bg-sacred-bg-hover"
            @click="showUncheckAllConfirm = false"
          >
            Cancel
          </button>
          <button
            class="min-h-[36px] rounded-lg bg-red-500/90 px-4 text-xs font-medium text-white transition duration-150 active:scale-[0.97] disabled:opacity-50"
            :disabled="bulkActioning"
            @click="showUncheckAllConfirm = false; uncheckAllMonth()"
          >
            Confirm
          </button>
        </div>
      </div>

      <div v-if="showResetConfirm" class="rounded-xl border border-red-200/50 bg-red-50/30 px-5 py-4">
        <p class="text-center text-xs text-sacred-text-secondary">
          This will delete all check-in records and reset the start date to today. This cannot be undone.
        </p>
        <div class="mt-3 flex justify-center gap-2">
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
            {{ resetting ? 'Resetting...' : 'Confirm' }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
