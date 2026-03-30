<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()
const router = useRouter()

interface GoalSummary {
  id: string
  title: string
  currentStreak: number
  checkedInToday: boolean
}
const goals = ref<GoalSummary[]>([])
const goalsLoading = ref(true)

async function loadGoals() {
  goalsLoading.value = true
  try {
    const data = await api.get<any>('/goals/today')
    const items = Array.isArray(data) ? data : (data?.goals || data?.items || [])
    goals.value = items.map((g: any) => ({
      id: g.id,
      title: g.title,
      currentStreak: g.currentStreak ?? g.current_streak ?? 0,
      checkedInToday: g.checkedInToday ?? g.checked_in_today ?? (g.checkIn != null),
    }))
  } catch {
    goals.value = []
  } finally {
    goalsLoading.value = false
  }
}

onMounted(() => { loadGoals() })
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-6 sm:py-10">
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-6 sm:p-8 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px]">
      <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-[#a38d6d]">Your Dharma</p>
      <p class="mt-3 font-serif text-xl sm:text-2xl font-bold tracking-wide text-[#2b1e10]">What needs your attention?</p>

      <!-- Loading -->
      <div v-if="goalsLoading" class="mt-6 space-y-3">
        <div v-for="i in 2" :key="i" class="h-14 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <!-- No tasks -->
      <div v-else-if="goals.length === 0" class="mt-6 text-center">
        <p class="text-sm text-[#6b5740]">You haven't set any tasks yet.</p>
        <button
          @click="router.push('/app/home')"
          class="mt-4 min-h-[44px] rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-3 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 active:scale-[0.97]"
        >
          Set your first task
        </button>
      </div>

      <!-- Task list -->
      <ul v-else class="mt-6 space-y-2">
        <li
          v-for="goal in goals"
          :key="goal.id"
          class="flex items-center justify-between rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] px-4 py-3 cursor-pointer transition duration-200 active:scale-[0.99]"
          @click="router.push(`/app/journey/goals/${goal.id}`)"
        >
          <div class="flex items-center gap-2 min-w-0">
            <SacredIcons v-if="goal.checkedInToday" name="check" :size="16" class="shrink-0 text-[#7aa87a]" />
            <SacredIcons v-else name="flame" :size="16" class="shrink-0 text-[#b5996f]" />
            <p class="truncate text-sm font-medium text-[#2b1e10]">{{ goal.title }}</p>
          </div>
          <div class="flex items-center gap-1 shrink-0 ml-3">
            <SacredIcons name="flame" :size="14" class="text-[#c4873b]" />
            <span class="font-serif font-bold text-[#c4873b] text-sm">{{ goal.currentStreak }}</span>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
