<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'

const api = useApi()
const router = useRouter()

const title = ref('')
const content = ref('')
const saving = ref(false)
const error = ref('')

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
    router.push('/app/journal')
  } catch {
    error.value = 'Could not save entry. Please try again.'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5">
    <div class="flex items-center gap-3">
      <RouterLink to="/app/journal" class="rounded-xl p-1.5 text-[#6c5c4d] transition hover:bg-[rgba(138,91,63,0.08)]">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
        </svg>
      </RouterLink>
      <h1 class="font-serif text-2xl text-[#2b221a]">New Journal Entry</h1>
    </div>

    <div class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.82)] p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[14px]">
      <div class="space-y-4">
        <div>
          <label class="mb-1.5 block text-xs font-semibold uppercase tracking-widest text-[#8a5b3f]">Title</label>
          <input
            v-model="title"
            type="text"
            placeholder="Give this entry a title (optional)"
            class="w-full rounded-2xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,248,239,0.9)] px-4 py-3 text-[#2b221a] placeholder-[#b89c87] outline-none transition focus:border-[#c99262] focus:ring-1 focus:ring-[#c99262]"
          />
        </div>
        <div>
          <label class="mb-1.5 block text-xs font-semibold uppercase tracking-widest text-[#8a5b3f]">Your thoughts</label>
          <textarea
            v-model="content"
            placeholder="What's on your mind? Write freely — this is your private space."
            rows="12"
            class="w-full resize-y rounded-2xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,248,239,0.9)] px-4 py-3 text-[#2b221a] placeholder-[#b89c87] outline-none transition focus:border-[#c99262] focus:ring-1 focus:ring-[#c99262]"
          />
        </div>
        <p v-if="error" class="rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-sm text-red-700">{{ error }}</p>
        <div class="flex gap-3">
          <button
            @click="save"
            :disabled="saving"
            class="rounded-full bg-[#2b221a] px-6 py-2.5 text-sm font-semibold text-[#fff8f1] transition hover:-translate-y-0.5 disabled:opacity-60"
          >
            {{ saving ? 'Saving…' : 'Save Entry' }}
          </button>
          <RouterLink to="/app/journal" class="rounded-full border border-[rgba(101,76,52,0.16)] px-6 py-2.5 text-sm font-semibold text-[#6c5c4d] transition hover:bg-[rgba(138,91,63,0.06)]">
            Cancel
          </RouterLink>
        </div>
      </div>
    </div>
  </div>
</template>
