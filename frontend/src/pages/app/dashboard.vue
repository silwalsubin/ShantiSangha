<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUser } from '@clerk/vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const { user } = useUser()
const api = useApi()
const router = useRouter()

const now = new Date()
const hour = now.getHours()
const greeting = computed(() => {
  if (hour < 12) return 'Good morning'
  if (hour < 17) return 'Good afternoon'
  return 'Good evening'
})
const firstName = computed(() => user.value?.firstName || user.value?.username || 'friend')

// Recent conversations
const conversations = ref<any[]>([])
const convsLoading = ref(true)

// Recent journals
const journals = ref<any[]>([])
const journalsLoading = ref(true)

// Goals summary
interface GoalSummary {
  id: string
  title: string
  currentStreak: number
  checkedInToday: boolean
}
const goals = ref<GoalSummary[]>([])
const goalsLoading = ref(true)

async function loadConversations() {
  try {
    const data = await api.get<any>('/conversations?limit=3')
    conversations.value = Array.isArray(data) ? data : (data?.conversations || data?.items || [])
  } catch {
    conversations.value = []
  } finally {
    convsLoading.value = false
  }
}

async function loadJournals() {
  try {
    const data = await api.get<any>('/journals?limit=2')
    journals.value = Array.isArray(data) ? data : (data?.journals || data?.items || [])
  } catch {
    journals.value = []
  } finally {
    journalsLoading.value = false
  }
}

async function loadGoals() {
  goalsLoading.value = true
  try {
    const data = await api.get<any>('/goals/today')
    const items = Array.isArray(data) ? data : (data?.goals || data?.items || [])
    goals.value = items.map((g: any) => ({
      id: g.id,
      title: g.title,
      currentStreak: g.currentStreak ?? g.current_streak ?? 0,
      checkedInToday: g.checkedInToday ?? g.checked_in_today ?? false,
    }))
  } catch {
    goals.value = []
  } finally {
    goalsLoading.value = false
  }
}

