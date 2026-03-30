/**
 * Global notification system.
 *
 * Provides toast-style notifications for success, error, and info messages.
 * Uses a singleton reactive array so notifications work across components.
 *
 * Usage:
 *   const { notify, notifications } = useNotification()
 *   notify.success('Task completed')
 *   notify.error('Failed to save')
 *
 * Render <NotificationToast /> once in AppLayout.vue to display them.
 */

import { ref } from 'vue'

export interface Notification {
  id: number
  type: 'success' | 'error' | 'info'
  message: string
}

// Singleton state — shared across all components
const notifications = ref<Notification[]>([])
let nextId = 0

function addNotification(type: Notification['type'], message: string, duration = 4000) {
  const id = nextId++
  notifications.value.push({ id, type, message })
  setTimeout(() => {
    notifications.value = notifications.value.filter(n => n.id !== id)
  }, duration)
}

export function useNotification() {
  return {
    notifications,
    notify: {
      success: (message: string) => addNotification('success', message),
      error: (message: string) => addNotification('error', message, 6000),
      info: (message: string) => addNotification('info', message),
    },
  }
}
