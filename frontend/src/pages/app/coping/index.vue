<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()

const exercises = ref<any[]>([])
const loading = ref(true)
const error = ref('')

// Timer/modal state
const activeExercise = ref<any>(null)
const timerSeconds = ref(0)
const timerRunning = ref(false)
const timerInterval = ref<ReturnType<typeof setInterval> | null>(null)
const completing = ref(false)
const completeSuccess = ref(false)

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get<any>('/exercises')
    exercises.value = Array.isArray(data) ? data : (data?.exercises || data?.items || [])
  } catch {
    error.value = 'Could not load exercises.'
  } finally {
    loading.value = false
  }
}

function startExercise(exercise: any) {
  activeExercise.value = exercise
  timerSeconds.value = 0
  timerRunning.value = true
  completeSuccess.value = false
  timerInterval.value = setInterval(() => {
    timerSeconds.value++
  }, 1000)
}

function pauseTimer() {
  if (timerInterval.value) {
    clearInterval(timerInterval.value)
    timerInterval.value = null
  }
  timerRunning.value = false
}

function resumeTimer() {
  timerRunning.value = true
  timerInterval.value = setInterval(() => {
    timerSeconds.value++
  }, 1000)
}

async function completeExercise() {
  if (!activeExercise.value) return
  pauseTimer()
  completing.value = true
  try {
    await api.post(`/exercises/${activeExercise.value.slug}/sessions`, {
      duration_seconds: timerSeconds.value,
    })
    completeSuccess.value = true
    setTimeout(closeModal, 2000)
  } catch {
    error.value = 'Could not record session.'
  } finally {
    completing.value = false
  }
}

function closeModal() {
  pauseTimer()
  activeExercise.value = null
  timerSeconds.value = 0
  completeSuccess.value = false
}

function formatTime(s: number) {
  const m = Math.floor(s / 60)
  const sec = s % 60
  return `${m}:${sec.toString().padStart(2, '0')}`
}

function categoryColor(cat: string) {
  const map: Record<string, string> = {
    breathing: 'bg-[rgba(196,135,59,0.12)] text-[#8b5a1b]',
    grounding: 'bg-[rgba(139,90,43,0.12)] text-[#6b5740]',
    mindfulness: 'bg-[rgba(196,135,59,0.15)] text-[#c4873b]',
    movement: 'bg-[rgba(139,90,43,0.14)] text-[#8b5a1b]',
  }
  return map[cat?.toLowerCase()] || 'bg-[rgba(139,90,43,0.1)] text-[#6b5740]'
}

onBeforeUnmount(() => {
  if (timerInterval.value) clearInterval(timerInterval.value)
})

onMounted(load)
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-5 p-4 sm:p-6">
    <!-- Header -->
    <div class="flex items-center gap-3">
      <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
        <SacredIcons name="lotus" :size="20" />
      </div>
      <div>
        <h1 class="font-serif text-xl font-bold tracking-wide text-[#2b1e10] sm:text-2xl">Coping Exercises</h1>
        <p class="mt-0.5 text-sm text-[#6b5740]">Grounding tools for emotionally heavy moments.</p>
      </div>
    </div>

    <p v-if="error" class="rounded-2xl bg-[rgba(220,50,50,0.08)] px-4 py-3 text-sm text-red-700">{{ error }}</p>

    <div v-if="loading" class="grid gap-4 sm:grid-cols-2">
      <div v-for="i in 4" :key="i" class="h-40 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
    </div>

    <div v-else-if="exercises.length === 0" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-6 py-12 text-center backdrop-blur-[20px]">
      <p class="font-serif text-xl text-[#2b1e10]">No exercises available</p>
      <p class="mt-2 text-sm text-[#6b5740]">Check back soon for grounding and coping tools.</p>
    </div>

    <div v-else class="grid gap-4 sm:grid-cols-2">
      <article
        v-for="exercise in exercises"
        :key="exercise.slug || exercise.id"
        class="flex flex-col rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] transition duration-200 hover:border-[rgba(139,90,43,0.24)] hover:shadow-[0_8px_32px_rgba(82,54,29,0.1)] sm:p-5"
      >
        <div class="flex items-start justify-between gap-2">
          <h2 class="font-serif text-lg font-bold text-[#2b1e10]">{{ exercise.name }}</h2>
          <span v-if="exercise.category" class="shrink-0 rounded-full px-2.5 py-0.5 text-[10px] font-medium uppercase tracking-[0.15em]" :class="categoryColor(exercise.category)">
            {{ exercise.category }}
          </span>
        </div>
        <p class="mt-2 flex-1 text-sm leading-relaxed text-[#6b5740]">{{ exercise.description }}</p>
        <div class="mt-4 flex items-center justify-between">
          <span v-if="exercise.duration" class="text-xs text-[#9a8568]">{{ exercise.duration }}</span>
          <button
            @click="startExercise(exercise)"
            class="min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-5 py-2 text-sm font-semibold text-white shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5"
          >
            Start
          </button>
        </div>
      </article>
    </div>

    <!-- Timer Modal -->
    <Teleport to="body">
      <div
        v-if="activeExercise"
        class="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(43,30,16,0.55)] p-4 backdrop-blur-[20px]"
        @click.self="closeModal"
      >
        <div class="w-full max-w-sm rounded-2xl border border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.97)] p-6 shadow-[0_32px_80px_rgba(43,30,16,0.25)] sm:p-8">
          <p class="text-center text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">{{ activeExercise.category }}</p>
          <h2 class="mt-2 text-center font-serif text-xl font-bold text-[#2b1e10] sm:text-2xl">{{ activeExercise.name }}</h2>
          <p class="mt-3 text-center text-sm leading-relaxed text-[#6b5740]">{{ activeExercise.description }}</p>

          <div class="mt-6 text-center">
            <p class="font-mono text-5xl font-bold text-[#c4873b]">{{ formatTime(timerSeconds) }}</p>
          </div>

          <div v-if="completeSuccess" class="mt-4 rounded-2xl bg-[rgba(90,160,90,0.12)] px-4 py-2 text-center text-sm text-green-700">
            Session recorded! Well done.
          </div>

          <div class="mt-6 flex flex-wrap justify-center gap-3">
            <button
              v-if="timerRunning"
              @click="pauseTimer"
              class="min-h-[44px] rounded-full border border-[rgba(139,90,43,0.15)] px-5 py-2 text-sm font-semibold text-[#6b5740] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
            >
              Pause
            </button>
            <button
              v-else-if="!completeSuccess"
              @click="resumeTimer"
              class="min-h-[44px] rounded-full border border-[rgba(139,90,43,0.15)] px-5 py-2 text-sm font-semibold text-[#6b5740] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
            >
              Resume
            </button>
            <button
              v-if="!completeSuccess"
              @click="completeExercise"
              :disabled="completing"
              class="min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-5 py-2 text-sm font-semibold text-white shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
            >
              {{ completing ? 'Saving...' : 'Complete' }}
            </button>
            <button
              @click="closeModal"
              class="min-h-[44px] rounded-full border border-[rgba(139,90,43,0.12)] px-5 py-2 text-sm font-medium text-[#9a8568] transition duration-200 hover:text-[#6b5740]"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
