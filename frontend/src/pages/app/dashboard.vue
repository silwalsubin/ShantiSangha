<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUser } from '@clerk/vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const { user } = useUser()
const api = useApi()
const router = useRouter()

const now = new Date()
const hour = now.getHours()
const greeting = computed(() => {
  if (hour < 12) return 'Good morning'
  if (hour < 17) return 'Good afternoon'
  return 'Good evening'
})
const firstName = computed(() => user.value?.firstName || user.value?.username || 'friend')

// Mood check-in
const moodScore = ref(5)
const moodNote = ref('')
const moodSubmitting = ref(false)
const moodDoneToday = ref(false)
const moodError = ref('')

// Recent conversations
const conversations = ref<any[]>([])
const convsLoading = ref(true)

// Recent journals
const journals = ref<any[]>([])
const journalsLoading = ref(true)

// Mood trends
const trends = ref<any>(null)
const trendsLoading = ref(true)

async function submitMood() {
  moodSubmitting.value = true
  moodError.value = ''
  try {
    await api.post('/moods', { score: moodScore.value, notes: moodNote.value })
    moodDoneToday.value = true
    await loadTrends()
  } catch (e: any) {
    moodError.value = 'Could not save check-in. Please try again.'
  } finally {
    moodSubmitting.value = false
  }
}

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

async function loadTrends() {
  try {
    trends.value = await api.get<any>('/moods/trends')
  } catch {
    trends.value = null
  } finally {
    trendsLoading.value = false
  }
}

