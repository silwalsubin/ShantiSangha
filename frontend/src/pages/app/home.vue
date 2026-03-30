<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()
const router = useRouter()

function localDateStr(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// --- Goals data ---
interface GoalToday {
  id: string
  title: string
  currentStreak: number
  longestStreak: number
  checkedInToday: boolean
  completedToday: boolean | null
}

interface Milestone {
  id: string
  title: string
  targetDate: string | null
  completedAt: string | null
  daysRemaining: number | null
}

const recurringGoals = ref<GoalToday[]>([])
const milestones = ref<Milestone[]>([])
const goalsLoading = ref(true)
const goalsCheckedIn = ref<Record<string, boolean>>({})
const goalsSaving = ref<Record<string, boolean>>({})
const goalNotes = ref<Record<string, string>>({})
const showNoteInput = ref<Record<string, boolean>>({})
const goalFeedbackMessages = ref<Record<string, string>>({})

// New goal inline form
const showNewGoalForm = ref(false)
const newGoalTitle = ref('')
const newGoalType = ref<'Recurring' | 'OneTime'>('Recurring')
const newGoalTargetDate = ref('')
const newGoalSaving = ref(false)

// --- Loaders ---
async function loadGoals() {
  goalsLoading.value = true
  try {
    const todayData = await api.get<any>(`/goals/today?date=${localDateStr()}`)
    const todayItems = Array.isArray(todayData) ? todayData : (todayData?.goals || todayData?.items || [])
    recurringGoals.value = todayItems.map((g: any) => ({
      id: g.id,
      title: g.title,
      currentStreak: g.currentStreak ?? g.current_streak ?? 0,
      longestStreak: g.longestStreak ?? g.longest_streak ?? 0,
      checkedInToday: g.checkedInToday ?? g.checked_in_today ?? (g.checkIn != null),
      completedToday: g.completedToday ?? g.completed_today ?? g.checkIn?.completed ?? null,
    }))
    for (const g of recurringGoals.value) {
      if (g.checkedInToday) {
        goalsCheckedIn.value[g.id] = true
        goalFeedbackMessages.value[g.id] = getCheckInFeedback(
          { ...g, currentStreak: g.completedToday ? g.currentStreak - 1 : 0, longestStreak: g.longestStreak },
          g.completedToday ?? false
        )
      }
    }

    // Load milestones
    const allData = await api.get<any>('/goals')
    const allItems = Array.isArray(allData) ? allData : (allData?.goals || allData?.items || [])
    milestones.value = allItems
      .filter((g: any) => (g.type ?? '') === 'OneTime' && !g.completedAt && !g.completed_at)
      .map((g: any) => ({
        id: g.id,
        title: g.title,
        targetDate: g.targetDate ?? g.target_date ?? null,
        completedAt: g.completedAt ?? g.completed_at ?? null,
        daysRemaining: g.daysRemaining ?? g.days_remaining ?? null,
      }))
      .sort((a: Milestone, b: Milestone) => {
        // Overdue first, then by days remaining ascending
        const aD = a.daysRemaining ?? 9999
        const bD = b.daysRemaining ?? 9999
        if (aD <= 0 && bD > 0) return -1
        if (bD <= 0 && aD > 0) return 1
        return aD - bD
      })
  } catch {
    recurringGoals.value = []
    milestones.value = []
  } finally {
    goalsLoading.value = false
  }
}

function getCheckInFeedback(goal: GoalToday, completed: boolean): string {
  const streak = completed ? goal.currentStreak + 1 : 0
  const longest = goal.longestStreak

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
    if (streak > longest && longest > 0) return `A new personal record — ${streak} days. You have surpassed your past self.`
    const ongoing = [
      `${streak} days and counting. Keep showing up.`,
      'Another day honored. The practice deepens.',
      'Consistency is the quiet form of courage.',
      'You showed up again. That is the whole practice.',
    ]
    return ongoing[Math.floor(Math.random() * ongoing.length)]
  } else {
    if (longest >= 7) {
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

async function checkInGoal(goalId: string, completed: boolean) {
  goalsSaving.value[goalId] = true
  try {
    const note = goalNotes.value[goalId]?.trim() || undefined
    await api.post(`/goals/${goalId}/checkin`, { completed, note, date: localDateStr() })
    const goal = recurringGoals.value.find(g => g.id === goalId)
    if (goal) {
      goalFeedbackMessages.value[goalId] = getCheckInFeedback(goal, completed)
      goal.checkedInToday = true
      goal.completedToday = completed
      if (completed) goal.currentStreak += 1
      else goal.currentStreak = 0
    }
    goalsCheckedIn.value[goalId] = true
    showNoteInput.value[goalId] = false
  } catch {
    // silently fail
  } finally {
    goalsSaving.value[goalId] = false
  }
}

async function undoCheckIn(goalId: string) {
  goalsSaving.value[goalId] = true
  try {
    await api.delete(`/goals/${goalId}/checkin?date=${localDateStr()}`)
    const goal = recurringGoals.value.find(g => g.id === goalId)
    if (goal) {
      goal.checkedInToday = false
      goal.completedToday = null
    }
    delete goalsCheckedIn.value[goalId]
    delete goalFeedbackMessages.value[goalId]
  } catch {
    // silently fail
  } finally {
    goalsSaving.value[goalId] = false
  }
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
    await loadGoals()
  } catch {
    // silently fail
  } finally {
    newGoalSaving.value = false
  }
}

onMounted(() => { loadGoals() })
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-6 sm:py-10">
    <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Your Dharma</p>
    <p class="mt-3 font-serif text-xl sm:text-2xl font-bold tracking-wide text-[#2b1e10]">What needs your attention today?</p>

      <!-- Loading -->
      <div v-if="goalsLoading" class="mt-6 space-y-3">
        <div v-for="i in 2" :key="i" class="h-14 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <!-- No tasks -->
      <div v-else-if="recurringGoals.length === 0 && milestones.length === 0 && !showNewGoalForm" class="mt-6 text-center">
        <p class="text-sm text-[#6b5740]">You haven't set any tasks yet.</p>
        <button
          @click="showNewGoalForm = true"
          class="mt-4 min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-3 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97]"
        >
          Set your first task
        </button>
      </div>

      <!-- New goal form -->
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

      <!-- Task check-in list -->
      <ul v-if="recurringGoals.length > 0" class="mt-6 space-y-3">
        <li
          v-for="goal in recurringGoals"
          :key="goal.id"
          class="rounded-2xl border px-4 py-3 transition-all duration-300"
          :class="goalsCheckedIn[goal.id]
            ? 'border-[rgba(122,168,122,0.25)] bg-[rgba(122,168,122,0.06)]'
            : 'border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)]'"
        >
          <div class="flex items-center gap-3">
            <!-- Check circle (tap to undo) -->
            <button
              class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full transition-all duration-300"
              :class="goalsCheckedIn[goal.id]
                ? (goal.completedToday
                  ? 'bg-gradient-to-br from-[#7aa87a] to-[#5a8a5a] hover:from-[#6a9a6a] hover:to-[#4a7a4a]'
                  : 'border-2 border-[rgba(139,90,43,0.2)] bg-[rgba(250,245,237,0.6)] hover:bg-[rgba(139,90,43,0.08)]')
                : 'border-2 border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.6)]'"
              :disabled="!goalsCheckedIn[goal.id] || goalsSaving[goal.id]"
              @click.stop="goalsCheckedIn[goal.id] ? undoCheckIn(goal.id) : undefined"
            >
              <SacredIcons v-if="goalsCheckedIn[goal.id] && goal.completedToday" name="check" :size="14" class="text-white" />
              <SacredIcons v-else-if="goalsCheckedIn[goal.id]" name="skip" :size="12" class="text-[#b5996f]" />
            </button>
            <!-- Title -->
            <button
              class="flex-1 text-left text-sm font-medium transition duration-200 hover:text-[#c4873b]"
              :class="goalsCheckedIn[goal.id] && goal.completedToday ? 'text-[#7aa87a] line-through decoration-[rgba(122,168,122,0.4)]' : 'text-[#2b1e10]'"
              @click="router.push(`/app/journey/goals/${goal.id}`)"
            >{{ goal.title }}</button>
            <SacredIcons name="recurring" :size="14" class="shrink-0 text-[#b5996f] opacity-40" />
          </div>
          <!-- Spiritual feedback after check-in -->
          <p v-if="goalsCheckedIn[goal.id] && goalFeedbackMessages[goal.id]" class="mt-2 ml-10 font-serif text-xs italic leading-relaxed text-[#9a8568]">
            {{ goalFeedbackMessages[goal.id] }}
          </p>
          <!-- Check-in buttons -->
          <div v-if="!goalsCheckedIn[goal.id]" class="mt-2 ml-10 flex items-center gap-2">
            <button @click="checkInGoal(goal.id, true)" :disabled="goalsSaving[goal.id]" class="flex min-h-[44px] items-center gap-1.5 rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2 text-xs font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97] disabled:opacity-60">
              <SacredIcons name="check" :size="14" /> Done
            </button>
            <button @click="checkInGoal(goal.id, false)" :disabled="goalsSaving[goal.id]" class="flex min-h-[44px] items-center gap-1.5 rounded-xl border border-[rgba(139,90,43,0.15)] px-4 py-2 text-xs font-medium text-[#6b5740] transition duration-200 active:scale-[0.97] disabled:opacity-60 hover:bg-[rgba(196,135,59,0.06)]">
              <SacredIcons name="skip" :size="12" /> Not today
            </button>
          </div>
        </li>
      </ul>

      <!-- Milestones -->
      <ul v-if="milestones.length > 0" class="mt-6 space-y-3">
        <li
          v-for="m in milestones"
          :key="m.id"
          class="cursor-pointer rounded-2xl border px-4 py-3 transition duration-200 active:scale-[0.99]"
          :class="m.daysRemaining != null && m.daysRemaining <= 0
            ? 'border-[rgba(180,90,60,0.25)] bg-[rgba(180,90,60,0.06)]'
            : 'border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)]'"
          @click="router.push(`/app/journey/goals/${m.id}`)"
        >
          <div class="flex items-center gap-3">
            <SacredIcons name="target" :size="16" class="shrink-0 text-[#c4873b]" />
            <p class="flex-1 text-sm font-medium text-[#2b1e10]">{{ m.title }}</p>
            <span v-if="m.daysRemaining != null" class="shrink-0 font-serif text-xs" :class="m.daysRemaining <= 0 ? 'font-bold text-[#b45a3c]' : 'text-[#c4873b]'">
              {{ m.daysRemaining > 0 ? `${m.daysRemaining}d left` : m.daysRemaining === 0 ? 'Due today' : `${Math.abs(m.daysRemaining)}d overdue` }}
            </span>
          </div>
        </li>
      </ul>

      <!-- Add task button (when tasks exist and form is hidden) -->
      <button
        v-if="(recurringGoals.length > 0 || milestones.length > 0) && !showNewGoalForm"
        @click="showNewGoalForm = true"
        class="mt-4 flex min-h-[44px] items-center justify-center gap-1.5 text-xs font-medium text-[#c4873b] transition duration-200 hover:text-[#8b5a1b] active:scale-[0.97]"
      >
        + Add task
      </button>
  </div>
</template>
