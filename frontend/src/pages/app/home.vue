<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUser } from '@clerk/vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const { user } = useUser()
const api = useApi()
const router = useRouter()

const firstName = computed(() => user.value?.firstName || user.value?.username || 'friend')

// --- Scroll state ---
const currentCard = ref(0)
const completed = ref(false)
const scrollContainer = ref<HTMLElement | null>(null)

// --- Goals data (all goals for context) ---
interface GoalToday {
  id: string
  title: string
  type: string
  currentStreak: number
  longestStreak: number
  checkedInToday: boolean
  completedToday: boolean | null
  targetDate?: string
  daysRemaining?: number
}

interface AllGoal {
  id: string
  title: string
  type: string
  currentStreak: number
  longestStreak: number
  targetDate?: string
  completedAt?: string
  daysRemaining?: number
}

const recurringGoals = ref<GoalToday[]>([])
const allGoals = ref<AllGoal[]>([])
const goalsLoading = ref(true)
const goalsCheckedIn = ref<Record<string, boolean>>({})
const goalsSaving = ref<Record<string, boolean>>({})
const allGoalsCheckedIn = ref(false)
const goalNotes = ref<Record<string, string>>({})
const showNoteInput = ref<Record<string, boolean>>({})
const goalFeedbackMessages = ref<Record<string, string>>({})

// New goal inline form
const showNewGoalForm = ref(false)
const newGoalTitle = ref('')
const newGoalType = ref<'Recurring' | 'OneTime'>('Recurring')
const newGoalTargetDate = ref('')
const newGoalSaving = ref(false)

// --- Intelligent feedback ---
const wisdomTemplates = {
  streakCelebrate: [
    { text: 'Discipline is choosing between what you want now and what you want most.', source: 'Abraham Lincoln' },
    { text: 'Small daily improvements are the key to staggering long-term results.', source: 'Zen Proverb' },
    { text: 'The secret of change is to focus all your energy not on fighting the old, but on building the new.', source: 'Socrates' },
  ],
  streakBroken: [
    { text: 'A moment of patience in a moment of anger saves a thousand moments of regret.', source: 'Ali ibn Abi Talib' },
    { text: 'Fall seven times, stand up eight.', source: 'Japanese Proverb' },
    { text: 'The wound is the place where the light enters you.', source: 'Rumi' },
  ],
  noGoals: [
    { text: 'The journey of a thousand miles begins with a single step.', source: 'Lao Tzu' },
    { text: 'You have the right to work, but never to the fruit of work.', source: 'Bhagavad Gita 2.47' },
  ],
  milestoneClose: [
    { text: 'It does not matter how slowly you go as long as you do not stop.', source: 'Confucius' },
    { text: 'Yoga is the journey of the self, through the self, to the self.', source: 'Bhagavad Gita' },
  ],
  default: [
    { text: 'The mind is everything. What you think, you become.', source: 'Dhammapada 1.1' },
    { text: 'Peace comes from within. Do not seek it without.', source: 'Buddha' },
    { text: 'Better than a thousand hollow words is one word that brings peace.', source: 'Dhammapada 100' },
    { text: 'He who has conquered himself is a far greater hero than he who has defeated a thousand times a thousand men.', source: 'Dhammapada 103' },
    { text: 'Yoga is the stilling of the fluctuations of the mind.', source: 'Yoga Sutras 1.2' },
  ]
}

const now = new Date()
const dayOfYear = Math.floor((now.getTime() - new Date(now.getFullYear(), 0, 0).getTime()) / 86400000)

