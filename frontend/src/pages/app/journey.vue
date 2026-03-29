<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()

// --- Mood check-in state ---
const score = ref(5)
const notes = ref('')
const submitting = ref(false)
const submitError = ref('')
const submitSuccess = ref(false)

// --- Data state ---
const trends = ref<any>(null)
const trendsLoading = ref(true)

const moods = ref<any[]>([])
const moodsLoading = ref(true)
const moodsError = ref('')

const insights = ref<any[]>([])
const insightsLoading = ref(true)

const conversationCount = ref(0)
const journalCount = ref(0)
const voiceCount = ref(0)
const statsLoading = ref(true)

// --- Mood check-in ---
async function submitMood() {
  submitting.value = true
  submitError.value = ''
  submitSuccess.value = false
  try {
    await api.post('/moods', { score: score.value, notes: notes.value })
    submitSuccess.value = true
    notes.value = ''
    score.value = 5
    await Promise.all([loadMoods(), loadTrends()])
  } catch {
    submitError.value = 'Could not save mood check-in.'
  } finally {
    submitting.value = false
  }
}

// --- Data loaders ---
async function loadTrends() {
  trendsLoading.value = true
  try {
    trends.value = await api.get<any>('/moods/trends')
  } catch {
    trends.value = null
  } finally {
    trendsLoading.value = false
  }
}

async function loadMoods() {
  moodsLoading.value = true
  moodsError.value = ''
  try {
    const data = await api.get<any>('/moods')
    const items = Array.isArray(data) ? data : (data?.moods || data?.items || [])
    moods.value = items.slice(0, 10)
  } catch {
    moodsError.value = 'Could not load mood history.'
  } finally {
    moodsLoading.value = false
  }
}

