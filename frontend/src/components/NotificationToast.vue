<script setup lang="ts">
/**
 * Global notification toast display.
 *
 * Render once in AppLayout.vue. Shows toast messages from useNotification().
 * Auto-dismisses after the configured duration.
 */

import { useNotification } from '@/composables/useNotification'

const { notifications } = useNotification()
</script>

<template>
  <Teleport to="body">
    <div class="fixed top-4 right-4 z-50 flex flex-col gap-2 max-w-sm">
      <TransitionGroup name="toast">
        <div
          v-for="n in notifications"
          :key="n.id"
          class="rounded-xl border px-4 py-3 text-sm shadow-sacred backdrop-blur-[20px]"
          :class="{
            'border-sacred-green-border bg-sacred-green-bg text-sacred-green-dark': n.type === 'success',
            'border-sacred-red-border bg-sacred-red-bg text-sacred-red': n.type === 'error',
            'border-sacred-border bg-sacred-bg-card text-sacred-text': n.type === 'info',
          }"
        >
          {{ n.message }}
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>

<style scoped>
.toast-enter-active { transition: all 0.3s ease; }
.toast-leave-active { transition: all 0.2s ease; }
.toast-enter-from { opacity: 0; transform: translateX(100%); }
.toast-leave-to { opacity: 0; transform: translateX(100%); }
</style>
