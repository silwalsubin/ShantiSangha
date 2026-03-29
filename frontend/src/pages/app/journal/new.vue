<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

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
  <div class="mx-auto max-w-2xl px-4 py-4 sm:px-6 sm:py-6">
    <!-- Header -->
    <div class="mb-5 flex items-center gap-3">
      <RouterLink
        to="/app/journal"
        class="flex h-11 w-11 items-center justify-center rounded-xl text-[#6b5740] transition duration-200 hover:bg-[rgba(139,90,43,0.08)]"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
        </svg>
      </RouterLink>
      <div class="flex items-center gap-2.5">
        <div class="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white shadow-[0_2px_8px_rgba(139,90,43,0.25)]">
          <SacredIcons name="scroll" :size="18" />
        </div>
        <div>
          <h1 class="font-serif text-xl font-bold tracking-wide text-[#2b1e10] sm:text-2xl">New Entry</h1>
          <p class="text-[9px] uppercase tracking-[0.2em] text-[#a38d6d]">Journal</p>
        </div>
      </div>
    </div>

    <!-- Form card -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <div class="space-y-5">
        <!-- Title field -->
        <div>
          <label class="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Title</label>
          <input
            v-model="title"
            type="text"
            placeholder="Give this entry a title (optional)"
            class="min-h-[44px] w-full rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.9)] px-4 py-3 text-[#2b1e10] placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
          />
        </div>

        <!-- Content field -->
        <div>
          <label class="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Your thoughts</label>
          <textarea
            v-model="content"
            placeholder="What is on your mind? Write freely -- this is your private space."
            rows="12"
            class="w-full resize-y rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.9)] px-4 py-3 text-[#2b1e10] leading-relaxed placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
          />
        </div>

        <!-- Error -->
        <p v-if="error" class="rounded-xl border border-[rgba(220,50,50,0.15)] bg-[rgba(220,50,50,0.06)] px-4 py-2.5 text-sm text-red-700">{{ error }}</p>

        <!-- Actions -->
        <div class="flex flex-col gap-3 sm:flex-row">
          <button
            @click="save"
            :disabled="saving"
            class="flex min-h-[44px] items-center justify-center rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_2px_12px_rgba(139,90,43,0.3)] transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
          >
            {{ saving ? 'Saving...' : 'Save Entry' }}
          </button>
          <RouterLink
            to="/app/journal"
            class="flex min-h-[44px] items-center justify-center rounded-xl border border-[rgba(139,90,43,0.15)] px-6 py-2.5 text-sm font-semibold text-[#6b5740] transition duration-200 hover:bg-[rgba(139,90,43,0.05)]"
          >
            Cancel
          </RouterLink>
        </div>
      </div>
    </div>

    <!-- Footer wisdom -->
    <p class="mt-8 text-center text-xs italic leading-relaxed text-[#b5996f]">
      "Know thyself" -- the eternal call of Atma-Jnana
    </p>
  </div>
</template>
