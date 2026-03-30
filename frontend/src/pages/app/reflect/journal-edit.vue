<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const route = useRoute()
const router = useRouter()
const api = useApi()
const id = computed(() => route.params.id as string)

const entry = ref<any>(null)
const title = ref('')
const content = ref('')
const loading = ref(true)
const saving = ref(false)
const deleting = ref(false)
const error = ref('')
const saveSuccess = ref(false)

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get<any>(`/journals/${id.value}`)
    entry.value = data
    title.value = data.title || ''
    content.value = data.content || ''
  } catch {
    error.value = 'Could not load journal entry.'
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  error.value = ''
  saveSuccess.value = false
  try {
    await api.patch(`/journals/${id.value}`, {
      title: title.value.trim() || 'Untitled',
      content: content.value,
    })
    saveSuccess.value = true
    setTimeout(() => { saveSuccess.value = false }, 2500)
  } catch {
    error.value = 'Could not save changes.'
  } finally {
    saving.value = false
  }
}

async function deleteEntry() {
  if (!confirm('Delete this journal entry?')) return
  deleting.value = true
  try {
    await api.delete(`/journals/${id.value}`)
    router.push('/app/reflect')
  } catch {
    error.value = 'Could not delete entry.'
    deleting.value = false
  }
}

onMounted(load)
watch(id, load)
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 py-4 sm:px-6 sm:py-6">
    <!-- Header -->
    <div class="mb-5 flex items-center justify-between gap-3">
      <div class="flex items-center gap-3">
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
            <SacredIcons name="scroll" :size="18" />
          </div>
          <div>
            <h1 class="font-serif text-xl font-bold tracking-wide text-sacred-text sm:text-2xl">Edit Entry</h1>
            <p class="text-[9px] uppercase tracking-[0.2em] text-sacred-label">Journal</p>
          </div>
        </div>
      </div>
      <button
        @click="deleteEntry"
        :disabled="deleting"
        class="flex min-h-[44px] items-center rounded-xl border border-sacred-error-border px-4 py-2 text-sm font-medium text-red-600 transition duration-200 hover:bg-sacred-error disabled:opacity-60"
      >
        {{ deleting ? 'Deleting...' : 'Delete' }}
      </button>
    </div>

    <!-- Loading skeletons -->
    <div v-if="loading" class="space-y-3">
      <div class="h-12 animate-pulse rounded-2xl bg-sacred-bg-hover" />
      <div class="h-64 animate-pulse rounded-2xl bg-sacred-bg-hover" />
    </div>

    <!-- Edit form card -->
    <div v-else class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
      <div class="space-y-5">
        <!-- Title field -->
        <div>
          <label class="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.2em] text-sacred-label">Title</label>
          <input
            v-model="title"
            type="text"
            placeholder="Entry title"
            class="min-h-[44px] w-full rounded-2xl border border-sacred-border bg-sacred-bg-card px-4 py-3 text-sacred-text placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold"
          />
        </div>

        <!-- Content field -->
        <div>
          <label class="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.2em] text-sacred-label">Content</label>
          <textarea
            v-model="content"
            rows="14"
            placeholder="Your thoughts..."
            class="w-full resize-y rounded-2xl border border-sacred-border bg-sacred-bg-card px-4 py-3 text-sacred-text leading-relaxed placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold"
          />
        </div>

        <!-- Error -->
        <p v-if="error" class="rounded-xl border border-sacred-error-border bg-sacred-error px-4 py-2.5 text-sm text-red-700">{{ error }}</p>

        <!-- Success -->
        <p v-if="saveSuccess" class="rounded-xl border border-sacred-success-bg bg-sacred-success-bg px-4 py-2.5 text-sm text-green-700">Saved successfully.</p>

        <!-- Actions -->
        <div class="flex flex-col gap-3 sm:flex-row">
          <button
            @click="save"
            :disabled="saving"
            class="flex min-h-[44px] items-center justify-center rounded-xl bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-2.5 text-sm font-semibold text-white shadow-sacred-glow transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
          >
            {{ saving ? 'Saving...' : 'Save Changes' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Footer wisdom -->
    <p v-if="!loading" class="mt-8 text-center text-xs italic leading-relaxed text-sacred-muted-light">
      "As a lamp in a windless place does not flicker" -- Bhagavad Gita 6.19
    </p>
  </div>
</template>
