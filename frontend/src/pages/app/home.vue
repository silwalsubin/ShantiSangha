<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUser } from '@clerk/vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const { user } = useUser()
const api = useApi()
const router = useRouter()

// --- Greeting ---
const now = new Date()
const hour = now.getHours()
const greeting = computed(() => {
  if (hour < 12) return 'Good morning'
  if (hour < 17) return 'Good afternoon'
  return 'Good evening'
})
const firstName = computed(() => user.value?.firstName || user.value?.username || 'friend')

// --- Daily Verse ---
const verses = [
  { text: 'You have the right to work, but never to the fruit of work.', source: 'Bhagavad Gita 2.47' },
  { text: 'The mind is everything. What you think, you become.', source: 'Dhammapada 1.1' },
  { text: 'Yoga is the stilling of the fluctuations of the mind.', source: 'Yoga Sutras 1.2' },
  { text: 'When meditation is mastered, the mind is unwavering like the flame of a candle in a windless place.', source: 'Bhagavad Gita 6.19' },
  { text: 'Better than a thousand hollow words is one word that brings peace.', source: 'Dhammapada 100' },
]
const dayOfYear = Math.floor((now.getTime() - new Date(now.getFullYear(), 0, 0).getTime()) / 86400000)
const dailyVerse = verses[dayOfYear % verses.length]

// --- Mood Check-in ---
const moodScore = ref(5)
const moodNote = ref('')
const moodSubmitting = ref(false)
const moodDoneToday = ref(false)
const moodError = ref('')

async function submitMood() {
  moodSubmitting.value = true
  moodError.value = ''
  try {
    await api.post('/moods', { score: moodScore.value, notes: moodNote.value })
    moodDoneToday.value = true
  } catch (e: any) {
    moodError.value = 'Could not save check-in. Please try again.'
  } finally {
    moodSubmitting.value = false
  }
}

// --- Today's Practice ---
const practices = [
  { text: 'Try 3 minutes of mindful breathing. Inhale for 4 counts, hold for 4, exhale for 6.', label: 'Mindful Breathing', tier: 'low' },
  { text: 'Write down one thing you are grateful for today and sit with that feeling for a moment.', label: 'Gratitude', tier: 'medium' },
  { text: 'Sit in stillness for 2 minutes. Let thoughts pass without following them.', label: 'Stillness', tier: 'high' },
  { text: 'Place one hand on your heart. Take 5 slow breaths and notice the warmth.', label: 'Grounding', tier: 'low' },
]

const suggestedPractice = computed(() => {
  const score = moodDoneToday.value ? moodScore.value : 5
  if (score <= 3) return practices.find(p => p.tier === 'low') || practices[0]
  if (score <= 6) return practices.find(p => p.tier === 'medium') || practices[1]
  return practices.find(p => p.tier === 'high') || practices[2]
})

// --- Continue Reflecting ---
const conversations = ref<any[]>([])
const convsLoading = ref(true)

const journals = ref<any[]>([])
const journalsLoading = ref(true)

async function loadConversations() {
  try {
    const data = await api.get<any>('/conversations?limit=3')
    conversations.value = Array.isArray(data) ? data : (data?.conversations || data?.items || [])
  } catch {
    conversations.value = []
  } finally {
    convsLoading.value = false
  }
}

