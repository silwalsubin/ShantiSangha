<script setup lang="ts">
/**
 * Home page — "What needs your attention today?"
 *
 * Shows active reminders (date-based). Completed items collapse
 * into an expandable summary. Inline form for adding a new reminder.
 */

import { ref, onMounted, computed } from 'vue'
import { useReminders } from '@/composables/useReminders'
import { useLocalDate } from '@/composables/useLocalDate'
import SacredIcons from '@/components/icons/SacredIcons.vue'
import ReminderItem from '@/components/ReminderItem.vue'

const { today } = useLocalDate()

const {
  loading,
  activeReminders, completedReminders,
  loadReminders, createReminder, completeReminder, deleteReminder,
} = useReminders()

const hasAnything = computed(() => activeReminders.value.length > 0 || completedReminders.value.length > 0)

const showCompleted = ref(false)

const showNewForm = ref(false)
const newTitle = ref('')
const newDate = ref('')
const newSaving = ref(false)

async function onCreate() {
  const title = newTitle.value.trim()
  if (!title || !newDate.value) return
  newSaving.value = true
  try {
    await createReminder({ label: title, date: newDate.value })
    newTitle.value = ''
    newDate.value = ''
    showNewForm.value = false
  } catch {} finally {
    newSaving.value = false
  }
}

function onCompleteReminder(id: string) { completeReminder(id, true) }
function onUncompleteReminder(id: string) { completeReminder(id, false) }

onMounted(async () => {
  await loadReminders()
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
      <p class="text-sm text-sacred-text-secondary">Nothing on your plate yet.</p>
      <button
        @click="showNewForm = true"
        class="mt-4 min-h-[44px] rounded-full bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-3 text-sm font-semibold text-white shadow-sacred-button transition duration-200 active:scale-[0.97]"
      >
        Add your first reminder
      </button>
    </div>

    <!-- New reminder form -->
    <div v-if="showNewForm" class="mt-6">
      <input v-model="newTitle" type="text" placeholder="Remind me to..." class="w-full rounded-2xl border border-sacred-border bg-sacred-bg-warm px-4 py-3 text-sm text-sacred-text placeholder-sacred-muted-light outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold" />
      <input v-model="newDate" type="date" class="mt-2 w-full rounded-2xl border border-sacred-border bg-sacred-bg-warm px-4 py-3 text-sm text-sacred-text outline-none transition duration-200 focus:border-sacred-gold focus:ring-1 focus:ring-sacred-gold" />
      <div class="mt-3 flex justify-center gap-2">
        <button @click="onCreate" :disabled="newSaving || !newTitle.trim() || !newDate" class="min-h-[44px] rounded-full bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-2.5 text-sm font-semibold text-white shadow-sacred-button transition duration-200 active:scale-[0.97] disabled:opacity-60">
          {{ newSaving ? 'Saving...' : 'Save' }}
        </button>
        <button @click="showNewForm = false; newDate = ''" class="min-h-[44px] rounded-full border border-sacred-border-strong px-5 py-2.5 text-sm font-medium text-sacred-text-secondary transition duration-200 active:scale-[0.97]">
          Cancel
        </button>
      </div>
    </div>

    <!-- Active reminders -->
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
    <div v-if="completedReminders.length > 0" class="mt-4">
      <button @click="showCompleted = !showCompleted" class="flex min-h-[44px] items-center gap-1.5 text-xs font-medium text-sacred-green transition duration-200 hover:text-sacred-green-dark">
        <SacredIcons name="check" :size="12" />
        {{ completedReminders.length }} completed
        <span class="text-[10px]">{{ showCompleted ? '&#9650;' : '&#9660;' }}</span>
      </button>
      <ul v-if="showCompleted" class="mt-2 space-y-3">
        <ReminderItem
          v-for="r in completedReminders" :key="r.id" :reminder="r"
          @complete="onCompleteReminder"
          @uncomplete="onUncompleteReminder"
          @delete="deleteReminder"
        />
      </ul>
    </div>

    <!-- Add button -->
    <button
      v-if="hasAnything && !showNewForm"
      @click="showNewForm = true"
      class="mt-4 flex min-h-[44px] items-center justify-center gap-1.5 text-xs font-medium text-sacred-gold transition duration-200 hover:text-sacred-gold-dark active:scale-[0.97]"
    >
      + Add reminder
    </button>
  </div>
</template>