async function loadInsights() {
  insightsLoading.value = true
  try {
    const data = await api.get<any>('/insights?page=1')
    const items = Array.isArray(data) ? data : (data?.insights || data?.items || data?.results || [])
    insights.value = items.slice(0, 3)
  } catch {
    insights.value = []
  } finally {
    insightsLoading.value = false
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

// --- Helpers ---
function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
}

function scoreColor(s: number) {
  if (s >= 8) return 'bg-[#7aa87a]'
  if (s >= 5) return 'bg-[#c99262]'
  return 'bg-[#b86a4a]'
}

function trendLabel(t: string) {
  if (t === 'improving') return '↑ Improving'
  if (t === 'declining') return '↓ Declining'
  return '→ Stable'
}

function trendColor(t: string) {
  if (t === 'improving') return 'text-green-700'
  if (t === 'declining') return 'text-red-600'
  return 'text-[#8a5b3f]'
}

function sourceLabel(s: string) {
  const map: Record<string, string> = {
    conversation: 'Conversation',
    journal: 'Journal',
  }
  return map[s] || s || 'Unknown'
}

const dailyMax = computed(() => {
  const avgs = trends.value?.daily_averages || []
  return Math.max(...avgs.map((d: any) => d.average || 0), 1)
})

onMounted(() => {
  loadTrends()
  loadMoods()
  loadInsights()
  loadStats()
})
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Header -->
    <p class="text-[13px] sm:text-sm text-[#6b5740]">See how you're growing over time.</p>

    <!-- Mood Over Time -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Mood Over Time</p>

      <div v-if="trendsLoading" class="mt-4 space-y-3">
        <div class="h-16 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
        <div class="h-20 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <template v-else-if="trends">
        <!-- Average and trend -->
        <div class="mt-4 grid grid-cols-2 gap-3">
          <div class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-4 py-4 text-center">
            <p class="text-3xl font-bold text-[#c4873b]">{{ trends.average?.toFixed(1) ?? '--' }}</p>
            <p class="mt-1 text-[10px] uppercase tracking-[0.2em] text-[#9a8568]">Average Score</p>
          </div>
          <div class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-4 py-4 text-center">
            <p class="text-2xl font-bold" :class="trendColor(trends.trend)">{{ trendLabel(trends.trend) }}</p>
            <p class="mt-1 text-[10px] uppercase tracking-[0.2em] text-[#9a8568]">Direction</p>
          </div>
        </div>

        <!-- Bar chart -->
        <div v-if="trends.daily_averages?.length" class="mt-5">
          <p class="mb-2 text-[10px] font-medium uppercase tracking-[0.2em] text-[#a38d6d]">Daily Averages (last {{ Math.min(trends.daily_averages.length, 14) }} days)</p>
          <div class="flex items-end gap-1">
            <div
              v-for="day in trends.daily_averages.slice(-14)"
              :key="day.date"
              class="flex flex-1 flex-col items-center gap-1"
            >
              <span class="text-[9px] text-[#b5996f]">{{ day.average?.toFixed(1) }}</span>
              <div
                class="w-full rounded-t bg-gradient-to-t from-[#8b5a1b] to-[#c4873b] opacity-75 transition-all duration-200"
                :style="{ height: `${((day.average || 0) / dailyMax) * 60 + 4}px` }"
                :title="`${day.date}: ${day.average?.toFixed(1)}`"
              />
              <span class="text-[8px] text-[#b5996f]">{{ new Date(day.date).getDate() }}</span>
            </div>
          </div>
        </div>
      </template>

      <div v-else class="mt-4 text-sm text-[#6b5740]">No mood data yet. Start with a check-in below.</div>
    </div>

    <!-- Practice Stats -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Practice Stats</p>

      <div v-if="statsLoading" class="mt-4 grid grid-cols-3 gap-3">
        <div v-for="i in 3" :key="i" class="h-20 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else class="mt-4 grid grid-cols-3 gap-3">
        <div class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-[rgba(196,135,59,0.15)] to-[rgba(196,135,59,0.05)]">
            <SacredIcons name="dialogue" :size="14" />
          </div>
          <p class="text-2xl font-bold text-[#c4873b]">{{ conversationCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Conversations</p>
        </div>
        <div class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-[rgba(196,135,59,0.15)] to-[rgba(196,135,59,0.05)]">
            <SacredIcons name="scroll" :size="14" />
          </div>
          <p class="text-2xl font-bold text-[#c4873b]">{{ journalCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Journals</p>
        </div>
        <div class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-4 text-center">
          <div class="mx-auto mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-[rgba(196,135,59,0.15)] to-[rgba(196,135,59,0.05)]">
            <SacredIcons name="shankha" :size="14" />
          </div>
          <p class="text-2xl font-bold text-[#c4873b]">{{ voiceCount }}</p>
          <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Voice Notes</p>
        </div>
      </div>
    </div>

    <!-- Recent Insights -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <div class="flex items-center justify-between">
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Recent Insights</p>
        <router-link
          to="/app/journey/insights"
          class="min-h-[44px] flex items-center text-xs font-medium text-[#c4873b] transition duration-200 hover:text-[#8b5a1b]"
        >
          View all
        </router-link>
      </div>

      <div v-if="insightsLoading" class="mt-3 space-y-2">
        <div v-for="i in 3" :key="i" class="h-16 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else-if="insights.length === 0" class="mt-3 text-sm text-[#6b5740]">
        No insights yet. They are generated during conversations and journal sessions.
      </div>

      <ul v-else class="mt-3 space-y-2">
        <li
          v-for="insight in insights"
          :key="insight.id"
          class="rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3"
        >
          <p class="text-sm leading-relaxed text-[#2b1e10]">{{ insight.content }}</p>
          <p class="mt-1.5 text-[10px] uppercase tracking-[0.15em] text-[#a38d6d]">{{ sourceLabel(insight.source) }}</p>
        </li>
      </ul>
    </div>

    <!-- Quick Check-in -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Quick Check-in</p>
      <div class="mt-4 space-y-4">
        <div class="flex items-center gap-4">
          <span class="w-10 text-center text-2xl font-bold text-[#c4873b]">{{ score }}</span>
          <div class="flex-1">
            <input
              v-model.number="score"
              type="range" min="1" max="10" step="1"
              class="h-2 w-full cursor-pointer appearance-none rounded-full bg-[#e6d5c3] accent-[#c4873b]"
            />
            <div class="mt-1 flex justify-between text-[10px] text-[#9a8568]">
              <span>1 -- Very low</span>
              <span>5 -- Okay</span>
              <span>10 -- Excellent</span>
            </div>
          </div>
        </div>
        <textarea
          v-model="notes"
          placeholder="Optional: What is contributing to this feeling?"
          rows="2"
          class="w-full resize-none rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] px-4 py-3 text-sm text-[#2b1e10] placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
        />
        <p v-if="submitError" class="rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-sm text-red-700">{{ submitError }}</p>
        <p v-if="submitSuccess" class="rounded-xl bg-[rgba(90,160,90,0.12)] px-4 py-2 text-sm text-green-700">Check-in saved!</p>
        <button
          @click="submitMood"
          :disabled="submitting"
          class="min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
        >
          {{ submitting ? 'Saving...' : 'Save Check-in' }}
        </button>
      </div>
    </div>

    <!-- Mood History -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Mood History</p>

      <p v-if="moodsError" class="mt-3 text-sm text-red-700">{{ moodsError }}</p>

      <div v-if="moodsLoading" class="mt-4 space-y-2">
        <div v-for="i in 5" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else-if="moods.length === 0" class="mt-4 text-sm text-[#6b5740]">No check-ins yet.</div>

      <ul v-else class="mt-4 space-y-2">
        <li
          v-for="mood in moods"
          :key="mood.id"
          class="flex items-start gap-3 rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3"
        >
          <span class="shrink-0 rounded-xl px-2.5 py-1 text-sm font-bold text-white" :class="scoreColor(mood.score)">{{ mood.score }}</span>
          <div class="min-w-0 flex-1">
            <p v-if="mood.notes" class="text-sm text-[#2b1e10]">{{ mood.notes }}</p>
            <p class="text-xs text-[#b5996f]">{{ mood.created_at ? formatDate(mood.created_at) : '' }}</p>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
