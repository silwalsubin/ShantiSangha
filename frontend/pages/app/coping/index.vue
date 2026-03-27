<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'app' })

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
    breathing: 'bg-[rgba(90,130,160,0.12)] text-[#3a7094]',
    grounding: 'bg-[rgba(90,140,90,0.12)] text-[#3a7d3a]',
    mindfulness: 'bg-[rgba(160,90,130,0.12)] text-[#8a3a6a]',
    movement: 'bg-[rgba(201,146,98,0.14)] text-[#8a5b3f]',
  }
  return map[cat?.toLowerCase()] || 'bg-[rgba(138,91,63,0.1)] text-[#6c5c4d]'
}

onBeforeUnmount(() => {
  if (timerInterval.value) clearInterval(timerInterval.value)
})

onMounted(load)
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-5">
    <div>
      <h1 class="font-serif text-2xl text-[#2b221a]">Coping Exercises</h1>
      <p class="mt-1 text-sm text-[#6c5c4d]">Grounding tools for emotionally heavy moments.</p>
    </div>

    <p v-if="error" class="rounded-2xl bg-[rgba(220,50,50,0.08)] px-4 py-3 text-sm text-red-700">{{ error }}</p>

    <div v-if="loading" class="grid gap-4 sm:grid-cols-2">
      <div v-for="i in 4" :key="i" class="h-40 animate-pulse rounded-3xl bg-[rgba(138,91,63,0.08)]" />
    </div>

    <div v-else-if="exercises.length === 0" class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.82)] px-6 py-12 text-center backdrop-blur-[14px]">
      <p class="font-serif text-xl text-[#2b221a]">No exercises available</p>
      <p class="mt-2 text-sm text-[#6c5c4d]">Check back soon for grounding and coping tools.</p>
    </div>

    <div v-else class="grid gap-4 sm:grid-cols-2">
      <article
        v-for="exercise in exercises"
        :key="exercise.slug || exercise.id"
        class="flex flex-col rounded-3xl border border-[rgba(101,76,52,0.12)] bg-[rgba(255,250,243,0.82)] p-5 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[14px] transition hover:border-[rgba(138,91,63,0.24)] hover:shadow-[0_8px_32px_rgba(82,54,29,0.1)]"
      >
        <div class="flex items-start justify-between gap-2">
          <h2 class="font-serif text-lg text-[#2b221a]">{{ exercise.name }}</h2>
          <span v-if="exercise.category" class="shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium" :class="categoryColor(exercise.category)">
            {{ exercise.category }}
          </span>
        </div>
        <p class="mt-2 flex-1 text-sm leading-relaxed text-[#6c5c4d]">{{ exercise.description }}</p>
        <div class="mt-4 flex items-center justify-between">
          <span v-if="exercise.duration" class="text-xs text-[#b89c87]">⏱ {{ exercise.duration }}</span>
          <button
            @click="startExercise(exercise)"
            class="rounded-full bg-[#8a5b3f] px-4 py-1.5 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-[#7a4c32]"
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
        class="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(43,34,26,0.5)] p-4 backdrop-blur-sm"
        @click.self="closeModal"
      >
        <div class="w-full max-w-sm rounded-3xl border border-[rgba(101,76,52,0.16)] bg-[#f9f2e8] p-8 shadow-[0_32px_80px_rgba(43,34,26,0.2)]">
          <p class="text-center text-xs font-bold uppercase tracking-widest text-[#8a5b3f]">{{ activeExercise.category }}</p>
          <h2 class="mt-2 text-center font-serif text-2xl text-[#2b221a]">{{ activeExercise.name }}</h2>
          <p class="mt-3 text-center text-sm leading-relaxed text-[#6c5c4d]">{{ activeExercise.description }}</p>

          <div class="mt-6 text-center">
            <p class="font-mono text-5xl font-bold text-[#8a5b3f]">{{ formatTime(timerSeconds) }}</p>
          </div>

          <div v-if="completeSuccess" class="mt-4 rounded-2xl bg-[rgba(90,160,90,0.12)] px-4 py-2 text-center text-sm text-green-700">
            Session recorded! Well done.
          </div>

          <div class="mt-6 flex flex-wrap justify-center gap-3">
            <button
              v-if="timerRunning"
              @click="pauseTimer"
              class="rounded-full border border-[rgba(101,76,52,0.16)] px-5 py-2 text-sm font-semibold text-[#6c5c4d] transition hover:bg-[rgba(138,91,63,0.06)]"
            >
              Pause
            </button>
            <button
              v-else-if="!completeSuccess"
              @click="resumeTimer"
              class="rounded-full border border-[rgba(101,76,52,0.16)] px-5 py-2 text-sm font-semibold text-[#6c5c4d] transition hover:bg-[rgba(138,91,63,0.06)]"
            >
              Resume
            </button>
            <button
              v-if="!completeSuccess"
              @click="completeExercise"
              :disabled="completing"
              class="rounded-full bg-[#2b221a] px-5 py-2 text-sm font-semibold text-[#fff8f1] transition hover:-translate-y-0.5 disabled:opacity-60"
            >
              {{ completing ? 'Saving…' : 'Complete' }}
            </button>
            <button
              @click="closeModal"
              class="rounded-full border border-[rgba(101,76,52,0.12)] px-5 py-2 text-sm font-medium text-[#b89c87] transition hover:text-[#6c5c4d]"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
