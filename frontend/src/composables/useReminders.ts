/**
 * Reminder (date-based) management composable.
 *
 * Loads reminders (own + circle), and exposes create / update /
 * complete / delete actions. Reminders may be one-time or yearly.
 */

import { ref, computed } from 'vue'
import { useApi } from '@/composables/useApi'
import { useNotification } from '@/composables/useNotification'
import type { Reminder, ReminderTask, ReminderRecurrence } from '@/types'

export function useReminders() {
  const api = useApi()
  const { notify } = useNotification()

  const reminders = ref<Reminder[]>([])
  const loading = ref(true)
  const savingState = ref<Record<string, boolean>>({})

  function toTask(r: Reminder): ReminderTask {
    return {
      id: r.id,
      label: r.label,
      date: r.date,
      recurrence: r.recurrence,
      daysRemaining: r.daysRemaining,
      completed: r.completedAt != null,
      saving: savingState.value[r.id] ?? false,
    }
  }

  const ownReminders = computed(() => reminders.value.filter(r => !r.connectionId))
  const activeReminders = computed(() => ownReminders.value.filter(r => !r.completedAt).map(toTask))
  const completedReminders = computed(() => ownReminders.value.filter(r => r.completedAt).map(toTask))
  const hasReminders = computed(() => reminders.value.length > 0)

  async function loadReminders(connectionId?: string) {
    loading.value = true
    try {
      const query = connectionId ? `?connectionId=${connectionId}` : ''
      const data = await api.get<any>(`/reminders${query}`)
      const items = Array.isArray(data) ? data : (data?.reminders || data?.items || [])
      reminders.value = items.map((r: any): Reminder => ({
        id: r.id,
        label: r.label,
        date: typeof r.date === 'string' ? r.date : String(r.date),
        recurrence: (r.recurrence ?? 'none') as ReminderRecurrence,
        remindersEnabled: r.remindersEnabled ?? false,
        connectionId: r.connectionId ?? null,
        completedAt: r.completedAt ?? null,
        createdAt: r.createdAt ?? '',
        daysRemaining: r.daysRemaining ?? 0,
      }))
    } catch {
      notify.error('Failed to load reminders')
      reminders.value = []
    } finally {
      loading.value = false
    }
  }

  async function createReminder(body: {
    label: string
    date: string
    recurrence?: ReminderRecurrence
    remindersEnabled?: boolean
    connectionId?: string
  }): Promise<Reminder | null> {
    try {
      const r = await api.post<any>('/reminders', body)
      const reminder: Reminder = {
        id: r.id,
        label: r.label,
        date: typeof r.date === 'string' ? r.date : String(r.date),
        recurrence: (r.recurrence ?? 'none') as ReminderRecurrence,
        remindersEnabled: r.remindersEnabled ?? false,
        connectionId: r.connectionId ?? null,
        completedAt: r.completedAt ?? null,
        createdAt: r.createdAt ?? '',
        daysRemaining: r.daysRemaining ?? 0,
      }
      reminders.value.push(reminder)
      return reminder
    } catch {
      notify.error('Failed to create reminder')
      return null
    }
  }

  async function updateReminder(id: string, body: {
    label?: string
    date?: string
    recurrence?: ReminderRecurrence
    remindersEnabled?: boolean
    completed?: boolean
  }) {
    savingState.value[id] = true
    try {
      await api.patch(`/reminders/${id}`, body)
      const r = reminders.value.find(x => x.id === id)
      if (r) {
        if (body.label !== undefined) r.label = body.label
        if (body.date !== undefined) r.date = body.date
        if (body.recurrence !== undefined) r.recurrence = body.recurrence
        if (body.remindersEnabled !== undefined) r.remindersEnabled = body.remindersEnabled
        if (body.completed !== undefined) {
          r.completedAt = body.completed ? new Date().toISOString() : null
        }
      }
    } catch {
      notify.error('Failed to update reminder')
    } finally {
      savingState.value[id] = false
    }
  }

  async function completeReminder(id: string, completed: boolean) {
    await updateReminder(id, { completed })
  }

  async function deleteReminder(id: string) {
    try {
      await api.delete(`/reminders/${id}`)
      reminders.value = reminders.value.filter(r => r.id !== id)
      delete savingState.value[id]
    } catch {
      notify.error('Failed to delete reminder')
    }
  }

  return {
    reminders,
    loading,
    hasReminders,
    activeReminders,
    completedReminders,
    loadReminders,
    createReminder,
    updateReminder,
    completeReminder,
    deleteReminder,
  }
}
