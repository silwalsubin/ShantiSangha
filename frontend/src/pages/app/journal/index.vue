<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()

const journals = ref<any[]>([])
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get<any>('/journals')
    journals.value = Array.isArray(data) ? data : (data?.journals || data?.items || [])
  } catch {
    error.value = 'Could not load journal entries.'
  } finally {
    loading.value = false
  }
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })
}

function preview(content: string) {
  return content?.slice(0, 100) || ''
}

onMounted(load)
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 py-4 sm:px-6 sm:py-6">
    <!-- Header -->
    <div class="mb-5 flex items-center justify-between gap-3">
      <div class="flex items-center gap-2.5">
        <div class="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white shadow-[0_2px_8px_rgba(139,90,43,0.25)]">
          <SacredIcons name="scroll" :size="18" />
        </div>
        <div>
          <h1 class="font-serif text-xl font-bold tracking-wide text-[#2b1e10] sm:text-2xl">Journal</h1>
          <p class="text-[10px] uppercase tracking-[0.2em] text-[#a38d6d]">Private reflections</p>
        </div>
      </div>
      <RouterLink
        to="/app/journal/new"
        class="flex min-h-[44px] items-center rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2.5 text-sm font-semibold text-white shadow-[0_2px_12px_rgba(139,90,43,0.3)] transition duration-200 hover:-translate-y-0.5 sm:px-5"
      >
        + New Entry
      </RouterLink>
    </div>

    <!-- Error -->
    <p v-if="error" class="mb-4 rounded-2xl border border-[rgba(220,50,50,0.15)] bg-[rgba(220,50,50,0.06)] px-4 py-3 text-sm text-red-700">{{ error }}</p>

    <!-- Loading skeletons -->
    <div v-if="loading" class="space-y-3">
      <div v-for="i in 4" :key="i" class="h-20 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
    </div>

    <!-- Empty state -->
    <div v-else-if="journals.length === 0" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-5 py-12 text-center shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:px-8">
      <div class="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-[rgba(196,135,59,0.1)] text-[#c4873b]">
        <SacredIcons name="scroll" :size="28" />
      </div>
      <p class="font-serif text-lg font-bold text-[#2b1e10]">No entries yet</p>
      <p class="mx-auto mt-2 max-w-xs text-sm leading-relaxed text-[#6b5740]">Begin your practice of self-reflection. Your thoughts are safe here.</p>
      <RouterLink
        to="/app/journal/new"
        class="mt-5 inline-flex min-h-[44px] items-center rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-2.5 text-sm font-semibold text-white shadow-[0_2px_12px_rgba(139,90,43,0.3)] transition duration-200 hover:-translate-y-0.5"
      >
        Write your first entry
      </RouterLink>
    </div>

    <!-- Journal entries list -->
    <ul v-else class="space-y-3">
      <li v-for="entry in journals" :key="entry.id">
        <RouterLink
          :to="`/app/journal/${entry.id}`"
          class="block min-h-[44px] rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-4 py-4 shadow-[0_2px_16px_rgba(82,54,29,0.05)] backdrop-blur-[20px] transition duration-200 hover:border-[rgba(139,90,43,0.25)] hover:shadow-[0_4px_24px_rgba(82,54,29,0.1)] sm:px-5"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0 flex-1">
              <p class="font-serif font-medium text-[#2b1e10]">{{ entry.title || 'Untitled' }}</p>
              <p class="mt-1 line-clamp-2 text-sm leading-relaxed text-[#6b5740]">{{ preview(entry.content) }}</p>
            </div>
            <span class="shrink-0 pt-0.5 text-[11px] text-[#9a8568]">{{ entry.created_at ? formatDate(entry.created_at) : '' }}</span>
          </div>
        </RouterLink>
      </li>
    </ul>

    <!-- Footer wisdom -->
    <p v-if="!loading && journals.length > 0" class="mt-8 text-center text-xs italic leading-relaxed text-[#b5996f]">
      "The unexamined life is not worth living." -- adapted from the spirit of Atma-Vichara
    </p>
  </div>
</template>
