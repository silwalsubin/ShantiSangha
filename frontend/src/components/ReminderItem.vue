<script setup lang="ts">
import { ref, computed } from 'vue'
import SacredIcons from '@/components/icons/SacredIcons.vue'
import type { ReminderTask } from '@/types'

const props = defineProps<{
  reminder: ReminderTask
}>()

const emit = defineEmits<{
  complete: [id: string]
  uncomplete: [id: string]
  delete: [id: string]
}>()

const showMenu = ref(false)
const confirmDelete = ref(false)

const isOverdue = computed(() => !props.reminder.completed && props.reminder.daysRemaining < 0)

const daysLabel = computed(() => {
  const d = props.reminder.daysRemaining
  if (props.reminder.completed) return 'Done'
  if (d > 0) return `${d}d`
  if (d === 0) return 'Today'
  return `${Math.abs(d)}d over`
})

function onComplete() { showMenu.value = false; emit('complete', props.reminder.id) }
function onUncomplete() { showMenu.value = false; emit('uncomplete', props.reminder.id) }
</script>

<template>
  <li
    class="relative rounded-sacred-lg border px-4 py-3 transition-all duration-300"
    :class="
      reminder.completed
        ? 'border-sacred-green-border bg-sacred-green-bg'
        : isOverdue
          ? 'border-sacred-red-border bg-sacred-red-bg'
          : 'border-sacred-border-subtle bg-sacred-bg-card-inner'
    "
  >
    <div class="flex items-center gap-3">
      <div class="flex h-6 w-6 shrink-0 items-center justify-center">
        <SacredIcons name="target" :size="14" class="text-sacred-gold" />
      </div>

      <p
        class="flex-1 text-left text-sm font-medium"
        :class="reminder.completed ? 'text-sacred-green line-through decoration-sacred-green-border' : 'text-sacred-text'"
      >{{ reminder.label }}</p>

      <span
        class="shrink-0 font-serif text-xs"
        :class="reminder.completed ? 'text-sacred-green' : isOverdue ? 'font-bold text-sacred-red' : 'text-sacred-gold'"
      >{{ daysLabel }}</span>

      <button
        v-if="!reminder.saving"
        @click.stop="showMenu = !showMenu"
        @keydown.escape="showMenu = false"
        :aria-label="`Actions for ${reminder.label}`"
        :aria-expanded="showMenu"
        aria-haspopup="true"
        class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sacred-muted transition duration-200 hover:bg-sacred-bg-hover-strong"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="12" cy="19" r="2"/></svg>
      </button>
    </div>

    <div
      v-if="showMenu"
      role="menu"
      :aria-label="`Actions for ${reminder.label}`"
      @keydown.escape="showMenu = false"
      class="absolute right-4 top-12 z-10 min-w-[180px] rounded-xl border border-sacred-border bg-sacred-bg-warm py-1 shadow-sacred-dropdown backdrop-blur-[20px]"
    >
      <button
        v-if="!reminder.completed"
        @click="onComplete"
        role="menuitem"
        class="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-sacred-text transition duration-200 hover:bg-sacred-bg-hover"
      >
        <SacredIcons name="check" :size="14" class="text-sacred-green" />
        Mark complete
      </button>

      <button
        v-if="reminder.completed"
        @click="onUncomplete"
        role="menuitem"
        class="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-sacred-text transition duration-200 hover:bg-sacred-bg-hover"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 14L4 9l5-5"/><path d="M4 9h11a4 4 0 010 8h-1"/></svg>
        Move to pending
      </button>

      <div class="my-1 border-t border-sacred-border-light" />

      <button
        v-if="!confirmDelete"
        @click="confirmDelete = true"
        class="flex w-full items-center gap-2.5 px-4 py-2.5 text-left text-sm text-sacred-red transition duration-200 hover:bg-sacred-red-bg"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6"/><path d="M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2"/></svg>
        Delete
      </button>
      <div v-if="confirmDelete" class="px-4 py-2.5">
        <p class="text-xs text-sacred-text-secondary">This will delete the reminder.</p>
        <div class="mt-2 flex gap-2">
          <button
            @click="confirmDelete = false; showMenu = false; emit('delete', reminder.id)"
            class="rounded-lg bg-sacred-red px-3 py-1.5 text-xs font-semibold text-white transition duration-200 active:scale-[0.95]"
          >
            Delete
          </button>
          <button
            @click="confirmDelete = false"
            class="rounded-lg px-3 py-1.5 text-xs text-sacred-text-secondary transition duration-200 hover:bg-sacred-bg-hover"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>

    <div v-if="showMenu" class="fixed inset-0 z-[5]" @click="showMenu = false" />
  </li>
</template>
