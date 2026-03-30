<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const route = useRoute()
const router = useRouter()
const api = useApi()

const goalId = computed(() => route.params.id as string)

interface Goal {
  id: string
  title: string
  type: 'Recurring' | 'OneTime'
  deeperWhy: string | null
  currentStreak?: number
  longestStreak?: number
  frequency?: string
  frequencyTarget?: number
  targetDate?: string | null
  completedAt?: string | null
  daysRemaining?: number | null
  noteCount?: number
  createdAt: string
}

interface CheckIn {
  id: string
  date: string
  completed: boolean
  note: string | null
  createdAt: string
}

const goal = ref<Goal | null>(null)
const history = ref<CheckIn[]>([])
const loading = ref(true)
const historyLoading = ref(true)

const editingWhy = ref(false)
const whyInput = ref('')
const savingWhy = ref(false)

async function loadGoal() {
  loading.value = true
  try {
    const data = await api.get<any>(`/goals/${goalId.value}`)
    goal.value = {
      id: data.id,
      title: data.title,
      type: data.type ?? 'Recurring',
      deeperWhy: data.deeperWhy ?? data.deeper_why ?? null,
      currentStreak: data.currentStreak ?? data.current_streak ?? 0,
      longestStreak: data.longestStreak ?? data.longest_streak ?? 0,
      frequency: data.frequency ?? null,
      frequencyTarget: data.frequencyTarget ?? data.frequency_target ?? null,
      targetDate: data.targetDate ?? data.target_date ?? null,
      completedAt: data.completedAt ?? data.completed_at ?? null,
      daysRemaining: data.daysRemaining ?? data.days_remaining ?? null,
      noteCount: data.noteCount ?? data.note_count ?? 0,
      createdAt: data.createdAt ?? data.created_at ?? '',
    }
    whyInput.value = goal.value.deeperWhy ?? ''
  } catch {
    goal.value = null
  } finally {
    loading.value = false
  }
}

async function loadHistory() {
  historyLoading.value = true
  try {
    const data = await api.get<any>(`/goals/${goalId.value}/history`)
    const items = Array.isArray(data) ? data : (data?.items || data?.checkins || data?.checkIns || [])
    history.value = items.map((c: any) => ({
      id: c.id,
      date: c.date,
      completed: c.completed ?? false,
      note: c.note ?? null,
      createdAt: c.createdAt ?? c.created_at ?? '',
    }))
  } catch {
    history.value = []
  } finally {
    historyLoading.value = false
  }
}

async function saveDeeperWhy() {
  if (!goal.value) return
  savingWhy.value = true
  try {
    await api.patch(`/goals/${goal.value.id}`, { deeperWhy: whyInput.value })
    goal.value.deeperWhy = whyInput.value || null
    editingWhy.value = false
  } catch {
    // keep editing
  } finally {
    savingWhy.value = false
  }
}

function startEditWhy() {
  whyInput.value = goal.value?.deeperWhy ?? ''
  editingWhy.value = true
}

