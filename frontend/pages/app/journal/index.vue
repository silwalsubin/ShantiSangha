<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'app' })

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
  <div class="mx-auto max-w-2xl space-y-5">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="font-serif text-2xl text-[#2b221a]">Journal</h1>
        <p class="mt-1 text-sm text-[#6c5c4d]">Your private space for reflection.</p>
      </div>
      <NuxtLink
        to="/app/journal/new"
        class="rounded-full bg-[#2b221a] px-5 py-2.5 text-sm font-semibold text-[#fff8f1] shadow transition hover:-translate-y-0.5"
      >
        + New Entry
      </NuxtLink>
    </div>

    <p v-if="error" class="rounded-2xl bg-[rgba(220,50,50,0.08)] px-4 py-3 text-sm text-red-700">{{ error }}</p>

    <div v-if="loading" class="space-y-3">
      <div v-for="i in 4" :key="i" class="h-20 animate-pulse rounded-3xl bg-[rgba(138,91,63,0.08)]" />
    </div>

    <div v-else-if="journals.length === 0" class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.82)] px-6 py-12 text-center backdrop-blur-[14px]">
      <p class="font-serif text-xl text-[#2b221a]">No entries yet</p>
      <p class="mt-2 text-sm text-[#6c5c4d]">Start writing to capture your thoughts and feelings.</p>
      <NuxtLink to="/app/journal/new" class="mt-4 inline-block rounded-full bg-[#8a5b3f] px-5 py-2 text-sm font-semibold text-white transition hover:-translate-y-0.5">
        Write your first entry
      </NuxtLink>
    </div>

    <ul v-else class="space-y-3">
      <li v-for="entry in journals" :key="entry.id">
        <NuxtLink
          :to="`/app/journal/${entry.id}`"
          class="block rounded-3xl border border-[rgba(101,76,52,0.12)] bg-[rgba(255,250,243,0.82)] px-5 py-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[14px] transition hover:border-[rgba(138,91,63,0.28)] hover:shadow-[0_8px_32px_rgba(82,54,29,0.1)]"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0 flex-1">
              <p class="font-medium text-[#2b221a]">{{ entry.title || 'Untitled' }}</p>
              <p class="mt-1 line-clamp-2 text-sm leading-relaxed text-[#6c5c4d]">{{ preview(entry.content) }}</p>
            </div>
            <span class="shrink-0 text-xs text-[#b89c87]">{{ entry.created_at ? formatDate(entry.created_at) : '' }}</span>
          </div>
        </NuxtLink>
      </li>
    </ul>
  </div>
</template>
