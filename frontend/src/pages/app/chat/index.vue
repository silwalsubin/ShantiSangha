<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

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
  <div class="mx-auto w-full max-w-2xl px-4 py-5 sm:px-6">

    <!-- Header -->
    <div class="mb-5 flex items-center justify-between gap-3">
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <SacredIcons name="dialogue" :size="20" class="shrink-0 text-[#c4873b]" />
          <h1 class="font-serif text-xl font-bold tracking-wide text-[#2b1e10] sm:text-2xl">Conversations</h1>
        </div>
        <p class="mt-1 text-[13px] leading-relaxed text-[#6b5740]">Reflect, process, and feel supported.</p>
      </div>
      <button
        @click="newConversation"
        :disabled="creating"
        class="min-h-[44px] shrink-0 rounded-2xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2.5 text-[13px] font-semibold text-white shadow-[0_4px_16px_rgba(139,90,27,0.2)] transition duration-200 hover:-translate-y-0.5 hover:shadow-[0_6px_24px_rgba(139,90,27,0.3)] disabled:opacity-60 sm:px-5"
      >
        {{ creating ? 'Creating...' : '+ New' }}
      </button>
    </div>

    <!-- Section label -->
    <p class="mb-3 text-[9px] uppercase tracking-[0.2em] text-[#a38d6d]">Your dialogues</p>

    <!-- Error -->
    <p v-if="error" class="mb-4 rounded-2xl border border-[rgba(220,50,50,0.12)] bg-[rgba(220,50,50,0.06)] px-4 py-3 text-[13px] text-red-700">{{ error }}</p>

    <!-- Loading skeletons -->
    <div v-if="loading" class="space-y-3">
      <div v-for="i in 5" :key="i" class="h-[72px] animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
    </div>

    <!-- Empty state -->
    <div v-else-if="conversations.length === 0" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-5 py-10 text-center backdrop-blur-[20px]">
      <SacredIcons name="dialogue" :size="32" class="mx-auto mb-3 text-[#b5996f]" />
      <p class="font-serif text-lg font-bold text-[#2b1e10]">No conversations yet</p>
      <p class="mt-2 text-[13px] text-[#6b5740]">Start a new one to begin a supportive dialogue.</p>
    </div>

    <!-- Conversation list -->
    <ul v-else class="space-y-2.5">
      <li v-for="conv in conversations" :key="conv.id">
        <RouterLink
          :to="`/app/chat/${conv.id}`"
          class="group flex min-h-[56px] items-start justify-between rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-4 py-3.5 shadow-[0_2px_12px_rgba(82,54,29,0.05)] backdrop-blur-[20px] transition duration-200 hover:border-[rgba(139,90,43,0.25)] hover:shadow-[0_4px_20px_rgba(82,54,29,0.1)] active:scale-[0.99] sm:px-5 sm:py-4"
        >
          <div class="min-w-0 flex-1">
            <p class="text-[15px] font-medium text-[#2b1e10]">{{ conv.title || 'Conversation' }}</p>
            <p v-if="conv.last_message || conv.lastMessage" class="mt-0.5 truncate text-[13px] text-[#6b5740]">
              {{ conv.last_message || conv.lastMessage }}
            </p>
            <p class="mt-1 text-[11px] text-[#9a8568]">{{ conv.created_at ? formatDate(conv.created_at) : '' }}</p>
          </div>
          <button
            @click="(e) => deleteConversation(conv.id, e)"
            class="ml-2 mt-0.5 flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-xl text-[#b5996f] opacity-0 transition duration-200 hover:bg-[rgba(220,50,50,0.08)] hover:text-red-600 group-hover:opacity-100"
            title="Delete"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-[18px] w-[18px]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </button>
        </RouterLink>
      </li>
    </ul>

  </div>
</template>
