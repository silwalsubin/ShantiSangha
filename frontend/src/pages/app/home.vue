<script setup lang="ts">
/**
 * Home page — "What needs your attention today?"
 *
 * Shows all active tasks grouped by type (Recurring Tasks, Milestones).
 * Completed and skipped tasks collapse into expandable summaries.
 * Inline form for creating new tasks.
 *
 * Uses: useGoals composable for all data and actions.
 */

import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useGoals } from '@/composables/useGoals'
import SacredIcons from '@/components/icons/SacredIcons.vue'
import TaskItem from '@/components/TaskItem.vue'

const router = useRouter()
const {
  loading, hasTasks,
  recurringTasks, milestoneTasks, completedTasks, skippedTasks,
  load, checkIn, undoCheckIn, updateProgress, deleteGoal, createGoal,
} = useGoals()

// Collapsed groups
const showCompleted = ref(false)
const showSkipped = ref(false)

// New task form
const showNewGoalForm = ref(false)
const newGoalTitle = ref('')
const newGoalType = ref<'Recurring' | 'OneTime'>('Recurring')
const newGoalTargetDate = ref('')
const newGoalSaving = ref(false)

async function onCreateGoal() {
  if (!newGoalTitle.value.trim()) return
  if (newGoalType.value === 'OneTime' && !newGoalTargetDate.value) return
  newGoalSaving.value = true
  try {
    await createGoal(newGoalTitle.value.trim(), newGoalType.value, newGoalTargetDate.value || undefined)
    newGoalTitle.value = ''
    newGoalType.value = 'Recurring'
    newGoalTargetDate.value = ''
    showNewGoalForm.value = false
  } catch {} finally {
    newGoalSaving.value = false
  }
}

function onNavigate(id: string) {
  router.push(`/app/journey/goals/${id}`)
}

