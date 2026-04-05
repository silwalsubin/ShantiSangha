<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
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

interface DayEntry {
  date: string
  label: string
  checkin: CheckIn | null
  isToday: boolean
  isFuture: boolean
}

const goal = ref<Goal | null>(null)
const checkIns = ref<CheckIn[]>([])
const loading = ref(true)

const editingWhy = ref(false)
const whyInput = ref('')
const savingWhy = ref(false)

function buildDayEntries(): DayEntry[] {
  if (!goal.value) return []

  const createdDate = goal.value.createdAt.includes('T')
    ? goal.value.createdAt.split('T')[0]
    : goal.value.createdAt.slice(0, 10)

  const now = new Date()
  const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`

  const checkinMap = new Map<string, CheckIn>()
  for (const ci of checkIns.value) {
    checkinMap.set(ci.date, ci)
  }

  const entries: DayEntry[] = []
  const start = new Date(createdDate + 'T12:00:00')
  const end = new Date(todayStr + 'T12:00:00')

  const cursor = new Date(end)
  while (cursor >= start) {
    const dateStr = `${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, '0')}-${String(cursor.getDate()).padStart(2, '0')}`
    entries.push({
      date: dateStr,
      label: formatDate(dateStr),
      checkin: checkinMap.get(dateStr) ?? null,
      isToday: dateStr === todayStr,
      isFuture: cursor > end,
    })
    cursor.setDate(cursor.getDate() - 1)
  }

  return entries
}

const dayEntries = computed(() => buildDayEntries())

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

    const items = data.checkIns ?? data.checkins ?? []
    checkIns.value = items.map((c: any) => ({
      id: c.id,
      date: c.date,
      completed: c.completed ?? false,
      note: c.note ?? null,
    }))
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

      <!-- Day-by-day Check-ins -->
      <div v-if="goal.type === 'Recurring'" class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Daily Record</p>

        <div v-if="dayEntries.length === 0" class="mt-4 text-sm text-sacred-text-secondary">
          No days recorded yet.
        </div>

        <ul v-else class="mt-4 space-y-1.5">
          <li
            v-for="day in dayEntries"
            :key="day.date"
            class="flex items-center gap-3 rounded-xl px-3 py-2.5"
            :class="day.isToday ? 'bg-sacred-bg-hover' : ''"
          >
            <!-- Status indicator -->
            <div
              class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full"
              :class="day.checkin?.completed
                ? 'bg-gradient-to-br from-sacred-gold to-sacred-gold-dark'
                : day.checkin && !day.checkin.completed
                  ? 'border border-sacred-border-focus bg-sacred-bg-card-deep'
                  : 'border border-dashed border-sacred-border-light bg-transparent'"
            >
              <SacredIcons v-if="day.checkin?.completed" name="check" :size="12" class="text-white" />
              <SacredIcons v-else-if="day.checkin && !day.checkin.completed" name="skip" :size="12" class="text-sacred-muted-light" />
              <span v-else class="text-[10px] text-sacred-muted-light">--</span>
            </div>

            <!-- Date and note -->
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <p class="text-xs font-medium text-sacred-text">{{ day.label }}</p>
                <span v-if="day.isToday" class="text-[9px] uppercase tracking-[0.15em] text-sacred-gold">Today</span>
              </div>
              <p v-if="day.checkin?.note" class="mt-0.5 truncate text-xs leading-relaxed text-sacred-text-secondary">{{ day.checkin.note }}</p>
            </div>
          </li>
        </ul>
      </div>
    </template>
  </div>
</template>
