<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'
import TaskItem from '@/components/TaskItem.vue'

interface Task {
  id: string
  title: string
  type: 'Recurring' | 'OneTime'
  checkedIn: boolean
  completedToday: boolean | null
  daysRemaining: number | null
  progress: number
  feedbackMessage: string | null
  saving: boolean
}

const api = useApi()
const router = useRouter()

function localDateStr(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// --- State ---
const tasks = ref<Task[]>([])
const loading = ref(true)
const feedbackMessages = ref<Record<string, string>>({})
const saving = ref<Record<string, boolean>>({})

// New task form
const showNewGoalForm = ref(false)
const newGoalTitle = ref('')
const newGoalType = ref<'Recurring' | 'OneTime'>('Recurring')
const newGoalTargetDate = ref('')
const newGoalSaving = ref(false)

// Computed task list with live state — hide skipped tasks
const showSkipped = ref(false)

function withLiveState(list: Task[]): Task[] {
  return list.map((t: Task) => ({
    ...t,
    feedbackMessage: feedbackMessages.value[t.id] ?? null,
    saving: saving.value[t.id] ?? false,
  }))
}

const activeTasks = computed(() =>
  tasks.value.filter((t: Task) => !t.checkedIn)
)

const recurringTasks = computed(() =>
  withLiveState(activeTasks.value.filter((t: Task) => t.type === 'Recurring'))
)

const milestoneTasks = computed(() =>
  withLiveState(activeTasks.value.filter((t: Task) => t.type === 'OneTime'))
)

const completedTasks = computed<Task[]>(() =>
  withLiveState(tasks.value.filter((t: Task) => t.checkedIn && t.completedToday === true))
)

const showCompleted = ref(false)

const skippedTasks = computed<Task[]>(() =>
  tasks.value
    .filter((t: Task) => t.checkedIn && t.completedToday === false)
    .map((t: Task) => ({
      ...t,
      feedbackMessage: feedbackMessages.value[t.id] ?? null,
      saving: saving.value[t.id] ?? false,
    }))
)

// --- Loaders ---
async function loadTasks() {
  loading.value = true
  try {
    // Load recurring tasks
    const todayData = await api.get<any>(`/goals/today?date=${localDateStr()}`)
    const todayItems = Array.isArray(todayData) ? todayData : (todayData?.goals || todayData?.items || [])
    const recurring: Task[] = todayItems.map((g: any) => {
      const checkedIn = g.checkedInToday ?? g.checked_in_today ?? (g.checkIn != null)
      const completedToday = g.completedToday ?? g.completed_today ?? g.checkIn?.completed ?? null
      const currentStreak = g.currentStreak ?? g.current_streak ?? 0
      const longestStreak = g.longestStreak ?? g.longest_streak ?? 0
      return {
        id: g.id,
        title: g.title,
        type: 'Recurring' as const,
        checkedIn,
        completedToday,
        daysRemaining: null,
        progress: 0,
        feedbackMessage: null,
        saving: false,
        _currentStreak: currentStreak,
        _longestStreak: longestStreak,
      }
    })

    // Generate feedback for pre-checked-in tasks
    for (const t of recurring) {
      if (t.checkedIn) {
        const streak = (t as any)._currentStreak
        const longest = (t as any)._longestStreak
        feedbackMessages.value[t.id] = getCheckInFeedback(
          streak > 0 && t.completedToday ? streak - 1 : 0,
          longest,
          t.completedToday ?? false
        )
      }
    }

    // Load all goals for milestones
    const allData = await api.get<any>('/goals')
    const allItems = Array.isArray(allData) ? allData : (allData?.goals || allData?.items || [])
    const milestones: Task[] = allItems
      .filter((g: any) => (g.type ?? '') === 'OneTime' && !g.completedAt && !g.completed_at)
      .map((g: any) => {
        const checkIn = g.checkIn ?? g.check_in ?? null
        return {
          id: g.id,
          title: g.title,
          type: 'OneTime' as const,
          checkedIn: checkIn != null,
          completedToday: checkIn?.completed ?? null,
          daysRemaining: g.daysRemaining ?? g.days_remaining ?? null,
          progress: g.progress ?? 0,
          feedbackMessage: null,
          saving: false,
        }
      })
      .sort((a: Task, b: Task) => {
        const aD = a.daysRemaining ?? 9999
        const bD = b.daysRemaining ?? 9999
        if (aD <= 0 && bD > 0) return -1
        if (bD <= 0 && aD > 0) return 1
        return aD - bD
      })

    // Recurring first, then milestones
    tasks.value = [...recurring, ...milestones]
  } catch {
    tasks.value = []
  } finally {
    loading.value = false
  }
}

function getCheckInFeedback(currentStreak: number, longestStreak: number, completed: boolean): string {
  const streak = completed ? currentStreak + 1 : 0

  if (completed) {
    if (streak === 1) {
      const fresh = [
        'A single step. That is all it ever takes.',
        'The seed has been planted. Trust the process.',
        'Today you chose yourself. That matters.',
      ]
      return fresh[Math.floor(Math.random() * fresh.length)]
    }
    if (streak === 3) return 'Three days. A pattern is forming. Stay with it.'
    if (streak === 7) return 'One full week. Your discipline is becoming devotion.'
    if (streak === 14) return 'Two weeks of showing up. This is no longer effort — it is who you are becoming.'
    if (streak === 21) return 'Twenty-one days. What began as intention is now dharma. The Gita teaches: the self is its own friend and its own enemy.'
    if (streak === 30) return 'A full month. You have proven something to yourself that no one can take away.'
    if (streak > 30 && streak % 10 === 0) return `${streak} days. Your consistency speaks louder than any intention ever could.`
    if (streak > longestStreak && longestStreak > 0) return `A new personal record — ${streak} days. You have surpassed your past self.`
    const ongoing = [
      `${streak} days and counting. Keep showing up.`,
      'Another day honored. The practice deepens.',
      'Consistency is the quiet form of courage.',
      'You showed up again. That is the whole practice.',
    ]
    return ongoing[Math.floor(Math.random() * ongoing.length)]
  } else {
    if (longestStreak >= 7) {
      return 'A pause is not a failure. Even the river rests in still pools before flowing on.'
    }
    const missed = [
      'Rest is also practice. Tomorrow is a new beginning.',
      'Not today — and that is honest. Honesty is the first discipline.',
      'The path does not disappear because you paused. It waits.',
      'Be gentle with yourself. Even the moon wanes before it grows full again.',
    ]
    return missed[Math.floor(Math.random() * missed.length)]
  }
}

async function onDone(id: string) {
  saving.value[id] = true
  try {
    await api.post(`/goals/${id}/checkin`, { completed: true, date: localDateStr() })
    const task = tasks.value.find((t: Task) => t.id === id) as any
    if (task) {
      const streak = task._currentStreak ?? 0
      const longest = task._longestStreak ?? 0
      feedbackMessages.value[id] = getCheckInFeedback(streak, longest, true)
      task.checkedIn = true
      task.completedToday = true
      task._currentStreak = streak + 1
    }
  } catch {} finally {
    saving.value[id] = false
  }
}

async function onSkip(id: string) {
  saving.value[id] = true
  try {
    await api.post(`/goals/${id}/checkin`, { completed: false, date: localDateStr() })
    const task = tasks.value.find((t: Task) => t.id === id) as any
    if (task) {
      const longest = task._longestStreak ?? 0
      feedbackMessages.value[id] = getCheckInFeedback(0, longest, false)
      task.checkedIn = true
      task.completedToday = false
      task._currentStreak = 0
    }
  } catch {} finally {
    saving.value[id] = false
  }
}

async function onUndo(id: string) {
  saving.value[id] = true
  try {
    await api.delete(`/goals/${id}/checkin?date=${localDateStr()}`)
    const task = tasks.value.find((t: Task) => t.id === id)
    if (task) {
      task.checkedIn = false
      task.completedToday = null
    }
    delete feedbackMessages.value[id]
  } catch {} finally {
    saving.value[id] = false
  }
}

async function onDelete(id: string) {
  try {
    await api.delete(`/goals/${id}`)
    tasks.value = tasks.value.filter((t: Task) => t.id !== id)
    delete feedbackMessages.value[id]
    delete saving.value[id]
  } catch {}
}

async function onProgress(id: string, value: number) {
  saving.value[id] = true
  try {
    await api.patch(`/goals/${id}`, { progress: value })
    const task = tasks.value.find((t: Task) => t.id === id)
    if (task) task.progress = value
  } catch {} finally {
    saving.value[id] = false
  }
}

function onNavigate(id: string) {
  router.push(`/app/journey/goals/${id}`)
}

async function createGoal() {
  if (!newGoalTitle.value.trim()) return
  if (newGoalType.value === 'OneTime' && !newGoalTargetDate.value) return
  newGoalSaving.value = true
  try {
    const payload: any = { title: newGoalTitle.value.trim(), type: newGoalType.value }
    if (newGoalType.value === 'OneTime' && newGoalTargetDate.value) payload.targetDate = newGoalTargetDate.value
    await api.post('/goals', payload)
    newGoalTitle.value = ''
    newGoalType.value = 'Recurring'
    newGoalTargetDate.value = ''
    showNewGoalForm.value = false
    await loadTasks()
  } catch {} finally {
    newGoalSaving.value = false
  }
}

onMounted(() => { loadTasks() })
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-6 sm:py-10">
    <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Your Dharma</p>
    <p class="mt-3 font-serif text-xl sm:text-2xl font-bold tracking-wide text-[#2b1e10]">What needs your attention today?</p>

    <!-- Loading -->
    <div v-if="loading" class="mt-6 space-y-3">
      <div v-for="i in 2" :key="i" class="h-14 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
    </div>

    <!-- No tasks -->
    <div v-else-if="tasks.length === 0 && !showNewGoalForm" class="mt-6 text-center">
      <p class="text-sm text-[#6b5740]">You haven't set any tasks yet.</p>
      <button
        @click="showNewGoalForm = true"
        class="mt-4 min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-3 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97]"
      >
        Set your first task
      </button>
    </div>

    <!-- New task form -->
    <div v-if="showNewGoalForm" class="mt-6">
      <div class="mb-3 flex justify-center gap-2">
        <button @click="newGoalType = 'Recurring'" class="flex min-h-[44px] items-center gap-1.5 rounded-2xl border px-4 py-2.5 text-xs font-semibold transition duration-200 active:scale-[0.97]" :class="newGoalType === 'Recurring' ? 'border-[#c4873b] text-[#c4873b] bg-[rgba(196,135,59,0.06)]' : 'border-[rgba(139,90,43,0.12)] text-[#6b5740]'">
          <SacredIcons name="flame" :size="14" /> Daily practice
        </button>
        <button @click="newGoalType = 'OneTime'" class="flex min-h-[44px] items-center gap-1.5 rounded-2xl border px-4 py-2.5 text-xs font-semibold transition duration-200 active:scale-[0.97]" :class="newGoalType === 'OneTime' ? 'border-[#c4873b] text-[#c4873b] bg-[rgba(196,135,59,0.06)]' : 'border-[rgba(139,90,43,0.12)] text-[#6b5740]'">
          <SacredIcons name="target" :size="14" /> Reach a milestone
        </button>
      </div>
      <input v-model="newGoalTitle" type="text" :placeholder="newGoalType === 'Recurring' ? 'I want to practice...' : 'I want to achieve...'" class="w-full rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] px-4 py-3 text-sm text-[#2b1e10] placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]" @keyup.enter="newGoalType === 'Recurring' ? createGoal() : undefined" />
      <input v-if="newGoalType === 'OneTime'" v-model="newGoalTargetDate" type="date" class="mt-2 w-full rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] px-4 py-3 text-sm text-[#2b1e10] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]" />
      <div class="mt-3 flex justify-center gap-2">
        <button @click="createGoal" :disabled="newGoalSaving || !newGoalTitle.trim() || (newGoalType === 'OneTime' && !newGoalTargetDate)" class="min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97] disabled:opacity-60">
          {{ newGoalSaving ? 'Saving...' : 'Save' }}
        </button>
        <button @click="showNewGoalForm = false; newGoalType = 'Recurring'; newGoalTargetDate = ''" class="min-h-[44px] rounded-full border border-[rgba(139,90,43,0.15)] px-5 py-2.5 text-sm font-medium text-[#6b5740] transition duration-200 active:scale-[0.97]">
          Cancel
        </button>
      </div>
    </div>

    <!-- Recurring Tasks -->
    <div v-if="recurringTasks.length > 0" class="mt-6">
      <div class="flex items-center gap-1.5 mb-3">
        <SacredIcons name="recurring" :size="14" class="text-[#a38d6d]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Recurring Tasks</p>
      </div>
      <ul class="space-y-3">
        <TaskItem
          v-for="task in recurringTasks"
          :key="task.id"
          :task="task"
          @done="onDone"
          @skip="onSkip"
          @undo="onUndo"
          @navigate="onNavigate"
          @progress="onProgress"
          @delete="onDelete"
        />
      </ul>
    </div>

    <!-- Milestones -->
    <div v-if="milestoneTasks.length > 0" class="mt-6">
      <div class="flex items-center gap-1.5 mb-3">
        <SacredIcons name="target" :size="14" class="text-[#a38d6d]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Milestones</p>
      </div>
      <ul class="space-y-3">
        <TaskItem
          v-for="task in milestoneTasks"
          :key="task.id"
          :task="task"
          @done="onDone"
          @skip="onSkip"
          @undo="onUndo"
          @navigate="onNavigate"
          @progress="onProgress"
          @delete="onDelete"
        />
      </ul>
    </div>

    <!-- Completed tasks collapsed -->
    <div v-if="completedTasks.length > 0" class="mt-4">
      <button
        @click="showCompleted = !showCompleted"
        class="flex min-h-[44px] items-center gap-1.5 text-xs font-medium text-[#7aa87a] transition duration-200 hover:text-[#5a8a5a]"
      >
        <SacredIcons name="check" :size="12" />
        {{ completedTasks.length }} completed
        <span class="text-[10px]">{{ showCompleted ? '&#9650;' : '&#9660;' }}</span>
      </button>
      <ul v-if="showCompleted" class="mt-2 space-y-3">
        <TaskItem
          v-for="task in completedTasks"
          :key="task.id"
          :task="task"
          @done="onDone"
          @skip="onSkip"
          @undo="onUndo"
          @navigate="onNavigate"
          @progress="onProgress"
          @delete="onDelete"
        />
      </ul>
    </div>

    <!-- Skipped tasks collapsed -->
    <div v-if="skippedTasks.length > 0" class="mt-2">
      <button
        @click="showSkipped = !showSkipped"
        class="flex min-h-[44px] items-center gap-1.5 text-xs font-medium text-[#9a8568] transition duration-200 hover:text-[#6b5740]"
      >
        <SacredIcons name="skip" :size="12" />
        {{ skippedTasks.length }} skipped
        <span class="text-[10px]">{{ showSkipped ? '&#9650;' : '&#9660;' }}</span>
      </button>
      <ul v-if="showSkipped" class="mt-2 space-y-3">
        <TaskItem
          v-for="task in skippedTasks"
          :key="task.id"
          :task="task"
          @done="onDone"
          @skip="onSkip"
          @undo="onUndo"
          @navigate="onNavigate"
          @progress="onProgress"
          @delete="onDelete"
        />
      </ul>
    </div>

    <!-- Add task button -->
    <button
      v-if="tasks.length > 0 && !showNewGoalForm"
      @click="showNewGoalForm = true"
      class="mt-4 flex min-h-[44px] items-center justify-center gap-1.5 text-xs font-medium text-[#c4873b] transition duration-200 hover:text-[#8b5a1b] active:scale-[0.97]"
    >
      + Add task
    </button>
  </div>
</template>