onMounted(() => load())
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-6 sm:py-10">
    <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-sacred-label">Your Dharma</p>
    <p class="mt-3 text-xl sm:text-2xl font-semibold text-sacred-text">What needs your attention today?</p>

    <!-- Loading -->
    <div v-if="loading" class="mt-6 space-y-3">
      <div v-for="i in 2" :key="i" class="h-14 animate-pulse rounded-2xl bg-sacred-bg-pulse" />
    </div>

    <!-- No tasks -->
    <div v-else-if="!hasTasks && !showNewGoalForm" class="mt-6 text-center">
      <p class="text-sm text-sacred-text-secondary">You haven't set any tasks yet.</p>
      <button
        @click="showNewGoalForm = true"
        class="mt-4 min-h-[44px] rounded-full bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-3 text-sm font-semibold text-white shadow-sacred-button transition duration-200 active:scale-[0.97]"
      >
        Set your first task
      </button>
    </div>

    <!-- New task form -->
    <div v-if="showNewGoalForm" class="mt-6">
      <div class="mb-3 flex justify-center gap-2">
        <button @click="newGoalType = 'Recurring'" class="flex min-h-[44px] items-center gap-1.5 rounded-2xl border px-4 py-2.5 text-xs font-semibold transition duration-200 active:scale-[0.97]" :class="newGoalType === 'Recurring' ? 'border-sacred-gold text-sacred-gold bg-sacred-gold-light' : 'border-sacred-border text-sacred-text-secondary'">
          <SacredIcons name="flame" :size="14" /> Daily practice
        </button>
        <button @click="newGoalType = 'OneTime'" class="flex min-h-[44px] items-center gap-1.5 rounded-2xl border px-4 py-2.5 text-xs font-semibold transition duration-200 active:scale-[0.97]" :class="newGoalType === 'OneTime' ? 'border-sacred-gold text-sacred-gold bg-sacred-gold-light' : 'border-sacred-border text-sacred-text-secondary'">
          <SacredIcons name="target" :size="14" /> Reach a milestone
        </button>
      </div>
      <input v-model="newGoalTitle" type="text" :placeholder="newGoalType === 'Recurring' ? 'I want to practice...' : 'I want to achieve...'" class="w-full rounded-2xl border border-sacred-border bg-sacred-bg-warm px-4 py-3 text-sm text-sacred-text placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold" @keyup.enter="newGoalType === 'Recurring' ? onCreateGoal() : undefined" />
      <input v-if="newGoalType === 'OneTime'" v-model="newGoalTargetDate" type="date" class="mt-2 w-full rounded-2xl border border-sacred-border bg-sacred-bg-warm px-4 py-3 text-sm text-sacred-text outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold" />
      <div class="mt-3 flex justify-center gap-2">
        <button @click="onCreateGoal" :disabled="newGoalSaving || !newGoalTitle.trim() || (newGoalType === 'OneTime' && !newGoalTargetDate)" class="min-h-[44px] rounded-full bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-2.5 text-sm font-semibold text-white shadow-sacred-button transition duration-200 active:scale-[0.97] disabled:opacity-60">
          {{ newGoalSaving ? 'Saving...' : 'Save' }}
        </button>
        <button @click="showNewGoalForm = false; newGoalType = 'Recurring'; newGoalTargetDate = ''" class="min-h-[44px] rounded-full border border-sacred-border-strong px-5 py-2.5 text-sm font-medium text-sacred-text-secondary transition duration-200 active:scale-[0.97]">
          Cancel
        </button>
      </div>
    </div>

    <!-- Recurring Tasks -->
    <div v-if="recurringTasks.length > 0" class="mt-6">
      <div class="flex items-center gap-1.5 mb-3">
        <SacredIcons name="recurring" :size="14" class="text-sacred-label" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Recurring Tasks</p>
      </div>
      <ul class="space-y-3">
        <TaskItem
          v-for="task in recurringTasks" :key="task.id" :task="task"
          @done="checkIn($event, true)" @skip="checkIn($event, false)"
          @undo="undoCheckIn" @navigate="onNavigate"
          @progress="updateProgress" @delete="deleteGoal"
        />
      </ul>
    </div>

    <!-- Milestones -->
    <div v-if="milestoneTasks.length > 0" class="mt-6">
      <div class="flex items-center gap-1.5 mb-3">
        <SacredIcons name="target" :size="14" class="text-sacred-label" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Milestones</p>
      </div>
      <ul class="space-y-3">
        <TaskItem
          v-for="task in milestoneTasks" :key="task.id" :task="task"
          @done="checkIn($event, true)" @skip="checkIn($event, false)"
          @undo="undoCheckIn" @navigate="onNavigate"
          @progress="updateProgress" @delete="deleteGoal"
        />
      </ul>
    </div>

    <!-- Completed -->
    <div v-if="completedTasks.length > 0" class="mt-4">
      <button @click="showCompleted = !showCompleted" class="flex min-h-[44px] items-center gap-1.5 text-xs font-medium text-sacred-green transition duration-200 hover:text-sacred-green-dark">
        <SacredIcons name="check" :size="12" />
        {{ completedTasks.length }} completed
        <span class="text-[10px]">{{ showCompleted ? '&#9650;' : '&#9660;' }}</span>
      </button>
      <ul v-if="showCompleted" class="mt-2 space-y-3">
        <TaskItem
          v-for="task in completedTasks" :key="task.id" :task="task"
          @done="checkIn($event, true)" @skip="checkIn($event, false)"
          @undo="undoCheckIn" @navigate="onNavigate"
          @progress="updateProgress" @delete="deleteGoal"
        />
      </ul>
    </div>

    <!-- Skipped -->
    <div v-if="skippedTasks.length > 0" class="mt-2">
      <button @click="showSkipped = !showSkipped" class="flex min-h-[44px] items-center gap-1.5 text-xs font-medium text-sacred-muted transition duration-200 hover:text-sacred-text-secondary">
        <SacredIcons name="skip" :size="12" />
        {{ skippedTasks.length }} skipped
        <span class="text-[10px]">{{ showSkipped ? '&#9650;' : '&#9660;' }}</span>
      </button>
      <ul v-if="showSkipped" class="mt-2 space-y-3">
        <TaskItem
          v-for="task in skippedTasks" :key="task.id" :task="task"
          @done="checkIn($event, true)" @skip="checkIn($event, false)"
          @undo="undoCheckIn" @navigate="onNavigate"
          @progress="updateProgress" @delete="deleteGoal"
        />
      </ul>
    </div>

    <!-- Add task button -->
    <button
      v-if="hasTasks && !showNewGoalForm"
      @click="showNewGoalForm = true"
      class="mt-4 flex min-h-[44px] items-center justify-center gap-1.5 text-xs font-medium text-sacred-gold transition duration-200 hover:text-sacred-gold-dark active:scale-[0.97]"
    >
      + Add task
    </button>
  </div>
</template>