async function loadJournals() {
  try {
    const data = await api.get<any>('/journals?limit=2')
    journals.value = Array.isArray(data) ? data : (data?.journals || data?.items || [])
  } catch {
    journals.value = []
  } finally {
    journalsLoading.value = false
  }
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

onMounted(() => {
  loadConversations()
  loadJournals()
})
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-4 sm:space-y-6 p-4 sm:p-6">

    <!-- 1. Greeting -->
    <div>
      <h1 class="font-serif text-2xl sm:text-3xl font-bold tracking-wide text-[#2b1e10]">
        {{ greeting }}, {{ firstName }}
      </h1>
      <p class="mt-1 text-[13px] sm:text-sm text-[#6b5740]">Take a moment to ground yourself today.</p>
    </div>

    <!-- 2. Daily Verse -->
    <div class="rounded-2xl border border-dashed border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] p-4 sm:p-5 backdrop-blur-[20px]">
      <div class="flex items-center gap-2">
        <SacredIcons name="scroll" :size="14" class="text-[#a38d6d]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Verse of the Day</p>
      </div>
      <p class="mt-3 font-serif italic text-sm sm:text-base text-[#b5996f] leading-relaxed">
        "{{ dailyVerse.text }}"
      </p>
      <p class="mt-2 text-[10px] uppercase tracking-[0.2em] text-[#9a8568]">
        -- {{ dailyVerse.source }}
      </p>
    </div>

    <!-- 3. Mood Check-in -->
    <div
      v-if="!moodDoneToday"
      class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px]"
    >
      <div class="flex items-center gap-2">
        <SacredIcons name="chakra" :size="14" class="text-[#a38d6d]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Mood Check-in</p>
      </div>
      <p class="mt-3 font-serif text-lg sm:text-xl font-bold tracking-wide text-[#2b1e10]">
        How are you feeling right now?
      </p>

      <div class="mt-5 space-y-4">
        <!-- Score slider -->
        <div class="flex items-center gap-4">
          <span class="w-6 text-center text-sm font-semibold text-[#c4873b]">{{ moodScore }}</span>
          <input
            v-model.number="moodScore"
            type="range"
            min="1"
            max="10"
            step="1"
            class="h-2 w-full cursor-pointer appearance-none rounded-full bg-[#e6d5c3] accent-[#c4873b]"
          />
        </div>
        <div class="flex justify-between text-xs text-[#6b5740]">
          <span>1 -- Very low</span>
          <span>10 -- Excellent</span>
        </div>

        <!-- Optional notes -->
        <textarea
          v-model="moodNote"
          placeholder="Any notes? (optional)"
          rows="2"
          class="w-full resize-none rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.9)] px-4 py-3 text-sm text-[#2b1e10] placeholder-[#b5996f] outline-none focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
        />

        <!-- Error -->
        <p v-if="moodError" class="rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-sm text-red-700">
          {{ moodError }}
        </p>

        <!-- Save button -->
        <button
          @click="submitMood"
          :disabled="moodSubmitting"
          class="min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
        >
          {{ moodSubmitting ? 'Saving...' : 'Save Check-in' }}
        </button>
      </div>
    </div>

    <!-- Mood: Checked-in state -->
    <div
      v-else
      class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px]"
    >
      <div class="flex items-center gap-2">
        <SacredIcons name="chakra" :size="14" class="text-[#a38d6d]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Check-in</p>
      </div>
      <p class="mt-2 font-serif text-base sm:text-lg text-[#2b1e10]">
        Checked in — you rated your mood {{ moodScore }}/10. Well done.
      </p>
    </div>

    <!-- 4. Today's Practice -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px]">
      <div class="flex items-center gap-2">
        <SacredIcons name="lotus" :size="14" class="text-[#a38d6d]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Today's Practice</p>
      </div>
      <p class="mt-3 font-serif text-lg sm:text-xl font-bold tracking-wide text-[#2b1e10]">
        {{ suggestedPractice.label }}
      </p>
      <p class="mt-2 text-[13px] sm:text-sm text-[#6b5740] leading-relaxed">
        {{ suggestedPractice.text }}
      </p>
    </div>

    <!-- 5. Continue Reflecting -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px]">
      <div class="flex items-center gap-2">
        <SacredIcons name="dialogue" :size="14" class="text-[#a38d6d]" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Continue Reflecting</p>
      </div>

      <!-- Loading state -->
      <div v-if="convsLoading && journalsLoading" class="mt-4 space-y-2">
        <div v-for="i in 2" :key="i" class="h-14 animate-pulse rounded-2xl bg-[rgba(196,135,59,0.08)]" />
      </div>

      <div v-else class="mt-4 space-y-2">
        <!-- Last conversation -->
        <div v-if="conversations.length === 0 && journals.length === 0" class="py-2 text-center">
          <p class="text-sm text-[#6b5740]">No reflections yet.</p>
          <RouterLink to="/app/reflect" class="mt-2 inline-block text-sm font-medium text-[#c4873b] transition duration-200 hover:text-[#8b5a1b]">
            Start your first reflection
          </RouterLink>
        </div>

        <RouterLink
          v-if="conversations.length > 0"
          :to="`/app/reflect/chat/${conversations[0].id}`"
          class="flex items-center gap-3 rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] min-h-[44px] px-4 py-3 transition duration-200 hover:bg-[rgba(245,235,224,1)] active:scale-[0.98]"
        >
          <SacredIcons name="dialogue" :size="16" class="shrink-0 text-[#c4873b]" />
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium text-[#2b1e10]">
              {{ conversations[0].title || 'Conversation' }}
            </p>
            <p class="mt-0.5 truncate text-xs text-[#6b5740]">
              {{ conversations[0].last_message || conversations[0].lastMessage || 'Continue where you left off' }}
            </p>
          </div>
          <span class="shrink-0 text-xs text-[#9a8568]">
            {{ conversations[0].created_at ? formatDate(conversations[0].created_at) : '' }}
          </span>
        </RouterLink>

        <!-- Last journal entry -->
        <RouterLink
          v-if="journals.length > 0"
          :to="`/app/reflect/journal/${journals[0].id}`"
          class="flex items-center gap-3 rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] min-h-[44px] px-4 py-3 transition duration-200 hover:bg-[rgba(245,235,224,1)] active:scale-[0.98]"
        >
          <SacredIcons name="scroll" :size="16" class="shrink-0 text-[#c4873b]" />
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium text-[#2b1e10]">
              {{ journals[0].title || 'Journal Entry' }}
            </p>
            <p class="mt-0.5 truncate text-xs text-[#6b5740]">
              {{ (journals[0].content || '').slice(0, 60) || 'Continue writing' }}
            </p>
          </div>
          <span class="shrink-0 text-xs text-[#9a8568]">
            {{ journals[0].created_at ? formatDate(journals[0].created_at) : '' }}
          </span>
        </RouterLink>
      </div>
    </div>

  </div>
</template>