async function newConversation() {
  try {
    const conv = await api.post<any>('/conversations', { title: 'New Conversation' })
    router.push(`/app/chat/${conv.id}`)
  } catch {
    // ignore
  }
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

onMounted(() => {
  loadConversations()
  loadJournals()
  loadGoals()
})
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-4 sm:space-y-6 p-4 sm:p-6">
    <!-- Greeting -->
    <div>
      <h1 class="font-serif text-2xl sm:text-3xl font-bold tracking-wide text-[#2b1e10]">{{ greeting }}, {{ firstName }}</h1>
      <p class="mt-1 text-sm text-[#6b5740]">How are you doing today?</p>
    </div>

    <!-- Daily Verse -->
    <div class="rounded-2xl border border-dashed border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] p-4 sm:p-5 backdrop-blur-[20px]">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Verse of the Day</p>
      <p class="mt-2 font-serif italic text-sm sm:text-base text-[#b5996f] leading-relaxed">"You have the right to work, but never to the fruit of work."</p>
      <p class="mt-1 text-[10px] uppercase tracking-[0.2em] text-[#9a8568]">-- Bhagavad Gita 2.47</p>
    </div>

    <!-- Goals Summary -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px]">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Your Intentions</p>

      <div v-if="goalsLoading" class="mt-3 space-y-2">
        <div v-for="i in 2" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else-if="goals.length === 0" class="mt-3">
        <p class="text-sm text-[#6b5740]">No intentions set yet. Visit the Sacred Scrolls to begin.</p>
      </div>

      <ul v-else class="mt-3 space-y-2">
        <li
          v-for="goal in goals"
          :key="goal.id"
          class="flex items-center justify-between rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3"
        >
          <div class="flex items-center gap-2 min-w-0">
            <SacredIcons v-if="goal.checkedInToday" name="check" :size="16" class="shrink-0 text-[#7aa87a]" />
            <SacredIcons v-else name="target" :size="16" class="shrink-0 text-[#b5996f]" />
            <p class="truncate text-sm font-medium text-[#2b1e10]">{{ goal.title }}</p>
          </div>
          <div class="flex items-center gap-1 shrink-0 ml-3">
            <SacredIcons name="flame" :size="14" class="text-[#c4873b]" />
            <span class="font-serif font-bold text-[#c4873b] text-sm">{{ goal.currentStreak }}</span>
          </div>
        </li>
      </ul>

      <RouterLink
        to="/app/home"
        class="mt-3 block text-center text-xs text-[#c4873b] min-h-[44px] flex items-center justify-center hover:underline"
      >
        Open Sacred Scrolls
      </RouterLink>
    </div>

    <!-- Recent Conversations -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px]">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <SacredIcons name="dialogue" :size="16" class="text-[#a38d6d]" />
          <p class="text-[10px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Recent Conversations</p>
        </div>
        <button @click="newConversation" class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2 text-xs font-semibold text-[#fff8f1] shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5">
          + New
        </button>
      </div>
      <div v-if="convsLoading" class="mt-4 space-y-2">
        <div v-for="i in 3" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(196,135,59,0.08)]" />
      </div>
      <div v-else-if="conversations.length === 0" class="mt-4 text-sm text-[#6b5740]">No conversations yet.</div>
      <ul v-else class="mt-4 space-y-2">
        <li v-for="conv in conversations" :key="conv.id">
          <RouterLink
            :to="`/app/chat/${conv.id}`"
            class="flex items-center justify-between rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] min-h-[44px] px-4 py-3 transition duration-200 hover:bg-[rgba(245,235,224,1)]"
          >
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-[#2b1e10]">{{ conv.title || 'Conversation' }}</p>
              <p class="mt-0.5 truncate text-xs text-[#6b5740]">{{ conv.last_message || conv.lastMessage || '' }}</p>
            </div>
            <span class="ml-3 shrink-0 text-xs text-[#9a8568]">{{ conv.created_at ? formatDate(conv.created_at) : '' }}</span>
          </RouterLink>
        </li>
      </ul>
      <RouterLink to="/app/chat" class="mt-3 block text-center text-xs text-[#c4873b] min-h-[44px] flex items-center justify-center hover:underline">View all</RouterLink>
    </div>

    <!-- Recent Journals -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 sm:p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px]">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <SacredIcons name="scroll" :size="16" class="text-[#a38d6d]" />
          <p class="text-[10px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Journal</p>
        </div>
        <RouterLink to="/app/journal/new" class="min-h-[44px] min-w-[44px] flex items-center justify-center rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 py-2 text-xs font-semibold text-[#fff8f1] shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5">
          + New Entry
        </RouterLink>
      </div>
      <div v-if="journalsLoading" class="mt-4 space-y-2">
        <div v-for="i in 2" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(196,135,59,0.08)]" />
      </div>
      <div v-else-if="journals.length === 0" class="mt-4 text-sm text-[#6b5740]">No journal entries yet.</div>
      <ul v-else class="mt-4 space-y-2">
        <li v-for="entry in journals" :key="entry.id">
          <RouterLink
            :to="`/app/journal/${entry.id}`"
            class="flex items-center justify-between rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] min-h-[44px] px-4 py-3 transition duration-200 hover:bg-[rgba(245,235,224,1)]"
          >
            <div class="min-w-0">
              <p class="truncate text-sm font-medium text-[#2b1e10]">{{ entry.title || 'Untitled' }}</p>
              <p class="mt-0.5 truncate text-xs text-[#6b5740]">{{ (entry.content || '').slice(0, 60) }}</p>
            </div>
            <span class="ml-3 shrink-0 text-xs text-[#9a8568]">{{ entry.created_at ? formatDate(entry.created_at) : '' }}</span>
          </RouterLink>
        </li>
      </ul>
      <RouterLink to="/app/journal" class="mt-3 block text-center text-xs text-[#c4873b] min-h-[44px] flex items-center justify-center hover:underline">View all</RouterLink>
    </div>
  </div>
</template>
