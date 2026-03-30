<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const route = useRoute()
const api = useApi()
const id = computed(() => route.params.id as string)

const entry = ref<any>(null)
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    entry.value = await api.get<any>(`/voice/entries/${id.value}`)
  } catch {
    error.value = 'Could not load voice entry.'
  } finally {
    loading.value = false
  }
}

function formatTime(s: number) {
  const m = Math.floor(s / 60)
  const sec = s % 60
  return `${m}:${sec.toString().padStart(2, '0')}`
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })
}

function statusColor(status: string) {
  const map: Record<string, string> = {
    Completed: 'bg-sacred-success-bg text-green-700',
    Transcribing: 'bg-sacred-gold-14 text-sacred-gold-dark',
    Pending: 'bg-sacred-border-subtle text-sacred-text-secondary',
    Failed: 'bg-sacred-error-strong text-red-600',
  }
  return map[status] || 'bg-sacred-border-subtle text-sacred-text-secondary'
}

onMounted(load)
watch(id, load)
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 py-4 sm:px-6 sm:py-6">
    <!-- Header -->
    <div class="mb-5 flex items-center gap-3">
      <RouterLink
        to="/app/reflect"
        class="flex h-11 w-11 items-center justify-center rounded-xl text-sacred-text-secondary transition duration-200 hover:bg-sacred-bg-hover-strong"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
        </svg>
      </RouterLink>
      <div class="flex items-center gap-2.5">
        <div class="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-sacred-gold to-sacred-gold-dark text-white shadow-sacred-glow">
          <SacredIcons name="shankha" :size="18" />
        </div>
        <div>
          <h1 class="font-serif text-xl font-bold tracking-wide text-sacred-text sm:text-2xl">Voice Note</h1>
          <p class="text-[9px] uppercase tracking-[0.2em] text-sacred-label">Reflection</p>
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="space-y-3">
      <div class="h-20 animate-pulse rounded-2xl bg-sacred-bg-hover" />
      <div class="h-40 animate-pulse rounded-2xl bg-sacred-bg-hover" />
    </div>

    <!-- Error -->
    <p v-else-if="error" class="rounded-2xl border border-sacred-error-border bg-sacred-error px-4 py-3 text-[13px] text-red-700">{{ error }}</p>

    <!-- Entry detail -->
    <div v-else-if="entry" class="space-y-4">

      <!-- Meta card -->
      <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
        <div class="flex flex-wrap items-center gap-3">
          <span class="rounded-full px-3 py-1 text-[11px] font-medium uppercase tracking-[0.1em]" :class="statusColor(entry.status)">
            {{ entry.status || 'Pending' }}
          </span>
          <span v-if="entry.duration_seconds" class="text-[13px] text-sacred-text-secondary">
            Duration: {{ formatTime(entry.duration_seconds) }}
          </span>
          <span v-if="entry.created_at" class="text-[13px] text-sacred-muted">
            {{ formatDate(entry.created_at) }}
          </span>
        </div>
      </div>

      <!-- Transcript card -->
      <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
        <p class="mb-3 text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Transcript</p>

        <div v-if="entry.transcript" class="text-[14px] leading-relaxed text-sacred-text whitespace-pre-wrap">{{ entry.transcript }}</div>

        <div v-else-if="entry.status === 'Transcribing'" class="flex items-center gap-3 py-4">
          <span class="h-5 w-5 animate-spin rounded-full border-2 border-sacred-gold border-t-transparent" />
          <p class="text-[13px] italic text-sacred-muted">Transcription in progress...</p>
        </div>

        <div v-else-if="entry.status === 'Pending'" class="py-4 text-center">
          <p class="text-[13px] italic text-sacred-muted">Waiting to be transcribed.</p>
        </div>

        <div v-else-if="entry.status === 'Failed'" class="py-4 text-center">
          <p class="text-[13px] text-red-500">Transcription failed.</p>
        </div>

        <div v-else class="py-4 text-center">
          <p class="text-[13px] italic text-sacred-muted">No transcript available.</p>
        </div>
      </div>
    </div>

    <!-- Footer wisdom -->
    <p v-if="!loading && entry" class="mt-8 text-center text-xs italic leading-relaxed text-sacred-muted-light">
      "The voice of the Self is heard in silence." -- inspired by the Upanishads
    </p>
  </div>
</template>