function formatDate(dateStr: string): string {
  if (!dateStr) return ''
  const d = new Date(dateStr.includes('T') ? dateStr : dateStr + 'T12:00:00')
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function daysSinceCreated(): number {
  if (!goal.value) return 0
  const created = new Date(goal.value.createdAt)
  const now = new Date()
  return Math.floor((now.getTime() - created.getTime()) / 86400000)
}

onMounted(() => {
  loadGoal()
  loadHistory()
})
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Back button -->
    <button
      class="flex min-h-[44px] items-center gap-1.5 text-sm font-medium text-[#c4873b] transition duration-200 hover:text-[#8b5a1b]"
      @click="router.push('/app/journey')"
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M12 19l-7-7 7-7"/></svg>
      Journey
    </button>

    <!-- Loading -->
    <div v-if="loading" class="space-y-4">
      <div class="h-8 w-3/4 animate-pulse rounded-xl bg-[rgba(139,90,43,0.08)]" />
      <div class="h-32 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
    </div>

    <!-- Not found -->
    <div v-else-if="!goal" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 text-center">
      <p class="text-sm text-[#6b5740]">Task not found.</p>
    </div>

    <template v-else>
      <!-- Header card -->
      <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
        <div class="flex items-start gap-2">
          <SacredIcons :name="goal.type === 'Recurring' ? 'flame' : 'target'" :size="18" class="mt-0.5 text-[#c4873b]" />
          <div class="flex-1">
            <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">
              {{ goal.type === 'Recurring' ? 'Daily Practice' : 'Milestone' }}
            </p>
            <h1 class="mt-1 font-serif text-xl font-bold text-[#2b1e10]">{{ goal.title }}</h1>
          </div>
        </div>

        <!-- Stats -->
        <div class="mt-5 flex gap-3">
          <template v-if="goal.type === 'Recurring'">
            <div class="flex-1 rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-3 text-center">
              <p class="text-2xl font-bold text-[#c4873b]">{{ goal.currentStreak }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Current Streak</p>
            </div>
            <div class="flex-1 rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-3 text-center">
              <p class="text-2xl font-bold text-[#c4873b]">{{ goal.longestStreak }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Longest Streak</p>
            </div>
            <div class="flex-1 rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-3 text-center">
              <p class="text-2xl font-bold text-[#c4873b]">{{ daysSinceCreated() }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Days Active</p>
            </div>
          </template>
          <template v-else>
            <div class="flex-1 rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-3 text-center">
              <p class="text-2xl font-bold text-[#c4873b]">
                {{ goal.completedAt ? 'Done' : goal.daysRemaining != null ? goal.daysRemaining : '--' }}
              </p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">
                {{ goal.completedAt ? 'Completed' : 'Days Left' }}
              </p>
            </div>
            <div class="flex-1 rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-3 text-center">
              <p class="text-2xl font-bold text-[#c4873b]">{{ goal.noteCount ?? 0 }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Progress Notes</p>
            </div>
            <div v-if="goal.targetDate" class="flex-1 rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-3 py-3 text-center">
              <p class="font-serif text-sm font-bold text-[#c4873b]">{{ formatDate(goal.targetDate) }}</p>
              <p class="mt-0.5 text-[9px] uppercase tracking-[0.2em] text-[#9a8568]">Target Date</p>
            </div>
          </template>
        </div>

        <!-- Created date -->
        <p class="mt-4 text-[10px] uppercase tracking-[0.15em] text-[#a38d6d]">
          Started {{ formatDate(goal.createdAt) }}
        </p>
      </div>

      <!-- Deeper Why -->
      <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <SacredIcons name="lotus" :size="14" class="text-[#c4873b]" />
            <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">The Deeper Why</p>
          </div>
          <button
            v-if="!editingWhy"
            class="min-h-[44px] text-xs font-medium text-[#c4873b] transition duration-200 hover:text-[#8b5a1b]"
            @click="startEditWhy"
          >
            {{ goal.deeperWhy ? 'Edit' : 'Add' }}
          </button>
        </div>

        <div v-if="editingWhy" class="mt-3">
          <textarea
            v-model="whyInput"
            rows="3"
            class="w-full rounded-xl border border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.6)] px-3 py-2 text-sm text-[#2b1e10] placeholder-[#b5996f] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[rgba(196,135,59,0.3)]"
            placeholder="Why does this task matter to you? What deeper intention does it serve?"
          />
          <div class="mt-2 flex gap-2 justify-end">
            <button
              class="min-h-[44px] rounded-xl px-4 text-sm font-medium text-[#6b5740] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
              @click="editingWhy = false"
            >
              Cancel
            </button>
            <button
              class="min-h-[44px] rounded-xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-4 text-sm font-medium text-white shadow-sm transition duration-200 active:scale-[0.98] disabled:opacity-50"
              :disabled="savingWhy"
              @click="saveDeeperWhy"
            >
              Save
            </button>
          </div>
        </div>

        <p v-else-if="goal.deeperWhy" class="mt-3 font-serif text-sm italic leading-relaxed text-[#2b1e10]">
          "{{ goal.deeperWhy }}"
        </p>

        <p v-else class="mt-3 text-sm text-[#9a8568]">
          What draws you to this task? Understanding the deeper intention behind your commitments can transform discipline into devotion.
        </p>
      </div>

      <!-- Check-in History -->
      <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:p-6">
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">History</p>

        <div v-if="historyLoading" class="mt-4 space-y-2">
          <div v-for="i in 3" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
        </div>

        <div v-else-if="history.length === 0" class="mt-4 text-sm text-[#6b5740]">
          No check-ins yet.
        </div>

        <ul v-else class="mt-4 space-y-2">
          <li
            v-for="checkin in history"
            :key="checkin.id"
            class="rounded-2xl border border-[rgba(139,90,43,0.08)] bg-[rgba(250,245,237,0.6)] px-4 py-3"
          >
            <div class="flex items-center gap-3">
              <div
                class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full"
                :class="checkin.completed
                  ? 'bg-gradient-to-br from-[#c4873b] to-[#8b5a1b]'
                  : 'border border-[rgba(139,90,43,0.2)] bg-[rgba(250,245,237,0.6)]'"
              >
                <SacredIcons v-if="checkin.completed" name="check" :size="12" class="text-white" />
                <SacredIcons v-else name="skip" :size="12" class="text-[#b5996f]" />
              </div>
              <div class="flex-1">
                <p class="text-xs font-medium text-[#2b1e10]">{{ formatDate(checkin.date) }}</p>
                <p v-if="checkin.note" class="mt-0.5 text-xs leading-relaxed text-[#6b5740]">{{ checkin.note }}</p>
              </div>
            </div>
          </li>
        </ul>
      </div>
    </template>
  </div>
</template>
