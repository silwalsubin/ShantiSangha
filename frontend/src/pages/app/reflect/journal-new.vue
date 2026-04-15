<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()
const router = useRouter()

const title = ref('')
const content = ref('')
const saving = ref(false)
const error = ref('')
const promptText = ref('What is on your mind? Write freely -- this is your private space.')

onMounted(async () => {
  try {
    const today = new Date()
    const dateStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`
    const res = await api.get<{ prompt: string | null }>(`/journal/prompt?date=${dateStr}`)
    if (res.prompt) promptText.value = res.prompt
  } catch {
    // Fallback placeholder already set
  }
})

async function save() {
  if (!content.value.trim()) {
    error.value = 'Please write something before saving.'
    return
  }
  saving.value = true
  error.value = ''
  try {
    await api.post('/journals', {
      title: title.value.trim() || 'Untitled',
      content: content.value,
    })
    router.push('/app/reflect')
  } catch {
    error.value = 'Could not save entry. Please try again.'
  } finally {
    saving.value = false
  }
}
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
          <SacredIcons name="scroll" :size="18" />
        </div>
        <div>
          <h1 class="font-serif text-xl font-bold tracking-wide text-sacred-text sm:text-2xl">New Entry</h1>
          <p class="text-[9px] uppercase tracking-[0.2em] text-sacred-label">Journal</p>
        </div>
      </div>
    </div>

    <!-- Form card -->
    <div class="rounded-2xl border border-sacred-border bg-sacred-bg-card p-4 shadow-sacred backdrop-blur-[20px] sm:p-6">
      <div class="space-y-5">
        <!-- Title field -->
        <div>
          <label class="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.2em] text-sacred-label">Title</label>
          <input
            v-model="title"
            type="text"
            placeholder="Give this entry a title (optional)"
            class="min-h-[44px] w-full rounded-2xl border border-sacred-border bg-sacred-bg-card px-4 py-3 text-sacred-text placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold"
          />
        </div>

        <!-- Content field -->
        <div>
          <label class="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.2em] text-sacred-label">Your thoughts</label>
          <textarea
            v-model="content"
            :placeholder="promptText"
            rows="12"
            class="w-full resize-y rounded-2xl border border-sacred-border bg-sacred-bg-card px-4 py-3 text-sacred-text leading-relaxed placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold"
          />
        </div>

        <!-- Error -->
        <p v-if="error" class="rounded-xl border border-sacred-error-border bg-sacred-error px-4 py-2.5 text-sm text-red-700">{{ error }}</p>

        <!-- Actions -->
        <div class="flex flex-col gap-3 sm:flex-row">
          <button
            @click="save"
            :disabled="saving"
            class="flex min-h-[44px] items-center justify-center rounded-xl bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-2.5 text-sm font-semibold text-white shadow-sacred-glow transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
          >
            {{ saving ? 'Saving...' : 'Save Entry' }}
          </button>
          <RouterLink
            to="/app/reflect"
            class="flex min-h-[44px] items-center justify-center rounded-xl border border-sacred-border-strong px-6 py-2.5 text-sm font-semibold text-sacred-text-secondary transition duration-200 hover:bg-sacred-bg-hover"
          >
            Cancel
          </RouterLink>
        </div>
      </div>
    </div>

    <!-- Footer wisdom -->
    <p class="mt-8 text-center text-xs italic leading-relaxed text-sacred-muted-light">
      "Know thyself" -- the eternal call of Atma-Jnana
    </p>
  </div>
</template>