const personalFeedback = computed(() => {
  const recurring = recurringGoals.value
  const all = allGoals.value

  // Strongest streak
  const bestStreak = recurring.reduce((max, g) => g.currentStreak > max.currentStreak ? g : max, { currentStreak: 0, title: '' } as any)

  // Any broken streaks (streak = 0 but has history)
  const brokenStreaks = recurring.filter(g => g.currentStreak === 0 && g.longestStreak > 0)

  // Milestone approaching
  const urgentMilestone = all.find(g => g.type === 'OneTime' && !g.completedAt && g.daysRemaining !== undefined && g.daysRemaining > 0 && g.daysRemaining <= 30)

  // Build feedback line
  let feedbackLine = ''
  let verse: { text: string; source: string }

  if (recurring.length === 0 && all.length === 0) {
    feedbackLine = 'Every journey begins with a single task.'
    verse = wisdomTemplates.noGoals[dayOfYear % wisdomTemplates.noGoals.length]
  } else if (bestStreak.currentStreak >= 7) {
    feedbackLine = `${bestStreak.currentStreak} days of "${bestStreak.title}". Your discipline is becoming who you are.`
    verse = wisdomTemplates.streakCelebrate[dayOfYear % wisdomTemplates.streakCelebrate.length]
  } else if (bestStreak.currentStreak >= 3) {
    feedbackLine = `${bestStreak.currentStreak} days strong on "${bestStreak.title}". Keep showing up.`
    verse = wisdomTemplates.streakCelebrate[dayOfYear % wisdomTemplates.streakCelebrate.length]
  } else if (brokenStreaks.length > 0) {
    feedbackLine = `"${brokenStreaks[0].title}" streak paused. Today is a new beginning.`
    verse = wisdomTemplates.streakBroken[dayOfYear % wisdomTemplates.streakBroken.length]
  } else if (urgentMilestone) {
    feedbackLine = `"${urgentMilestone.title}" — ${urgentMilestone.daysRemaining} days remaining. Stay on the path.`
    verse = wisdomTemplates.milestoneClose[dayOfYear % wisdomTemplates.milestoneClose.length]
  } else if (recurring.length > 0) {
    const total = recurring.reduce((sum, g) => sum + g.currentStreak, 0)
    feedbackLine = `${recurring.length} active practices. ${total} total streak days. You're building something real.`
    verse = wisdomTemplates.default[dayOfYear % wisdomTemplates.default.length]
  } else {
    feedbackLine = ''
    verse = wisdomTemplates.default[dayOfYear % wisdomTemplates.default.length]
  }

  return { feedbackLine, verse }
})

// --- Loaders ---
async function loadGoals() {
  goalsLoading.value = true
  try {
    // Load recurring goals for check-in
    const todayData = await api.get<any>('/goals/today')
    const todayItems = Array.isArray(todayData) ? todayData : (todayData?.goals || todayData?.items || [])
    recurringGoals.value = todayItems.map((g: any) => ({
      id: g.id,
      title: g.title,
      type: 'Recurring',
      currentStreak: g.currentStreak ?? g.current_streak ?? 0,
      longestStreak: g.longestStreak ?? g.longest_streak ?? 0,
      checkedInToday: g.checkedInToday ?? g.checked_in_today ?? (g.checkIn != null),
      completedToday: g.completedToday ?? g.completed_today ?? g.checkIn?.completed ?? null,
    }))
    for (const g of recurringGoals.value) {
      if (g.checkedInToday) goalsCheckedIn.value[g.id] = true
    }
    checkAllDone()

    // Load all goals for context/feedback
    const allData = await api.get<any>('/goals')
    const allItems = Array.isArray(allData) ? allData : (allData?.goals || allData?.items || [])
    allGoals.value = allItems.map((g: any) => ({
      id: g.id,
      title: g.title,
      type: g.type ?? 'Recurring',
      currentStreak: g.currentStreak ?? g.current_streak ?? 0,
      longestStreak: g.longestStreak ?? g.longest_streak ?? 0,
      targetDate: g.targetDate ?? g.target_date,
      completedAt: g.completedAt ?? g.completed_at,
      daysRemaining: g.daysRemaining ?? g.days_remaining,
    }))
  } catch {
    recurringGoals.value = []
    allGoals.value = []
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
    await api.post(`/goals/${goalId}/checkin`, { completed, note })
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
    checkAllDone()
  } catch {
    // silently fail
  } finally {
    goalsSaving.value[goalId] = false
  }
}

