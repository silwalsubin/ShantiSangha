<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import { useLocalDate } from '@/composables/useLocalDate'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const route = useRoute()
const router = useRouter()
const api = useApi()
const { today, formatDate } = useLocalDate()

const practiceId = computed(() => route.params.id as string)

interface Practice {
  id: string
  title: string
  deeperWhy: string | null
  currentStreak: number
  longestStreak: number
  frequency: string | null
  frequencyTarget: number | null
  createdAt: string
}

const practice = ref<Practice | null>(null)
const loading = ref(true)

const editingWhy = ref(false)
const whyInput = ref('')
const savingWhy = ref(false)

async function loadPractice() {
  loading.value = true
  try {
    const data = await api.get<any>(`/practices/${practiceId.value}?date=${today()}`)
    practice.value = {
      id: data.id,
      title: data.title,
      deeperWhy: data.deeperWhy ?? null,
      currentStreak: data.currentStreak ?? 0,
      longestStreak: data.longestStreak ?? 0,
      frequency: data.frequency ?? null,
      frequencyTarget: data.frequencyTarget ?? null,
      createdAt: data.createdAt ?? '',
    }
    whyInput.value = practice.value.deeperWhy ?? ''
  } catch {
    practice.value = null
  } finally {
    loading.value = false
  }
}

async function saveDeeperWhy() {
  if (!practice.value) return
  savingWhy.value = true
  try {
    await api.patch(`/practices/${practice.value.id}`, { deeperWhy: whyInput.value })
    practice.value.deeperWhy = whyInput.value || null
    editingWhy.value = false
  } catch {
    // keep editing
  } finally {
    savingWhy.value = false
  }
}

function startEditWhy() {
  whyInput.value = practice.value?.deeperWhy ?? ''
  editingWhy.value = true
}

function daysSinceCreated(): number {
  if (!practice.value) return 0
  const created = new Date(practice.value.createdAt)
  const now = new Date()
  return Math.floor((now.getTime() - created.getTime()) / 86400000)
}

onMounted(() => {
  loadPractice()
})
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Back button -->
    <button
      class="flex min-h-[44px] items-center gap-1.5 text-sm font-medium text-sacred-gold transition duration-200 hover:text-sacred-gold-dark"
      @click="router.push('/app/journey')"
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M12 19l-7-7 7-7"/></svg>
      Journey
    </button>

    <!-- Loading -->
    <div v-if="loading" class="space-y-4">
      <div class="h-8 w-3/4 animate-pulse rounded-xl bg-sacred-bg-hover-strong" />
      <div class="h-32 animate-pulse rounded-2xl bg-sacred-bg-hover" />
    </div>

    <!-- Not found -->
    <div v-else-if="!practice" class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-6 text-center">
      <p class="text-sm text-sacred-text-secondary">Practice not found.</p>
    </div>

    <template v-else>
      <!-- Header card -->
      <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
        <div class="flex items-start gap-2">
          <SacredIcons name="flame" :size="18" class="mt-0.5 text-sacred-gold" />
          <div class="flex-1">
            <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">
              Daily Practice
            </p>
            <h1 class="mt-1 font-serif text-xl font-bold text-sacred-text">{{ practice.title }}</h1>
          </div>
        </div>

        <!-- Stats -->
        <div class="mt-5 flex gap-3">
          <div class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
            <p class="text-2xl font-bold text-sacred-gold">{{ practice.currentStreak }}</p>
            <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Current Streak</p>
          </div>
          <div class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
            <p class="text-2xl font-bold text-sacred-gold">{{ practice.longestStreak }}</p>
            <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Longest Streak</p>
          </div>
          <div class="flex-1 rounded-2xl border border-sacred-border-light bg-sacred-bg-card-deep px-3 py-3 text-center">
            <p class="text-2xl font-bold text-sacred-gold">{{ daysSinceCreated() }}</p>
            <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-sacred-muted">Days Active</p>
          </div>
        </div>

        <!-- Created date -->
        <p class="mt-4 text-[10px] uppercase tracking-[0.15em] text-sacred-label">
          Started {{ formatDate(practice.createdAt) }}
        </p>
      </div>

      <!-- Deeper Why -->
      <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <SacredIcons name="lotus" :size="14" class="text-sacred-gold" />
            <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">The Deeper Why</p>
          </div>
          <button
            v-if="!editingWhy"
            class="min-h-[44px] text-xs font-medium text-sacred-gold transition duration-200 hover:text-sacred-gold-dark"
            @click="startEditWhy"
          >
            {{ practice.deeperWhy ? 'Edit' : 'Add' }}
          </button>
        </div>

        <div v-if="editingWhy" class="mt-3">
          <textarea
            v-model="whyInput"
            rows="3"
            class="w-full rounded-xl border border-sacred-border-strong bg-sacred-bg-card-deep px-3 py-2 text-sm text-sacred-text placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold-30"
            placeholder="Why does this practice matter to you? What deeper intention does it serve?"
          />
          <div class="mt-2 flex gap-2 justify-end">
            <button
              class="min-h-[44px] rounded-xl px-4 text-sm font-medium text-sacred-text-secondary transition duration-200 hover:bg-sacred-bg-hover"
              @click="editingWhy = false"
            >
              Cancel
            </button>
            <button
              class="min-h-[44px] rounded-xl bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-4 text-sm font-medium text-white shadow-sm transition duration-200 active:scale-[0.98] disabled:opacity-50"
              :disabled="savingWhy"
              @click="saveDeeperWhy"
            >
              Save
            </button>
          </div>
        </div>

        <p v-else-if="practice.deeperWhy" class="mt-3 font-serif text-sm italic leading-relaxed text-sacred-text">
          "{{ practice.deeperWhy }}"
        </p>

        <p v-else class="mt-3 text-sm text-sacred-muted">
          What draws you to this practice? Understanding the deeper intention behind your commitments can transform discipline into devotion.
        </p>
      </div>

      <!-- Check-in Calendar -->
      <div
        class="cursor-pointer rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] transition duration-150 hover:bg-sacred-bg-hover active:scale-[0.99] sm:p-6"
        @click="router.push(`/app/journey/practices/${practice.id}/calendar`)"
      >
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <SacredIcons name="chakra" :size="14" class="text-sacred-gold" />
            <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Check-in Calendar</p>
          </div>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-sacred-muted"><path d="M9 18l6-6-6-6"/></svg>
        </div>
        <p class="mt-3 text-sm text-sacred-muted">
          View, edit, or correct past entries.
        </p>
      </div>
    </template>
  </div>
</template>
