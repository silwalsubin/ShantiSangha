<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()

const score = ref(5)
const notes = ref('')
const submitting = ref(false)
const submitError = ref('')
const submitSuccess = ref(false)

const moods = ref<any[]>([])
const moodsLoading = ref(true)
const moodsError = ref('')

const trends = ref<any>(null)
const trendsLoading = ref(true)

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

async function loadMoods() {
  moodsLoading.value = true
  moodsError.value = ''
  try {
    const data = await api.get<any>('/moods')
    moods.value = Array.isArray(data) ? data : (data?.moods || data?.items || [])
  } catch {
    moodsError.value = 'Could not load mood history.'
  } finally {
    moodsLoading.value = false
  }
}

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

const dailyMax = computed(() => {
  const avgs = trends.value?.daily_averages || []
  return Math.max(...avgs.map((d: any) => d.average || 0), 1)
})

onMounted(() => {
  loadMoods()
  loadTrends()
})
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Header -->
    <div class="flex items-center gap-3">
      <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
        <SacredIcons name="chakra" :size="20" />
      </div>
      <div>
        <h1 class="font-serif text-xl font-bold tracking-wide text-[#2b1e10] sm:text-2xl">Mood Check-in</h1>
        <p class="mt-0.5 text-sm text-[#6b5740]">Track how you are feeling over time.</p>
      </div>
    </div>

    <!-- Quick check-in -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Log a Check-in</p>
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
          class="min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
        >
          {{ submitting ? 'Saving...' : 'Save Check-in' }}
        </button>
      </div>
    </div>

    <!-- Trends -->
    <div v-if="!trendsLoading && trends" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Trends</p>
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
    </div>

    <!-- History -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">History</p>
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