async function newConversation() {
  try {
    const conv = await api.post<any>('/conversations', { title: 'New Conversation' })
    router.push(`/app/chat/${conv.id}`)
  } catch {
    // ignore
  }
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

onMounted(() => {
  loadConversations()
  loadJournals()
  loadTrends()
})
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-4 sm:space-y-6 p-4 sm:p-6">
    <!-- Greeting -->
    <div>
      <h1 class="font-serif text-2xl sm:text-3xl font-bold tracking-wide text-[#2b1e10]">{{ greeting }}, {{ firstName }}</h1>
      <p class="mt-1 text-sm text-[#6b5740]">How are you doing today?</p>
    </div>

    <!-- Daily Verse -->
    <div class="rounded-2xl border border-dashed border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] p-4 sm:p-5 backdrop-blur-[20px]">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Verse of the Day</p>
      <p class="mt-2 font-serif italic text-sm sm:text-base text-[#b5996f] leading-relaxed">"You have the right to work, but never to the fruit of work."</p>
      <p class="mt-1 text-[10px] uppercase tracking-[0.2em] text-[#9a8568]">-- Bhagavad Gita 2.47</p>
    </div>

    <!-- Mood Check-in -->
    <div v-if="!moodDoneToday" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px]">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Today's Check-in</p>
      <p class="mt-3 font-serif text-lg sm:text-xl font-bold tracking-wide text-[#2b1e10]">How would you rate your mood right now?</p>
      <div class="mt-5 space-y-4">
        <div class="flex items-center gap-4">
          <span class="w-6 text-center text-sm font-semibold text-[#c4873b]">{{ moodScore }}</span>
          <input
            v-model.number="moodScore"
            type="range" min="1" max="10" step="1"
            class="h-2 w-full cursor-pointer appearance-none rounded-full bg-[#e6d5c3] accent-[#c4873b]"
          />
          <div class="flex justify-between w-full absolute pointer-events-none" />
        </div>
        <div class="flex justify-between text-xs text-[#6b5740]">
          <span>1 -- Very low</span>
          <span>10 -- Excellent</span>
        </div>
        <textarea
          v-model="moodNote"
          placeholder="Any notes? (optional)"
          rows="2"
          class="w-full resize-none rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] px-4 py-3 text-sm text-[#2b1e10] placeholder-[#9a8568] outline-none focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
        />
        <p v-if="moodError" class="rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-sm text-red-700">{{ moodError }}</p>
        <button
          @click="submitMood"
          :disabled="moodSubmitting"
          class="min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-[#fff8f1] shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
        >
          {{ moodSubmitting ? 'Saving...' : 'Save Check-in' }}
        </button>
      </div>
    </div>
    <div v-else class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-4 sm:px-6 py-4 sm:py-5 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px]">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Check-in</p>
      <p class="mt-2 font-serif text-base sm:text-lg text-[#2b1e10]">You've checked in today. Well done.</p>
    </div>

    <!-- Mood Trend -->
    <div v-if="!trendsLoading && trends" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px]">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Mood Trend</p>
      <div class="mt-3 flex flex-wrap items-center gap-3 sm:gap-4">
        <div class="rounded-2xl bg-[rgba(196,135,59,0.08)] px-4 sm:px-5 py-3 text-center">
          <p class="text-2xl font-bold text-[#c4873b]">{{ trends.average?.toFixed(1) ?? '--' }}</p>
          <p class="text-xs text-[#6b5740]">Average</p>
        </div>
        <div class="rounded-2xl bg-[rgba(196,135,59,0.08)] px-4 sm:px-5 py-3 text-center">
          <p class="text-2xl font-bold text-[#c4873b] capitalize">{{ trends.trend ?? '--' }}</p>
          <p class="text-xs text-[#6b5740]">Trend</p>
        </div>
        <div v-if="trends.daily_averages?.length" class="flex flex-1 items-end gap-1 min-w-0">
          <div
            v-for="day in trends.daily_averages.slice(-7)"
            :key="day.date"
            class="flex-1 rounded-t bg-gradient-to-t from-[#8b5a1b] to-[#c4873b] opacity-80 transition-all duration-200"
            :style="{ height: `${(day.average / 10) * 48 + 4}px` }"
            :title="`${day.date}: ${day.average?.toFixed(1)}`"
          />
        </div>
      </div>
    </div>

    <!-- Recent Conversations -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px]">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <SacredIcons name="dialogue" :size="16" class="text-[#a38d6d]" />
          <p class="text-[10px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Recent Conversations</p>
        </div>
        <button @click="newConversation" class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2 text-xs font-semibold text-[#fff8f1] shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5">
          + New
        </button>
      </div>
      <div v-if="convsLoading" class="mt-4 space-y-2">
        <div v-for="i in 3" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(196,135,59,0.08)]" />
      </div>
      <div v-else-if="conversations.length === 0" class="mt-4 text-sm text-[#6b5740]">No conversations yet.</div>
      <ul v-else class="mt-4 space-y-2">
        <li v-for="conv in conversations" :key="conv.id">
          <RouterLink
            :to="`/app/chat/${conv.id}`"
            class="flex items-center justify-between rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] min-h-[44px] px-4 py-3 transition duration-200 hover:bg-[rgba(245,235,224,1)]"
          >
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-[#2b1e10]">{{ conv.title || 'Conversation' }}</p>
              <p class="mt-0.5 truncate text-xs text-[#6b5740]">{{ conv.last_message || conv.lastMessage || '' }}</p>
            </div>
            <span class="ml-3 shrink-0 text-xs text-[#9a8568]">{{ conv.created_at ? formatDate(conv.created_at) : '' }}</span>
          </RouterLink>
        </li>
      </ul>
      <RouterLink to="/app/chat" class="mt-3 block text-center text-xs text-[#c4873b] min-h-[44px] flex items-center justify-center hover:underline">View all</RouterLink>
    </div>

    <!-- Recent Journals -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px]">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <SacredIcons name="scroll" :size="16" class="text-[#a38d6d]" />
          <p class="text-[10px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Journal</p>
        </div>
        <RouterLink to="/app/journal/new" class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2 text-xs font-semibold text-[#fff8f1] shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5">
          + New Entry
        </RouterLink>
      </div>
      <div v-if="journalsLoading" class="mt-4 space-y-2">
        <div v-for="i in 2" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(196,135,59,0.08)]" />
      </div>
      <div v-else-if="journals.length === 0" class="mt-4 text-sm text-[#6b5740]">No journal entries yet.</div>
      <ul v-else class="mt-4 space-y-2">
        <li v-for="entry in journals" :key="entry.id">
          <RouterLink
            :to="`/app/journal/${entry.id}`"
            class="flex items-center justify-between rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] min-h-[44px] px-4 py-3 transition duration-200 hover:bg-[rgba(245,235,224,1)]"
          >
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-[#2b1e10]">{{ entry.title || 'Untitled' }}</p>
              <p class="mt-0.5 truncate text-xs text-[#6b5740]">{{ (entry.content || '').slice(0, 60) }}</p>
            </div>
            <span class="ml-3 shrink-0 text-xs text-[#9a8568]">{{ entry.created_at ? formatDate(entry.created_at) : '' }}</span>
          </RouterLink>
        </li>
      </ul>
      <RouterLink to="/app/journal" class="mt-3 block text-center text-xs text-[#c4873b] min-h-[44px] flex items-center justify-center hover:underline">View all</RouterLink>
    </div>
  </div>
</template>
