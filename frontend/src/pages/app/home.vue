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

// --- Daily Verse ---
const verses = [
  { text: 'You have the right to work, but never to the fruit of work.', source: 'Bhagavad Gita 2.47' },
  { text: 'The mind is everything. What you think, you become.', source: 'Dhammapada 1.1' },
  { text: 'Yoga is the stilling of the fluctuations of the mind.', source: 'Yoga Sutras 1.2' },
  { text: 'When meditation is mastered, the mind is unwavering like the flame of a candle in a windless place.', source: 'Bhagavad Gita 6.19' },
  { text: 'Better than a thousand hollow words is one word that brings peace.', source: 'Dhammapada 100' },
  { text: 'The soul is neither born, nor does it die.', source: 'Bhagavad Gita 2.20' },
  { text: 'Peace comes from within. Do not seek it without.', source: 'Buddha' },
  { text: 'In the midst of movement and chaos, keep stillness inside of you.', source: 'Deepak Chopra' },
  { text: 'The quieter you become, the more you can hear.', source: 'Rumi' },
  { text: 'He who has conquered himself is a far greater hero than he who has defeated a thousand times a thousand men.', source: 'Dhammapada 103' },
]
const now = new Date()
const dayOfYear = Math.floor((now.getTime() - new Date(now.getFullYear(), 0, 0).getTime()) / 86400000)
const dailyVerse = verses[dayOfYear % verses.length]

// --- Goals check-in ---
interface GoalToday {
  id: string
  title: string
  currentStreak: number
  longestStreak: number
  checkedInToday: boolean
  completedToday: boolean | null
}

const goals = ref<GoalToday[]>([])
const goalsLoading = ref(true)
const goalsCheckedIn = ref<Record<string, boolean>>({})
const goalsSaving = ref<Record<string, boolean>>({})
const allGoalsCheckedIn = ref(false)

// New goal inline form
const showNewGoalForm = ref(false)
const newGoalTitle = ref('')
const newGoalSaving = ref(false)

async function loadGoals() {
  goalsLoading.value = true
  try {
    const data = await api.get<any>('/goals/today')
    const items = Array.isArray(data) ? data : (data?.goals || data?.items || [])
    goals.value = items.map((g: any) => ({
      id: g.id,
      title: g.title,
      currentStreak: g.currentStreak ?? g.current_streak ?? 0,
      longestStreak: g.longestStreak ?? g.longest_streak ?? 0,
      checkedInToday: g.checkedInToday ?? g.checked_in_today ?? false,
      completedToday: g.completedToday ?? g.completed_today ?? null,
    }))
    // Mark already checked-in goals
    for (const g of goals.value) {
      if (g.checkedInToday) {
        goalsCheckedIn.value[g.id] = true
      }
    }
    checkAllDone()
  } catch {
    goals.value = []
  } finally {
    goalsLoading.value = false
  }
}

async function checkInGoal(goalId: string, completed: boolean) {
  goalsSaving.value[goalId] = true
  try {
    await api.post(`/goals/${goalId}/checkin`, { completed })
    goalsCheckedIn.value[goalId] = true
    // Update streak locally
    const goal = goals.value.find(g => g.id === goalId)
    if (goal) {
      goal.checkedInToday = true
      goal.completedToday = completed
      if (completed) {
        goal.currentStreak += 1
      } else {
        goal.currentStreak = 0
      }
    }
    checkAllDone()
  } catch {
    // silently fail
  } finally {
    goalsSaving.value[goalId] = false
  }
}

function checkAllDone() {
  if (goals.value.length === 0) return
  const allDone = goals.value.every(g => goalsCheckedIn.value[g.id])
  if (allDone && !allGoalsCheckedIn.value) {
    allGoalsCheckedIn.value = true
    setTimeout(() => nextCard(), 1200)
  }
}

async function createGoal() {
  if (!newGoalTitle.value.trim()) return
  newGoalSaving.value = true
  try {
    await api.post('/goals', { title: newGoalTitle.value.trim() })
    newGoalTitle.value = ''
    showNewGoalForm.value = false
    await loadGoals()
  } catch {
    // silently fail
  } finally {
    newGoalSaving.value = false
  }
}

