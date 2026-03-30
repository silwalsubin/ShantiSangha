<script setup lang="ts">
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

const isOverdue = props.task.type === 'OneTime' && props.task.daysRemaining != null && props.task.daysRemaining <= 0
</script>

<template>
  <li
    class="rounded-2xl border px-4 py-3 transition-all duration-300"
    :class="
      task.checkedIn
        ? 'border-[rgba(122,168,122,0.25)] bg-[rgba(122,168,122,0.06)]'
        : isOverdue
          ? 'border-[rgba(180,90,60,0.25)] bg-[rgba(180,90,60,0.06)]'
          : 'border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)]'
    "
  >
    <div class="flex items-center gap-3">
      <!-- Check circle (tap to undo when checked in) -->
      <button
        class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full transition-all duration-300"
        :class="
          task.checkedIn
            ? (task.completedToday
              ? 'bg-gradient-to-br from-[#7aa87a] to-[#5a8a5a] hover:from-[#6a9a6a] hover:to-[#4a7a4a]'
              : 'border-2 border-[rgba(139,90,43,0.2)] bg-[rgba(250,245,237,0.6)] hover:bg-[rgba(139,90,43,0.08)]')
            : 'border-2 border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.6)]'
        "
        :disabled="!task.checkedIn || task.saving"
        @click.stop="task.checkedIn ? emit('undo', task.id) : undefined"
      >
        <SacredIcons v-if="task.checkedIn && task.completedToday" name="check" :size="14" class="text-white" />
        <SacredIcons v-else-if="task.checkedIn" name="skip" :size="12" class="text-[#b5996f]" />
      </button>

      <!-- Title -->
      <button
        class="flex-1 text-left text-sm font-medium transition duration-200 hover:text-[#c4873b]"
        :class="task.checkedIn && task.completedToday ? 'text-[#7aa87a] line-through decoration-[rgba(122,168,122,0.4)]' : 'text-[#2b1e10]'"
        @click="emit('navigate', task.id)"
      >{{ task.title }}</button>

      <!-- Type icon + info -->
      <template v-if="task.type === 'Recurring'">
        <SacredIcons name="recurring" :size="14" class="shrink-0 text-[#b5996f] opacity-40" />
      </template>
      <template v-else>
        <span v-if="task.daysRemaining != null" class="shrink-0 font-serif text-xs" :class="task.daysRemaining <= 0 ? 'font-bold text-[#b45a3c]' : 'text-[#c4873b]'">
          {{ task.daysRemaining > 0 ? `${task.daysRemaining}d` : task.daysRemaining === 0 ? 'Today' : `${Math.abs(task.daysRemaining)}d over` }}
        </span>
        <SacredIcons name="target" :size="14" class="shrink-0 text-[#c4873b] opacity-60" />
      </template>
    </div>

    <!-- Spiritual feedback after check-in -->
    <p v-if="task.checkedIn && task.feedbackMessage" class="mt-2 ml-10 font-serif text-xs italic leading-relaxed text-[#9a8568]">
      {{ task.feedbackMessage }}
    </p>

    <!-- Check-in icons (recurring only, when not checked in) -->
    <div v-if="task.type === 'Recurring' && !task.checkedIn" class="mt-1 ml-10 flex items-center gap-3">
      <button @click="emit('done', task.id)" :disabled="task.saving" title="Done" class="flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-[#7aa87a] to-[#5a8a5a] text-white shadow-sm transition duration-200 active:scale-[0.93] disabled:opacity-60 hover:from-[#6a9a6a] hover:to-[#4a7a4a]">
        <SacredIcons name="check" :size="14" />
      </button>
      <button @click="emit('skip', task.id)" :disabled="task.saving" title="Not today" class="flex h-8 w-8 items-center justify-center rounded-full border border-[rgba(139,90,43,0.2)] text-[#b5996f] transition duration-200 active:scale-[0.93] disabled:opacity-60 hover:bg-[rgba(139,90,43,0.06)]">
        <SacredIcons name="skip" :size="12" />
      </button>
    </div>
  </li>
</template>
