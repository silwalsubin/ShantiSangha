<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'

const api = useApi()
const router = useRouter()
const route = useRoute()

const insights = ref<any[]>([])
const loading = ref(true)
const error = ref('')
const searchQuery = ref((route.query.q as string) || '')
const searching = ref(false)
const page = ref(1)
const hasMore = ref(true)

async function load(reset = false) {
  if (reset) {
    page.value = 1
    insights.value = []
    hasMore.value = true
  }
  if (!hasMore.value) return
  loading.value = true
  error.value = ''
  try {
    const q = searchQuery.value.trim()
    let data: any
    if (q) {
      data = await api.get<any>(`/search?q=${encodeURIComponent(q)}&page=${page.value}`)
    } else {
      data = await api.get<any>(`/insights?page=${page.value}`)
    }
    const items = Array.isArray(data) ? data : (data?.insights || data?.items || data?.results || [])
    if (reset) {
      insights.value = items
    } else {
      insights.value.push(...items)
    }
    hasMore.value = items.length > 0 && items.length >= 20
  } catch {
    error.value = 'Could not load insights.'
  } finally {
    loading.value = false
    searching.value = false
  }
}

async function search() {
  searching.value = true
  router.replace({ query: searchQuery.value ? { q: searchQuery.value } : {} })
  await load(true)
}

async function deleteInsight(id: string) {
  if (!confirm('Delete this insight?')) return
  try {
    await api.delete(`/insights/${id}`)
    insights.value = insights.value.filter(i => i.id !== id)
  } catch {
    error.value = 'Could not delete insight.'
  }
}

async function loadMore() {
  page.value++
  await load()
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function sourceLabel(s: string) {
  const map: Record<string, string> = {
    conversation: '💬 Conversation',
    journal: '📔 Journal',
  }
  return map[s] || s || 'Unknown'
}

let debounceTimer: ReturnType<typeof setTimeout>
function handleSearchInput() {
  clearTimeout(debounceTimer)
  debounceTimer = setTimeout(search, 400)
}

onMounted(() => load(true))
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5">
    <div>
      <h1 class="font-serif text-2xl text-[#2b221a]">Insights</h1>
      <p class="mt-1 text-sm text-[#6c5c4d]">Saved reflections and meaningful takeaways.</p>
    </div>

    <!-- Search -->
    <div class="relative">
      <div class="pointer-events-none absolute inset-y-0 left-4 flex items-center">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-[#b89c87]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
        </svg>
      </div>
      <input
        v-model="searchQuery"
        @input="handleSearchInput"
        @keydown.enter="search"
        type="search"
        placeholder="Search insights…"
        class="w-full rounded-2xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.9)] py-3 pl-10 pr-4 text-sm text-[#2b221a] placeholder-[#b89c87] outline-none transition focus:border-[#c99262] focus:ring-1 focus:ring-[#c99262]"
      />
    </div>

    <p v-if="error" class="rounded-2xl bg-[rgba(220,50,50,0.08)] px-4 py-3 text-sm text-red-700">{{ error }}</p>

    <div v-if="loading && insights.length === 0" class="space-y-3">
      <div v-for="i in 5" :key="i" class="h-24 animate-pulse rounded-3xl bg-[rgba(138,91,63,0.08)]" />
    </div>

    <div v-else-if="insights.length === 0 && !loading" class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.82)] px-6 py-12 text-center backdrop-blur-[14px]">
      <p class="font-serif text-xl text-[#2b221a]">{{ searchQuery ? 'No results found' : 'No insights yet' }}</p>
      <p class="mt-2 text-sm text-[#6c5c4d]">{{ searchQuery ? 'Try a different search term.' : 'Insights are saved during conversations and journal sessions.' }}</p>
    </div>

    <ul v-else class="space-y-3">
      <li v-for="insight in insights" :key="insight.id">
        <div class="group rounded-3xl border border-[rgba(101,76,52,0.12)] bg-[rgba(255,250,243,0.82)] px-5 py-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[14px]">
          <p class="text-sm leading-relaxed text-[#2b221a]">{{ insight.content }}</p>
          <div class="mt-2 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-xs text-[#b89c87]">{{ sourceLabel(insight.source) }}</span>
              <span class="text-xs text-[#d5c4b3]">·</span>
              <span class="text-xs text-[#b89c87]">{{ insight.created_at ? formatDate(insight.created_at) : '' }}</span>
            </div>
            <button
              @click="deleteInsight(insight.id)"
              class="rounded-full p-1.5 text-[#b89c87] opacity-0 transition hover:bg-[rgba(220,50,50,0.1)] hover:text-red-500 group-hover:opacity-100"
              title="Delete"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
          </div>
        </div>
      </li>
    </ul>

    <div v-if="hasMore && !loading" class="text-center">
      <button
        @click="loadMore"
        class="rounded-full border border-[rgba(101,76,52,0.16)] px-6 py-2.5 text-sm font-medium text-[#6c5c4d] transition hover:bg-[rgba(138,91,63,0.06)]"
      >
        Load more
      </button>
    </div>

    <div v-if="loading && insights.length > 0" class="py-4 text-center">
      <div class="inline-flex gap-1">
        <span class="h-2 w-2 animate-bounce rounded-full bg-[#c99262]" style="animation-delay:0ms" />
        <span class="h-2 w-2 animate-bounce rounded-full bg-[#c99262]" style="animation-delay:150ms" />
        <span class="h-2 w-2 animate-bounce rounded-full bg-[#c99262]" style="animation-delay:300ms" />
      </div>
    </div>
  </div>
</template>
