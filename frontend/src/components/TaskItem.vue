<script setup lang="ts">
import { ref } from 'vue'
import SacredIcons from '@/components/icons/SacredIcons.vue'

interface Task {
  id: string
  title: string
  type: 'Recurring' | 'OneTime'
  checkedIn: boolean
  completedToday: boolean | null
  daysRemaining: number | null
  feedbackMessage: string | null
  saving: boolean
}

const props = defineProps<{
  task: Task
}>()

const emit = defineEmits<{
  done: [id: string]
  skip: [id: string]
  undo: [id: string]
  navigate: [id: string]
}>()

const showMenu = ref(false)

const isOverdue = props.task.type === 'OneTime' && props.task.daysRemaining != null && props.task.daysRemaining <= 0

function onAction(action: 'done' | 'skip' | 'undo') {
  showMenu.value = false
  emit(action, props.task.id)
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
      <!-- Status indicator -->
      <div
        class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full"
        :class="
          task.checkedIn && task.completedToday
            ? 'bg-gradient-to-br from-[#7aa87a] to-[#5a8a5a]'
            : task.checkedIn
              ? 'border-2 border-[rgba(139,90,43,0.2)] bg-[rgba(250,245,237,0.6)]'
              : 'border-2 border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.6)]'
        "
      >
        <SacredIcons v-if="task.checkedIn && task.completedToday" name="check" :size="12" class="text-white" />
        <SacredIcons v-else-if="task.checkedIn" name="skip" :size="10" class="text-[#b5996f]" />
      </div>

      <!-- Title -->
      <button
        class="flex-1 text-left text-sm font-medium transition duration-200 hover:text-[#c4873b]"
        :class="task.checkedIn && task.completedToday ? 'text-[#7aa87a] line-through decoration-[rgba(122,168,122,0.4)]' : 'text-[#2b1e10]'"
        @click="emit('navigate', task.id)"
      >{{ task.title }}</button>

      <!-- Type icon + info -->
      <template v-if="task.type === 'OneTime'">
        <span v-if="task.daysRemaining != null" class="shrink-0 font-serif text-xs" :class="task.daysRemaining <= 0 ? 'font-bold text-[#b45a3c]' : 'text-[#c4873b]'">
          {{ task.daysRemaining > 0 ? `${task.daysRemaining}d` : task.daysRemaining === 0 ? 'Today' : `${Math.abs(task.daysRemaining)}d over` }}
        </span>
      </template>

      <!-- Type badge -->
      <SacredIcons :name="task.type === 'Recurring' ? 'recurring' : 'target'" :size="14" class="shrink-0 opacity-40" :class="task.type === 'Recurring' ? 'text-[#b5996f]' : 'text-[#c4873b]'" />

      <!-- Three-dot menu (recurring only, not saving) -->
      <button
        v-if="task.type === 'Recurring' && !task.saving"
        @click.stop="showMenu = !showMenu"
        class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-[#9a8568] transition duration-200 hover:bg-[rgba(139,90,43,0.08)]"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="12" cy="19" r="2"/></svg>
      </button>
    </div>

    <!-- Dropdown menu -->
    <div
      v-if="showMenu"
      class="absolute right-4 top-12 z-10 min-w-[160px] rounded-xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.98)] py-1 shadow-[0_4px_16px_rgba(82,54,29,0.12)] backdrop-blur-[20px]"
    >
      <button
        v-if="!task.checkedIn"
        @click="onAction('done')"
        class="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm text-[#2b1e10] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
      >
        <SacredIcons name="check" :size="14" class="text-[#7aa87a]" />
        Mark complete
      </button>
      <button
        v-if="!task.checkedIn"
        @click="onAction('skip')"
        class="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm text-[#2b1e10] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
      >
        <SacredIcons name="skip" :size="14" class="text-[#b5996f]" />
        Skip for today
      </button>
      <button
        v-if="task.checkedIn"
        @click="onAction('undo')"
        class="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm text-[#2b1e10] transition duration-200 hover:bg-[rgba(139,90,43,0.06)]"
      >
        <SacredIcons name="recurring" :size="14" class="text-[#c4873b]" />
        Undo
      </button>
    </div>

    <!-- Click outside to close menu -->
    <div v-if="showMenu" class="fixed inset-0 z-[5]" @click="showMenu = false" />

    <!-- Spiritual feedback after check-in -->
    <p v-if="task.checkedIn && task.feedbackMessage" class="mt-2 ml-9 font-serif text-xs italic leading-relaxed text-[#9a8568]">
      {{ task.feedbackMessage }}
    </p>
  </li>
</template>
