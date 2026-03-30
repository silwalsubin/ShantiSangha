<script setup lang="ts">
import { ref } from 'vue'
import SacredIcons from '@/components/icons/SacredIcons.vue'
import type { Task } from '@/types'

const props = defineProps<{
  task: Task
}>()

const emit = defineEmits<{
  done: [id: string]
  skip: [id: string]
  undo: [id: string]
  delete: [id: string]
  navigate: [id: string]
  progress: [id: string, value: number]
}>()

const showMenu = ref(false)
const showProgress = ref(false)
const confirmDelete = ref(false)
const progressValue = ref(props.task.progress)

const isOverdue = props.task.type === 'OneTime' && props.task.daysRemaining != null && props.task.daysRemaining <= 0

function onAction(action: 'done' | 'skip' | 'undo') {
  showMenu.value = false
  emit(action, props.task.id)
}

function openProgress() {
  showMenu.value = false
  progressValue.value = props.task.progress
  showProgress.value = true
}

function saveProgress() {
  showProgress.value = false
  emit('progress', props.task.id, progressValue.value)
}
</script>

<template>
  <li
    class="relative rounded-2xl border px-4 py-3 transition-all duration-300"
    :class="
      task.checkedIn
        ? 'border-[rgba(122,168,122,0.25)] bg-[rgba(122,168,122,0.06)]'
        : isOverdue
          ? 'border-[rgba(180,90,60,0.25)] bg-[rgba(180,90,60,0.06)]'
          : 'border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)]'
    "
  >
    <div class="flex items-center gap-3">
      <!-- Type icon -->
      <div class="flex h-6 w-6 shrink-0 items-center justify-center">
        <SacredIcons :name="task.type === 'Recurring' ? 'recurring' : 'target'" :size="14" :class="task.type === 'Recurring' ? 'text-[#b5996f]' : 'text-[#c4873b]'" />
      </div>

      <!-- Title -->
      <button
        class="flex-1 text-left text-sm font-medium transition duration-200 hover:text-[#c4873b]"
        :class="task.checkedIn && task.completedToday ? 'text-[#7aa87a] line-through decoration-[rgba(122,168,122,0.4)]' : 'text-[#2b1e10]'"
        @click="emit('navigate', task.id)"
      >{{ task.title }}</button>

      <!-- Milestone info -->
      <span v-if="task.type === 'OneTime' && task.daysRemaining != null" class="shrink-0 font-serif text-xs" :class="task.daysRemaining <= 0 ? 'font-bold text-[#b45a3c]' : 'text-[#c4873b]'">
        {{ task.daysRemaining > 0 ? `${task.daysRemaining}d` : task.daysRemaining === 0 ? 'Today' : `${Math.abs(task.daysRemaining)}d over` }}
      </span>

      <!-- Three-dot menu -->
      <button
        v-if="!task.saving"
        @click.stop="showMenu = !showMenu"
        class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-[#9a8568] transition duration-200 hover:bg-[rgba(139,90,43,0.08)]"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="12" cy="19" r="2"/></svg>
      </button>
    </div>

    <!-- Progress bar for milestones -->
    <div v-if="task.type === 'OneTime' && !showProgress" class="mt-2 ml-9">
      <div class="h-1.5 w-full rounded-full bg-[rgba(139,90,43,0.1)]">
        <div class="h-1.5 rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] transition-all duration-300" :style="{ width: `${task.progress}%` }" />
      </div>
      <p class="mt-1 text-[10px] text-[#9a8568]">{{ task.progress }}% complete</p>
    </div>

    <!-- Progress slider (inline edit) -->
    <div v-if="showProgress" class="mt-3 ml-9">
      <input
        v-model.number="progressValue"
        type="range"
        min="0"
        max="100"
        step="5"
        class="w-full accent-[#c4873b]"
      />
      <div class="mt-1 flex items-center justify-between">
        <span class="text-xs font-medium text-[#c4873b]">{{ progressValue }}%</span>
        <div class="flex gap-2">
          <button @click="showProgress = false" class="text-xs text-[#9a8568] hover:text-[#6b5740]">Cancel</button>
          <button @click="saveProgress" class="text-xs font-semibold text-[#c4873b] hover:text-[#8b5a1b]">Save</button>
        </div>
      </div>
    </div>

    <!-- Dropdown menu -->
    <div
      v-if="showMenu"
      class="absolute right-4 top-12 z-10 min-w-[180px] rounded-xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.98)] py-1 shadow-[0_4px_16px_rgba(82,54,29,0.12)] backdrop-blur-[20px]"
    >
      <!-- Mark complete -->
      <button
        v-if="!task.checkedIn"
        @click="onAction('done')"
        class="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-[#2b1e10] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
      >
        <SacredIcons name="check" :size="14" class="text-[#7aa87a]" />
        Mark complete
      </button>

      <!-- Update progress (milestone only) -->
      <button
        v-if="task.type === 'OneTime' && !task.checkedIn"
        @click="openProgress"
        class="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-[#2b1e10] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
      >
        <SacredIcons name="dharma" :size="14" class="text-[#c4873b]" />
        Update progress
      </button>

      <!-- Skip for today -->
      <button
        v-if="!task.checkedIn"
        @click="onAction('skip')"
        class="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-[#2b1e10] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
      >
        <SacredIcons name="skip" :size="14" class="text-[#b5996f]" />
        Skip for today
      </button>

      <!-- Move back to pending -->
      <button
        v-if="task.checkedIn"
        @click="onAction('undo')"
        class="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-[#2b1e10] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 14L4 9l5-5"/><path d="M4 9h11a4 4 0 010 8h-1"/></svg>
        Move to pending
      </button>

      <!-- Divider -->
      <div class="my-1 border-t border-[rgba(139,90,43,0.08)]" />

      <!-- Delete -->
      <button
        v-if="!confirmDelete"
        @click="confirmDelete = true"
        class="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-[#b45a3c] transition duration-200 hover:bg-[rgba(180,90,60,0.06)]"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6"/><path d="M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2"/></svg>
        Delete
      </button>
      <div v-if="confirmDelete" class="px-4 py-2.5">
        <p class="text-xs text-[#6b5740]">This will delete the task and all its history.</p>
        <div class="mt-2 flex gap-2">
          <button
            @click="confirmDelete = false; showMenu = false; emit('delete', task.id)"
            class="rounded-lg bg-[#b45a3c] px-3 py-1.5 text-xs font-semibold text-white transition duration-200 active:scale-[0.95]"
          >
            Delete
          </button>
          <button
            @click="confirmDelete = false"
            class="rounded-lg px-3 py-1.5 text-xs text-[#6b5740] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>

    <!-- Click outside to close menu -->
    <div v-if="showMenu" class="fixed inset-0 z-[5]" @click="showMenu = false" />

    <!-- Spiritual feedback after check-in -->
    <p v-if="task.checkedIn && task.feedbackMessage" class="mt-2 ml-9 font-serif text-xs italic leading-relaxed text-[#9a8568]">
      {{ task.feedbackMessage }}
    </p>
  </li>
</template>
