<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'

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
    router.push('/app/journal')
  } catch {
    error.value = 'Could not delete entry.'
    deleting.value = false
  }
}

onMounted(load)
watch(id, load)
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5">
    <div class="flex items-center justify-between gap-3">
      <div class="flex items-center gap-3">
        <RouterLink to="/app/journal" class="rounded-xl p-1.5 text-[#6c5c4d] transition hover:bg-[rgba(138,91,63,0.08)]">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
        </RouterLink>
        <h1 class="font-serif text-2xl text-[#2b221a]">Journal Entry</h1>
      </div>
      <button
        @click="deleteEntry"
        :disabled="deleting"
        class="rounded-full border border-[rgba(220,50,50,0.2)] px-4 py-1.5 text-sm font-medium text-red-600 transition hover:bg-[rgba(220,50,50,0.08)] disabled:opacity-60"
      >
        {{ deleting ? 'Deleting…' : 'Delete' }}
      </button>
    </div>

    <div v-if="loading" class="space-y-3">
      <div class="h-12 animate-pulse rounded-2xl bg-[rgba(138,91,63,0.08)]" />
      <div class="h-64 animate-pulse rounded-2xl bg-[rgba(138,91,63,0.08)]" />
    </div>

    <div v-else class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.82)] p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[14px]">
      <div class="space-y-4">
        <div>
          <label class="mb-1.5 block text-xs font-semibold uppercase tracking-widest text-[#8a5b3f]">Title</label>
          <input
            v-model="title"
            type="text"
            placeholder="Entry title"
            class="w-full rounded-2xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,248,239,0.9)] px-4 py-3 text-[#2b221a] placeholder-[#b89c87] outline-none transition focus:border-[#c99262] focus:ring-1 focus:ring-[#c99262]"
          />
        </div>
        <div>
          <label class="mb-1.5 block text-xs font-semibold uppercase tracking-widest text-[#8a5b3f]">Content</label>
          <textarea
            v-model="content"
            rows="14"
            placeholder="Your thoughts…"
            class="w-full resize-y rounded-2xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,248,239,0.9)] px-4 py-3 text-[#2b221a] placeholder-[#b89c87] outline-none transition focus:border-[#c99262] focus:ring-1 focus:ring-[#c99262]"
          />
        </div>
        <p v-if="error" class="rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-sm text-red-700">{{ error }}</p>
        <p v-if="saveSuccess" class="rounded-xl bg-[rgba(90,160,90,0.12)] px-4 py-2 text-sm text-green-700">Saved successfully.</p>
        <button
          @click="save"
          :disabled="saving"
          class="rounded-full bg-[#2b221a] px-6 py-2.5 text-sm font-semibold text-[#fff8f1] transition hover:-translate-y-0.5 disabled:opacity-60"
        >
          {{ saving ? 'Saving…' : 'Save Changes' }}
        </button>
      </div>
    </div>
  </div>
</template>
