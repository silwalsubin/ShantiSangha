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
            <h1 class="font-serif text-xl font-bold tracking-wide text-[#2b1e10] sm:text-2xl">Edit Entry</h1>
            <p class="text-[9px] uppercase tracking-[0.2em] text-[#a38d6d]">Journal</p>
          </div>
        </div>
      </div>
      <button
        @click="deleteEntry"
        :disabled="deleting"
        class="flex min-h-[44px] items-center rounded-xl border border-[rgba(220,50,50,0.18)] px-4 py-2 text-sm font-medium text-red-600 transition duration-200 hover:bg-[rgba(220,50,50,0.06)] disabled:opacity-60"
      >
        {{ deleting ? 'Deleting...' : 'Delete' }}
      </button>
    </div>

    <!-- Loading skeletons -->
    <div v-if="loading" class="space-y-3">
      <div class="h-12 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      <div class="h-64 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
    </div>

    <!-- Edit form card -->
    <div v-else class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
      <div class="space-y-5">
        <!-- Title field -->
        <div>
          <label class="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Title</label>
          <input
            v-model="title"
            type="text"
            placeholder="Entry title"
            class="min-h-[44px] w-full rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.9)] px-4 py-3 text-[#2b1e10] placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
          />
        </div>

        <!-- Content field -->
        <div>
          <label class="mb-1.5 block text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Content</label>
          <textarea
            v-model="content"
            rows="14"
            placeholder="Your thoughts..."
            class="w-full resize-y rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.9)] px-4 py-3 text-[#2b1e10] leading-relaxed placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
          />
        </div>

        <!-- Error -->
        <p v-if="error" class="rounded-xl border border-[rgba(220,50,50,0.15)] bg-[rgba(220,50,50,0.06)] px-4 py-2.5 text-sm text-red-700">{{ error }}</p>

        <!-- Success -->
        <p v-if="saveSuccess" class="rounded-xl border border-[rgba(90,160,90,0.15)] bg-[rgba(90,160,90,0.08)] px-4 py-2.5 text-sm text-green-700">Saved successfully.</p>

        <!-- Actions -->
        <div class="flex flex-col gap-3 sm:flex-row">
          <button
            @click="save"
            :disabled="saving"
            class="flex min-h-[44px] items-center justify-center rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_2px_12px_rgba(139,90,43,0.3)] transition duration-200 hover:-translate-y-0.5 disabled:opacity-60"
          >
            {{ saving ? 'Saving...' : 'Save Changes' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Footer wisdom -->
    <p v-if="!loading" class="mt-8 text-center text-xs italic leading-relaxed text-[#b5996f]">
      "As a lamp in a windless place does not flicker" -- Bhagavad Gita 6.19
    </p>
  </div>
</template>