function checkAllDone() {
  if (recurringGoals.value.length === 0) return
  const allDone = recurringGoals.value.every(g => goalsCheckedIn.value[g.id])
  if (allDone && !allGoalsCheckedIn.value) {
    allGoalsCheckedIn.value = true
    setTimeout(() => nextCard(), 1200)
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

// --- Past insight ---
const insight = ref<any>(null)
async function loadInsight() {
  try {
    const data = await api.get<any>('/insights?page=1&pageSize=1')
    const items = Array.isArray(data) ? data : (data?.insights || data?.items || [])
    insight.value = items[0] || null
  } catch { insight.value = null }
}

// --- Recent activity ---
const lastConversation = ref<any>(null)
async function loadRecent() {
  try {
    const data = await api.get<any>('/conversations?limit=1')
    const items = Array.isArray(data) ? data : (data?.conversations || data?.items || [])
    lastConversation.value = items[0] || null
  } catch { lastConversation.value = null }
}

// --- Navigation ---
function nextCard() {
  const totalCards = 4
  if (currentCard.value < totalCards - 1) {
    currentCard.value++
    scrollToCard(currentCard.value)
  } else {
    completed.value = true
  }
}

function scrollToCard(index: number) {
  const container = scrollContainer.value
  if (!container) return
  const cards = container.children
  if (cards[index]) (cards[index] as HTMLElement).scrollIntoView({ behavior: 'smooth', block: 'center' })
}

function handleScroll() {
  const container = scrollContainer.value
  if (!container) return
  const cards = container.children
  const containerRect = container.getBoundingClientRect()
  const center = containerRect.top + containerRect.height / 2
  for (let i = 0; i < cards.length; i++) {
    const rect = (cards[i] as HTMLElement).getBoundingClientRect()
    if (rect.top <= center && rect.bottom >= center) { currentCard.value = i; break }
  }
}

onMounted(() => { loadGoals(); loadInsight(); loadRecent() })
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-4 sm:py-6">
    <!-- Progress dots -->
    <div class="mb-6 flex items-center justify-center gap-2">
      <div
        v-for="i in 4" :key="i"
        class="h-1.5 rounded-full transition-all duration-300"
        :class="i - 1 <= currentCard ? 'w-6 bg-gradient-to-r from-[#c4873b] to-[#8b5a1b]' : 'w-1.5 bg-[rgba(139,90,43,0.2)]'"
      />
    </div>

    <div ref="scrollContainer" class="space-y-6 snap-y snap-mandatory" @scroll="handleScroll">

      <!-- Card 1: Intelligent Greeting -->
      <div class="snap-center rounded-2xl border border-dashed border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.95)] p-6 sm:p-8 backdrop-blur-[20px] min-h-[300px] flex flex-col items-center justify-center text-center">
        <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">
          {{ new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }) }}
        </p>
        <h1 class="mt-4 font-serif text-2xl sm:text-3xl font-bold tracking-wide text-[#2b1e10]">
          {{ firstName }}
        </h1>

        <!-- Personal feedback line -->
        <p v-if="!goalsLoading && personalFeedback.feedbackLine" class="mt-4 text-[13px] leading-relaxed text-[#6b5740] max-w-xs">
          {{ personalFeedback.feedbackLine }}
        </p>

        <!-- Contextual verse -->
        <div class="mt-5 max-w-xs">
          <p class="font-serif italic text-[14px] sm:text-[15px] leading-relaxed text-[#9a8568]">
            "{{ personalFeedback.verse.text }}"
          </p>
          <p class="mt-2 text-[10px] uppercase tracking-[0.2em] text-[#b5996f]">
            {{ personalFeedback.verse.source }}
          </p>
        </div>

        <button @click="nextCard" class="mt-6 text-[12px] font-medium tracking-wide text-[#c4873b] transition duration-200 active:scale-95">
          Continue
        </button>
      </div>

      <!-- Card 2: Dharma Check-in -->
      <div class="snap-center rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 sm:p-8 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] min-h-[280px] flex flex-col items-center justify-center text-center">
        <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Your Dharma</p>
        <p class="mt-4 font-serif text-xl sm:text-2xl font-bold tracking-wide text-[#2b1e10]">What needs your attention?</p>

        <!-- Loading -->
        <div v-if="goalsLoading" class="mt-6 w-full max-w-xs space-y-3">
          <div v-for="i in 2" :key="i" class="h-16 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
        </div>

        <!-- No goals -->
        <div v-else-if="recurringGoals.length === 0 && !showNewGoalForm" class="mt-6 w-full max-w-xs">
          <p class="text-sm text-[#6b5740]">You haven't set any tasks yet.</p>
          <button @click="showNewGoalForm = true" class="mt-4 min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-3 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97]">
            Set your first task
          </button>
        </div>

        <!-- New goal form -->
        <div v-if="showNewGoalForm" class="mt-6 w-full max-w-xs">
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

        <!-- Goal check-in list -->
        <div v-if="recurringGoals.length > 0" class="mt-6 w-full max-w-xs space-y-3">
          <div v-for="goal in recurringGoals" :key="goal.id" class="rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3">
            <div class="flex items-center justify-between">
              <button class="text-left text-sm font-medium text-[#2b1e10] transition duration-200 hover:text-[#c4873b]" @click="router.push(`/app/journey/goals/${goal.id}`)">{{ goal.title }}</button>
              <div class="flex items-center gap-1.5 shrink-0">
                <SacredIcons name="flame" :size="14" class="text-[#c4873b]" />
                <span class="font-serif font-bold text-[#c4873b] text-sm">{{ goal.currentStreak }}</span>
              </div>
            </div>
            <!-- Already checked in — spiritual feedback -->
            <div v-if="goalsCheckedIn[goal.id]" class="mt-2">
              <p class="font-serif text-xs italic leading-relaxed text-[#6b5740]">
                {{ goalFeedbackMessages[goal.id] || (goal.completedToday ? 'Done for today.' : 'Rest well.') }}
              </p>
            </div>
            <!-- Check-in flow -->
            <div v-else>
              <!-- Optional note -->
              <div v-if="showNoteInput[goal.id]" class="mt-2">
                <input
                  v-model="goalNotes[goal.id]"
                  type="text"
                  placeholder="A brief reflection (optional)"
                  class="w-full rounded-xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] px-3 py-2 text-xs text-[#2b1e10] placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b]"
                  @keyup.enter="checkInGoal(goal.id, true)"
                />
              </div>
              <!-- Buttons -->
              <div class="mt-2 flex items-center justify-center gap-2">
                <button @click="checkInGoal(goal.id, true)" :disabled="goalsSaving[goal.id]" class="flex min-h-[44px] items-center gap-1.5 rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2 text-xs font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97] disabled:opacity-60">
                  <SacredIcons name="check" :size="14" /> Done
                </button>
                <button @click="checkInGoal(goal.id, false)" :disabled="goalsSaving[goal.id]" class="flex min-h-[44px] items-center gap-1.5 rounded-xl border border-[rgba(139,90,43,0.15)] px-4 py-2 text-xs font-medium text-[#6b5740] transition duration-200 active:scale-[0.97] disabled:opacity-60 hover:bg-[rgba(196,135,59,0.06)]">
                  <SacredIcons name="skip" :size="12" /> Not today
                </button>
                <button
                  v-if="!showNoteInput[goal.id]"
                  @click="showNoteInput[goal.id] = true"
                  class="flex min-h-[44px] items-center justify-center rounded-xl border border-[rgba(139,90,43,0.1)] px-2.5 py-2 text-[#9a8568] transition duration-200 hover:bg-[rgba(196,135,59,0.06)]"
                  title="Add a note"
                >
                  <SacredIcons name="scroll" :size="14" />
                </button>
              </div>
            </div>
          </div>
        </div>

        <div v-if="allGoalsCheckedIn && recurringGoals.length > 0" class="mt-4">
          <p class="text-sm text-[#6b5740]">All tasks accounted for. Well done.</p>
        </div>

        <button v-if="recurringGoals.length === 0 && !showNewGoalForm" @click="nextCard" class="mt-4 text-[12px] font-medium tracking-wide text-[#c4873b] transition duration-200 active:scale-95">
          Skip for now
        </button>
      </div>

      <!-- Card 3: Your insight / milestone reminder (only if there's something to show) -->
      <div v-if="allGoals.some(g => g.type === 'OneTime' && !g.completedAt && g.daysRemaining && g.daysRemaining > 0 && g.daysRemaining <= 60) || insight" class="snap-center rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 sm:p-8 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] min-h-[240px] flex flex-col items-center justify-center text-center">

        <!-- Show milestone reminder if one is approaching -->
        <template v-if="allGoals.some(g => g.type === 'OneTime' && !g.completedAt && g.daysRemaining && g.daysRemaining > 0 && g.daysRemaining <= 60)">
          <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Milestone ahead</p>
          <SacredIcons name="target" :size="28" class="mt-4 text-[#c4873b]" />
          <div v-for="g in allGoals.filter(g => g.type === 'OneTime' && !g.completedAt && g.daysRemaining && g.daysRemaining > 0 && g.daysRemaining <= 60).slice(0, 1)" :key="g.id">
            <p class="mt-4 font-serif text-[15px] sm:text-base font-bold text-[#2b1e10]">"{{ g.title }}"</p>
            <p class="mt-2 font-serif text-2xl font-bold text-[#c4873b]">{{ g.daysRemaining }} days left</p>
            <p class="mt-1 text-[11px] text-[#9a8568]">What can you do today to move closer?</p>
          </div>
        </template>

        <!-- Otherwise show insight -->
        <template v-else-if="insight">
          <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">From your journey</p>
          <SacredIcons name="diya" :size="28" class="mt-4 text-[#c4873b]" />
          <p class="mt-4 font-serif text-[15px] sm:text-base leading-relaxed text-[#2b1e10] max-w-sm">"{{ insight.content }}"</p>
          <p class="mt-3 text-[10px] text-[#9a8568]">From a past reflection</p>
        </template>

        <button @click="nextCard" class="mt-6 text-[12px] font-medium tracking-wide text-[#c4873b] transition duration-200 active:scale-95">Continue</button>
      </div>

      <!-- Card 5: Summary + Actions -->
      <div class="snap-center rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 sm:p-8 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] min-h-[280px] flex flex-col items-center justify-center text-center">
        <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Today's practice complete</p>
        <div class="mt-4 flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
          <SacredIcons name="lotus" :size="30" />
        </div>
        <p class="mt-4 font-serif text-xl font-bold text-[#2b1e10]">Well done, {{ firstName }}</p>
        <p class="mt-2 text-sm text-[#6b5740]">You showed up for yourself today.</p>

        <!-- Goal summary -->
        <div v-if="recurringGoals.length > 0" class="mt-4 text-xs text-[#9a8568]">
          {{ recurringGoals.filter(g => g.completedToday === true).length }}/{{ recurringGoals.length }} practices completed today
        </div>

        <div class="mt-6 flex flex-col gap-2 w-full max-w-xs">
          <button @click="router.push('/app/reflect')" class="min-h-[48px] flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-5 py-3 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97]">
            <SacredIcons name="dialogue" :size="18" /> Start a reflection
          </button>
          <RouterLink v-if="lastConversation" :to="`/app/reflect/chat/${lastConversation.id}`" class="min-h-[48px] flex items-center justify-center gap-2 rounded-xl border border-[rgba(139,90,43,0.15)] px-5 py-3 text-sm font-medium text-[#6b5740] transition duration-200 active:scale-[0.97] hover:bg-[rgba(196,135,59,0.06)]">
            Continue last conversation
          </RouterLink>
        </div>
      </div>
    </div>
  </div>
</template>
