<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

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
    conversation: 'Conversation',
    journal: 'Journal',
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
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Back link -->
    <router-link
      to="/app/journey"
      class="inline-flex min-h-[44px] items-center gap-1.5 text-sm font-medium text-[#c4873b] transition duration-200 hover:text-[#8b5a1b]"
    >
      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back to Journey
    </router-link>

    <!-- Header -->
    <div class="flex items-center gap-3">
      <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
        <SacredIcons name="diya" :size="20" />
      </div>
      <div>
        <h1 class="font-serif text-2xl font-bold tracking-wide text-[#2b1e10] sm:text-3xl">Insights</h1>
        <p class="mt-0.5 text-sm text-[#6b5740]">Saved reflections and meaningful takeaways</p>
      </div>
    </div>

    <!-- Search -->
    <div class="relative">
      <div class="pointer-events-none absolute inset-y-0 left-4 flex items-center">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-[#b5996f]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
        </svg>
      </div>
      <input
        v-model="searchQuery"
        @input="handleSearchInput"
        @keydown.enter="search"
        type="search"
        placeholder="Search insights..."
        class="min-h-[44px] w-full rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] py-3 pl-10 pr-4 text-sm text-[#2b1e10] placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]"
      />
    </div>

    <p v-if="error" class="rounded-2xl bg-[rgba(220,50,50,0.08)] px-4 py-3 text-sm text-red-700">{{ error }}</p>

    <!-- Loading skeleton -->
    <div v-if="loading && insights.length === 0" class="space-y-3">
      <div v-for="i in 5" :key="i" class="h-24 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
    </div>

    <!-- Empty state -->
    <div v-else-if="insights.length === 0 && !loading" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-6 py-12 text-center backdrop-blur-[20px]">
      <p class="font-serif text-xl text-[#2b1e10]">{{ searchQuery ? 'No results found' : 'No insights yet' }}</p>
      <p class="mt-2 text-sm text-[#6b5740]">{{ searchQuery ? 'Try a different search term.' : 'Insights are saved during conversations and journal sessions.' }}</p>
    </div>

    <!-- Insights list -->
    <ul v-else class="space-y-3">
      <li v-for="insight in insights" :key="insight.id">
        <div class="group rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-4 py-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:px-5">
          <p class="text-sm leading-relaxed text-[#2b1e10]">{{ insight.content }}</p>
          <div class="mt-2 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-[10px] uppercase tracking-[0.15em] text-[#a38d6d]">{{ sourceLabel(insight.source) }}</span>
              <span class="text-xs text-[rgba(139,90,43,0.25)]">|</span>
              <span class="text-xs text-[#b5996f]">{{ insight.created_at ? formatDate(insight.created_at) : '' }}</span>
            </div>
            <button
              @click="deleteInsight(insight.id)"
              class="min-h-[44px] min-w-[44px] rounded-full p-2 text-[#b5996f] opacity-0 transition duration-200 hover:bg-[rgba(220,50,50,0.1)] hover:text-red-500 group-hover:opacity-100"
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

    <!-- Load more -->
    <div v-if="hasMore && !loading" class="text-center">
      <button
        @click="loadMore"
        class="min-h-[44px] rounded-full border border-[rgba(139,90,43,0.15)] px-6 py-2.5 text-sm font-medium text-[#6b5740] transition duration-200 hover:bg-[rgba(196,135,59,0.06)]"
      >
        Load more
      </button>
    </div>

    <!-- Loading indicator for pagination -->
    <div v-if="loading && insights.length > 0" class="py-4 text-center">
      <div class="inline-flex gap-1">
        <span class="h-2 w-2 animate-bounce rounded-full bg-[#c4873b]" style="animation-delay:0ms" />
        <span class="h-2 w-2 animate-bounce rounded-full bg-[#c4873b]" style="animation-delay:150ms" />
        <span class="h-2 w-2 animate-bounce rounded-full bg-[#c4873b]" style="animation-delay:300ms" />
      </div>
    </div>
  </div>
</template>
