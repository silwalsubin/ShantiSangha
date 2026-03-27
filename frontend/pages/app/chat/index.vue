<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'app' })

const api = useApi()
const router = useRouter()

const conversations = ref<any[]>([])
const loading = ref(true)
const error = ref('')
const creating = ref(false)

async function load() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get<any>('/conversations')
    conversations.value = Array.isArray(data) ? data : (data?.conversations || data?.items || [])
  } catch {
    error.value = 'Could not load conversations.'
  } finally {
    loading.value = false
  }
}

async function newConversation() {
  creating.value = true
  try {
    const conv = await api.post<any>('/conversations', { title: 'New Conversation' })
    router.push(`/app/chat/${conv.id}`)
  } catch {
    error.value = 'Could not create conversation.'
  } finally {
    creating.value = false
  }
}

async function deleteConversation(id: string, e: Event) {
  e.preventDefault()
  if (!confirm('Delete this conversation?')) return
  try {
    await api.delete(`/conversations/${id}`)
    conversations.value = conversations.value.filter(c => c.id !== id)
  } catch {
    error.value = 'Could not delete conversation.'
  }
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

onMounted(load)
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="font-serif text-2xl text-[#2b221a]">Conversations</h1>
        <p class="mt-1 text-sm text-[#6c5c4d]">Reflect, process, and feel supported.</p>
      </div>
      <button
        @click="newConversation"
        :disabled="creating"
        class="rounded-full bg-[#2b221a] px-5 py-2.5 text-sm font-semibold text-[#fff8f1] shadow transition hover:-translate-y-0.5 disabled:opacity-60"
      >
        {{ creating ? 'Creating…' : '+ New Conversation' }}
      </button>
    </div>

    <p v-if="error" class="rounded-2xl bg-[rgba(220,50,50,0.08)] px-4 py-3 text-sm text-red-700">{{ error }}</p>

    <div v-if="loading" class="space-y-3">
      <div v-for="i in 5" :key="i" class="h-16 animate-pulse rounded-3xl bg-[rgba(138,91,63,0.08)]" />
    </div>

    <div v-else-if="conversations.length === 0" class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.82)] px-6 py-10 text-center backdrop-blur-[14px]">
      <p class="font-serif text-xl text-[#2b221a]">No conversations yet</p>
      <p class="mt-2 text-sm text-[#6c5c4d]">Start a new one to begin a supportive chat.</p>
    </div>

    <ul v-else class="space-y-3">
      <li v-for="conv in conversations" :key="conv.id">
        <NuxtLink
          :to="`/app/chat/${conv.id}`"
          class="group flex items-start justify-between rounded-3xl border border-[rgba(101,76,52,0.12)] bg-[rgba(255,250,243,0.82)] px-5 py-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[14px] transition hover:border-[rgba(138,91,63,0.28)] hover:shadow-[0_8px_32px_rgba(82,54,29,0.1)]"
        >
          <div class="min-w-0 flex-1">
            <p class="font-medium text-[#2b221a]">{{ conv.title || 'Conversation' }}</p>
            <p v-if="conv.last_message || conv.lastMessage" class="mt-0.5 truncate text-sm text-[#6c5c4d]">
              {{ conv.last_message || conv.lastMessage }}
            </p>
            <p class="mt-1 text-xs text-[#b89c87]">{{ conv.created_at ? formatDate(conv.created_at) : '' }}</p>
          </div>
          <button
            @click="(e) => deleteConversation(conv.id, e)"
            class="ml-3 mt-0.5 shrink-0 rounded-full p-1.5 text-[#b89c87] opacity-0 transition hover:bg-[rgba(220,50,50,0.1)] hover:text-red-500 group-hover:opacity-100"
            title="Delete"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </button>
        </NuxtLink>
      </li>
    </ul>
  </div>
</template>