// --- Breathing exercise ---
const breathPhase = ref<'idle' | 'inhale' | 'hold' | 'exhale' | 'done'>('idle')
const breathCount = ref(0)
const breathTimer = ref<ReturnType<typeof setTimeout> | null>(null)

function startBreathing() {
  breathCount.value = 0
  runBreathCycle()
}

function runBreathCycle() {
  if (breathCount.value >= 3) {
    breathPhase.value = 'done'
    return
  }
  breathPhase.value = 'inhale'
  breathTimer.value = setTimeout(() => {
    breathPhase.value = 'hold'
    breathTimer.value = setTimeout(() => {
      breathPhase.value = 'exhale'
      breathTimer.value = setTimeout(() => {
        breathCount.value++
        runBreathCycle()
      }, 4000)
    }, 4000)
  }, 4000)
}

// --- Past insight ---
const insight = ref<any>(null)

async function loadInsight() {
  try {
    const data = await api.get<any>('/insights?page=1&pageSize=1')
    const items = Array.isArray(data) ? data : (data?.insights || data?.items || [])
    insight.value = items[0] || null
  } catch {
    insight.value = null
  }
}

// --- Recent activity for final card ---
const lastConversation = ref<any>(null)

async function loadRecent() {
  try {
    const data = await api.get<any>('/conversations?limit=1')
    const items = Array.isArray(data) ? data : (data?.conversations || data?.items || [])
    lastConversation.value = items[0] || null
  } catch {
    lastConversation.value = null
  }
}

// --- Navigation ---
function nextCard() {
  const totalCards = 5
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
  if (cards[index]) {
    (cards[index] as HTMLElement).scrollIntoView({ behavior: 'smooth', block: 'center' })
  }
}

function handleScroll() {
  const container = scrollContainer.value
  if (!container) return
  const cards = container.children
  const containerRect = container.getBoundingClientRect()
  const center = containerRect.top + containerRect.height / 2

  for (let i = 0; i < cards.length; i++) {
    const rect = (cards[i] as HTMLElement).getBoundingClientRect()
    if (rect.top <= center && rect.bottom >= center) {
      currentCard.value = i
      break
    }
  }
}

