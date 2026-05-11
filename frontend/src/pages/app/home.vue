<script setup lang="ts">
/**
 * Home page — "What needs your attention today?"
 *
 * Shows pending practices (recurring) and reminders (date-based)
 * grouped by section. Completed and skipped items collapse into
 * expandable summaries. Inline form for creating new items.
 */

import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { usePractices } from '@/composables/usePractices'
import { useReminders } from '@/composables/useReminders'
import { useLocalDate } from '@/composables/useLocalDate'
import SacredIcons from '@/components/icons/SacredIcons.vue'
import TaskItem from '@/components/TaskItem.vue'
import ReminderItem from '@/components/ReminderItem.vue'

const router = useRouter()
const { today } = useLocalDate()

const {
  loading: practicesLoading,
  hasPractices,
  pendingPractices, completedPractices, skippedPractices,
  loadPractices, checkIn, undoCheckIn, deletePractice, createPractice,
} = usePractices()

const {
  loading: remindersLoading,
  activeReminders, completedReminders,
  loadReminders, createReminder, completeReminder, deleteReminder,
} = useReminders()

const loading = computed(() => practicesLoading.value || remindersLoading.value)
const hasAnything = computed(() => hasPractices.value || activeReminders.value.length > 0 || completedReminders.value.length > 0)

// Collapsed groups
const showCompleted = ref(false)
const showSkipped = ref(false)

// New item form
const showNewForm = ref(false)
const newKind = ref<'practice' | 'reminder'>('practice')
const newTitle = ref('')
const newDate = ref('')
const newSaving = ref(false)

async function onCreate() {
  const title = newTitle.value.trim()
  if (!title) return
  if (newKind.value === 'reminder' && !newDate.value) return
  newSaving.value = true
  try {
    if (newKind.value === 'practice') {
      await createPractice(title)
    } else {
      await createReminder({ label: title, date: newDate.value })
    }
    newTitle.value = ''
    newDate.value = ''
    newKind.value = 'practice'
    showNewForm.value = false
  } catch {} finally {
    newSaving.value = false
  }
}

function onCompleteReminder(id: string) { completeReminder(id, true) }
function onUncompleteReminder(id: string) { completeReminder(id, false) }

function onNavigatePractice(id: string) {
  router.push(`/app/journey/practices/${id}`)
}