onMounted(() => {
  loadGoals()
  loadInsight()
  loadRecent()
})
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-4 sm:py-6">
    <!-- Progress dots -->
    <div class="mb-6 flex items-center justify-center gap-2">
      <div
        v-for="i in 5"
        :key="i"
        class="h-1.5 rounded-full transition-all duration-300"
        :class="i - 1 <= currentCard
          ? 'w-6 bg-gradient-to-r from-[#c4873b] to-[#8b5a1b]'
          : 'w-1.5 bg-[rgba(139,90,43,0.2)]'"
      />
    </div>

    <!-- Scrollable cards -->
    <div
      ref="scrollContainer"
      class="space-y-6 snap-y snap-mandatory"
      @scroll="handleScroll"
    >
      <!-- Card 1: Greeting + Verse -->
      <div class="snap-center rounded-2xl border border-dashed border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.95)] p-6 sm:p-8 backdrop-blur-[20px] min-h-[280px] flex flex-col items-center justify-center text-center">
        <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">
          {{ new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }) }}
        </p>
        <h1 class="mt-4 font-serif text-2xl sm:text-3xl font-bold tracking-wide text-[#2b1e10]">
          {{ firstName }}
        </h1>
        <div class="mt-6 max-w-xs">
          <p class="font-serif italic text-[15px] sm:text-base leading-relaxed text-[#9a8568]">
            "{{ dailyVerse.text }}"
          </p>
          <p class="mt-3 text-[10px] uppercase tracking-[0.2em] text-[#b5996f]">
            {{ dailyVerse.source }}
          </p>
        </div>
        <button
          @click="nextCard"
          class="mt-8 text-[12px] font-medium tracking-wide text-[#c4873b] transition duration-200 active:scale-95"
        >
          Continue
        </button>
      </div>

      <!-- Card 2: Your Intentions (Goals check-in) -->
      <div class="snap-center rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 sm:p-8 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] min-h-[280px] flex flex-col items-center justify-center text-center">
        <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Daily discipline</p>

        <p class="mt-4 font-serif text-xl sm:text-2xl font-bold tracking-wide text-[#2b1e10]">
          Your intentions
        </p>

        <!-- Loading -->
        <div v-if="goalsLoading" class="mt-6 w-full max-w-xs space-y-3">
          <div v-for="i in 2" :key="i" class="h-16 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
        </div>

        <!-- No goals — empty state -->
        <div v-else-if="goals.length === 0 && !showNewGoalForm" class="mt-6 w-full max-w-xs">
          <p class="text-sm text-[#6b5740]">You haven't set any intentions yet.</p>
          <button
            @click="showNewGoalForm = true"
            class="mt-4 min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-3 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97]"
          >
            Set your first intention
          </button>
        </div>

        <!-- New goal inline form -->
        <div v-if="showNewGoalForm" class="mt-6 w-full max-w-xs">
          <input
            v-model="newGoalTitle"
            type="text"
            placeholder="I want to..."
            class="w-full rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] px-4 py-3 text-sm text-[#2b1e10] placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
            @keyup.enter="createGoal"
          />
          <div class="mt-3 flex justify-center gap-2">
            <button
              @click="createGoal"
              :disabled="newGoalSaving || !newGoalTitle.trim()"
              class="min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97] disabled:opacity-60"
            >
              {{ newGoalSaving ? 'Saving...' : 'Save' }}
            </button>
            <button
              @click="showNewGoalForm = false"
              class="min-h-[44px] rounded-full border border-[rgba(139,90,43,0.15)] px-5 py-2.5 text-sm font-medium text-[#6b5740] transition duration-200 active:scale-[0.97]"
            >
              Cancel
            </button>
          </div>
        </div>

        <!-- Goal list with check-in buttons -->
        <div v-if="goals.length > 0" class="mt-6 w-full max-w-xs space-y-3">
          <div
            v-for="goal in goals"
            :key="goal.id"
            class="rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3"
          >
            <div class="flex items-center justify-between">
              <p class="text-left text-sm font-medium text-[#2b1e10]">{{ goal.title }}</p>
              <div class="flex items-center gap-1.5 shrink-0">
                <SacredIcons name="flame" :size="14" class="text-[#c4873b]" />
                <span class="font-serif font-bold text-[#c4873b] text-sm">{{ goal.currentStreak }}</span>
              </div>
            </div>

            <!-- Already checked in -->
            <div v-if="goalsCheckedIn[goal.id]" class="mt-2 flex items-center justify-center gap-2">
              <SacredIcons name="check" :size="16" class="text-[#7aa87a]" />
              <span class="text-xs text-[#6b5740]">
                {{ goal.completedToday ? 'Done for today' : 'Noted. Rest well.' }}
              </span>
            </div>

            <!-- Check-in buttons -->
            <div v-else class="mt-2 flex justify-center gap-2">
              <button
                @click="checkInGoal(goal.id, true)"
                :disabled="goalsSaving[goal.id]"
                class="flex min-h-[44px] items-center gap-1.5 rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2 text-xs font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97] disabled:opacity-60"
              >
                <SacredIcons name="check" :size="14" />
                Done
              </button>
              <button
                @click="checkInGoal(goal.id, false)"
                :disabled="goalsSaving[goal.id]"
                class="flex min-h-[44px] items-center gap-1.5 rounded-xl border border-[rgba(139,90,43,0.15)] px-4 py-2 text-xs font-medium text-[#6b5740] transition duration-200 active:scale-[0.97] disabled:opacity-60 hover:bg-[rgba(196,135,59,0.06)]"
              >
                <SacredIcons name="skip" :size="12" />
                Not today
              </button>
            </div>
          </div>
        </div>

        <!-- All checked in message -->
        <div v-if="allGoalsCheckedIn && goals.length > 0" class="mt-4">
          <p class="text-sm text-[#6b5740]">All intentions accounted for. Well done.</p>
        </div>

        <!-- Skip if no goals and form not shown -->
        <button
          v-if="goals.length === 0 && !showNewGoalForm"
          @click="nextCard"
          class="mt-4 text-[12px] font-medium tracking-wide text-[#c4873b] transition duration-200 active:scale-95"
        >
          Skip for now
        </button>
      </div>

      <!-- Card 3: Breathe -->
      <div class="snap-center rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 sm:p-8 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] min-h-[320px] flex flex-col items-center justify-center text-center">
        <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Practice</p>

        <template v-if="breathPhase === 'idle'">
          <p class="mt-4 font-serif text-xl sm:text-2xl font-bold tracking-wide text-[#2b1e10]">
            Take 3 breaths
          </p>
          <p class="mt-2 text-sm text-[#6b5740]">
            A moment of stillness before you continue.
          </p>
          <button
            @click="startBreathing"
            class="mt-6 min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-8 py-3 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-95"
          >
            Begin
          </button>
        </template>

        <template v-else-if="breathPhase === 'done'">
          <div class="flex h-20 w-20 items-center justify-center rounded-full bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
            <SacredIcons name="lotus" :size="36" />
          </div>
          <p class="mt-4 font-serif text-xl font-bold text-[#2b1e10]">Well done</p>
          <p class="mt-2 text-sm text-[#6b5740]">Three breaths of peace.</p>
          <button
            @click="nextCard"
            class="mt-6 text-[12px] font-medium tracking-wide text-[#c4873b] transition duration-200 active:scale-95"
          >
            Continue
          </button>
        </template>

        <template v-else>
          <!-- Breathing circle -->
          <div
            class="mt-4 flex items-center justify-center rounded-full border-2 border-[#c4873b] transition-all duration-[4000ms] ease-in-out"
            :class="breathPhase === 'inhale' ? 'h-36 w-36' : breathPhase === 'hold' ? 'h-36 w-36' : 'h-20 w-20'"
          >
            <span class="text-sm font-semibold uppercase tracking-[0.15em] text-[#c4873b]">
              {{ breathPhase === 'inhale' ? 'Breathe in' : breathPhase === 'hold' ? 'Hold' : 'Breathe out' }}
            </span>
          </div>
          <p class="mt-4 text-xs text-[#9a8568]">Breath {{ breathCount + 1 }} of 3</p>
        </template>
      </div>

      <!-- Card 4: Your insight -->
      <div class="snap-center rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 sm:p-8 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] min-h-[240px] flex flex-col items-center justify-center text-center">
        <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">From your journey</p>

        <template v-if="insight">
          <SacredIcons name="diya" :size="28" class="mt-4 text-[#c4873b]" />
          <p class="mt-4 font-serif text-[15px] sm:text-base leading-relaxed text-[#2b1e10] max-w-sm">
            "{{ insight.content }}"
          </p>
          <p class="mt-3 text-[10px] text-[#9a8568]">
            From a past reflection
          </p>
        </template>
        <template v-else>
          <SacredIcons name="diya" :size="28" class="mt-4 text-[#b5996f]" />
          <p class="mt-4 font-serif text-base text-[#6b5740]">
            Your insights will appear here as you reflect.
          </p>
        </template>

        <button
          @click="nextCard"
          class="mt-6 text-[12px] font-medium tracking-wide text-[#c4873b] transition duration-200 active:scale-95"
        >
          Continue
        </button>
      </div>

      <!-- Card 5: What would you like to do? -->
      <div class="snap-center rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 sm:p-8 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] min-h-[280px] flex flex-col items-center justify-center text-center">
        <template v-if="!completed">
          <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Today's practice complete</p>
          <div class="mt-4 flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
            <SacredIcons name="lotus" :size="30" />
          </div>
          <p class="mt-4 font-serif text-xl font-bold text-[#2b1e10]">
            Well done, {{ firstName }}
          </p>
          <p class="mt-2 text-sm text-[#6b5740]">
            You showed up for yourself today.
          </p>
        </template>

        <div class="mt-6 flex flex-col gap-2 w-full max-w-xs">
          <button
            @click="router.push('/app/reflect')"
            class="min-h-[48px] flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-5 py-3 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97]"
          >
            <SacredIcons name="dialogue" :size="18" />
            Start a reflection
          </button>
          <RouterLink
            v-if="lastConversation"
            :to="`/app/reflect/chat/${lastConversation.id}`"
            class="min-h-[48px] flex items-center justify-center gap-2 rounded-xl border border-[rgba(139,90,43,0.15)] px-5 py-3 text-sm font-medium text-[#6b5740] transition duration-200 active:scale-[0.97] hover:bg-[rgba(196,135,59,0.06)]"
          >
            Continue last conversation
          </RouterLink>
        </div>
      </div>
    </div>
  </div>
</template>