onMounted(async () => {
  await Promise.all([loadPractices(), loadReminders()])
  void today
})
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-6 sm:py-10">
    <p class="text-[10px] font-semibold uppercase tracking-[0.2em] text-sacred-label">Your Dharma</p>
    <p class="mt-3 text-xl sm:text-2xl font-semibold text-sacred-text">What needs your attention today?</p>

    <!-- Loading -->
    <div v-if="loading" class="mt-6 space-y-3">
      <div v-for="i in 2" :key="i" class="h-14 animate-pulse rounded-2xl bg-sacred-bg-pulse" />
    </div>

    <!-- Empty state -->
    <div v-else-if="!hasAnything && !showNewForm" class="mt-6 text-center">
      <p class="text-sm text-sacred-text-secondary">You haven't set anything yet.</p>
      <button
        @click="showNewForm = true"
        class="mt-4 min-h-[44px] rounded-full bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-3 text-sm font-semibold text-white shadow-sacred-button transition duration-200 active:scale-[0.97]"
      >
        Set your first practice
      </button>
    </div>

    <!-- New item form -->
    <div v-if="showNewForm" class="mt-6">
      <div class="mb-3 flex justify-center gap-2">
        <button @click="newKind = 'practice'" class="flex min-h-[44px] items-center gap-1.5 rounded-2xl border px-4 py-2.5 text-xs font-semibold transition duration-200 active:scale-[0.97]" :class="newKind === 'practice' ? 'border-sacred-gold text-sacred-gold bg-sacred-gold-light' : 'border-sacred-border text-sacred-text-secondary'">
          <SacredIcons name="flame" :size="14" /> Daily practice
        </button>
        <button @click="newKind = 'reminder'" class="flex min-h-[44px] items-center gap-1.5 rounded-2xl border px-4 py-2.5 text-xs font-semibold transition duration-200 active:scale-[0.97]" :class="newKind === 'reminder' ? 'border-sacred-gold text-sacred-gold bg-sacred-gold-light' : 'border-sacred-border text-sacred-text-secondary'">
          <SacredIcons name="target" :size="14" /> Reminder
        </button>
      </div>
      <input v-model="newTitle" type="text" :placeholder="newKind === 'practice' ? 'I want to practice...' : 'Remind me to...'" class="w-full rounded-2xl border border-sacred-border bg-sacred-bg-warm px-4 py-3 text-sm text-sacred-text placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold" @keyup.enter="newKind === 'practice' ? onCreate() : undefined" />
      <input v-if="newKind === 'reminder'" v-model="newDate" type="date" class="mt-2 w-full rounded-2xl border border-sacred-border bg-sacred-bg-warm px-4 py-3 text-sm text-sacred-text outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold" />
      <div class="mt-3 flex justify-center gap-2">
        <button @click="onCreate" :disabled="newSaving || !newTitle.trim() || (newKind === 'reminder' && !newDate)" class="min-h-[44px] rounded-full bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-2.5 text-sm font-semibold text-white shadow-sacred-button transition duration-200 active:scale-[0.97] disabled:opacity-60">
          {{ newSaving ? 'Saving...' : 'Save' }}
        </button>
        <button @click="showNewForm = false; newKind = 'practice'; newDate = ''" class="min-h-[44px] rounded-full border border-sacred-border-strong px-5 py-2.5 text-sm font-medium text-sacred-text-secondary transition duration-200 active:scale-[0.97]">
          Cancel
        </button>
      </div>
    </div>

    <!-- Practices -->
    <div v-if="pendingPractices.length > 0" class="mt-6">
      <div class="flex items-center gap-1.5 mb-3">
        <SacredIcons name="recurring" :size="14" class="text-sacred-label" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Practices</p>
      </div>
      <ul class="space-y-3">
        <TaskItem
          v-for="task in pendingPractices" :key="task.id" :task="task"
          @done="checkIn($event, true)" @skip="checkIn($event, false)"
          @undo="undoCheckIn" @navigate="onNavigatePractice"
          @delete="deletePractice"
        />
      </ul>
    </div>

    <!-- Reminders -->
    <div v-if="activeReminders.length > 0" class="mt-6">
      <div class="flex items-center gap-1.5 mb-3">
        <SacredIcons name="target" :size="14" class="text-sacred-label" />
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">Reminders</p>
      </div>
      <ul class="space-y-3">
        <ReminderItem
          v-for="r in activeReminders" :key="r.id" :reminder="r"
          @complete="onCompleteReminder"
          @uncomplete="onUncompleteReminder"
          @delete="deleteReminder"
        />
      </ul>
    </div>

    <!-- Completed -->
    <div v-if="completedPractices.length > 0 || completedReminders.length > 0" class="mt-4">
      <button @click="showCompleted = !showCompleted" class="flex min-h-[44px] items-center gap-1.5 text-xs font-medium text-sacred-green transition duration-200 hover:text-sacred-green-dark">
        <SacredIcons name="check" :size="12" />
        {{ completedPractices.length + completedReminders.length }} completed
        <span class="text-[10px]">{{ showCompleted ? '&#9650;' : '&#9660;' }}</span>
      </button>
      <ul v-if="showCompleted" class="mt-2 space-y-3">
        <TaskItem
          v-for="task in completedPractices" :key="task.id" :task="task"
          @done="checkIn($event, true)" @skip="checkIn($event, false)"
          @undo="undoCheckIn" @navigate="onNavigatePractice"
          @delete="deletePractice"
        />
        <ReminderItem
          v-for="r in completedReminders" :key="r.id" :reminder="r"
          @complete="onCompleteReminder"
          @uncomplete="onUncompleteReminder"
          @delete="deleteReminder"
        />
      </ul>
    </div>

    <!-- Skipped practices -->
    <div v-if="skippedPractices.length > 0" class="mt-2">
      <button @click="showSkipped = !showSkipped" class="flex min-h-[44px] items-center gap-1.5 text-xs font-medium text-sacred-muted transition duration-200 hover:text-sacred-text-secondary">
        <SacredIcons name="skip" :size="12" />
        {{ skippedPractices.length }} skipped
        <span class="text-[10px]">{{ showSkipped ? '&#9650;' : '&#9660;' }}</span>
      </button>
      <ul v-if="showSkipped" class="mt-2 space-y-3">
        <TaskItem
          v-for="task in skippedPractices" :key="task.id" :task="task"
          @done="checkIn($event, true)" @skip="checkIn($event, false)"
          @undo="undoCheckIn" @navigate="onNavigatePractice"
          @delete="deletePractice"
        />
      </ul>
    </div>

    <!-- Add button -->
    <button
      v-if="hasAnything && !showNewForm"
      @click="showNewForm = true"
      class="mt-4 flex min-h-[44px] items-center justify-center gap-1.5 text-xs font-medium text-sacred-gold transition duration-200 hover:text-sacred-gold-dark active:scale-[0.97]"
    >
      + Add
    </button>
  </div>
</template>
