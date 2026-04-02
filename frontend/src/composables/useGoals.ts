/**
 * Goal and task management composable.
 *
 * Centralizes all goal/task data loading, check-in actions, and
 * spiritual feedback generation. Used by home.vue and any future
 * page that needs goal data.
 *
 * Responsibilities:
 * - Load recurring tasks and milestones from API
 * - Check in (done/skip), undo, delete, update progress
 * - Generate spiritual feedback messages based on streaks
 * - Provide computed lists: active, completed, skipped
 */

import { ref, computed } from 'vue'
import { useApi } from '@/composables/useApi'
import { useLocalDate } from '@/composables/useLocalDate'
import { useNotification } from '@/composables/useNotification'
import type { Task } from '@/types'

// Internal type with streak data for feedback generation
interface TaskInternal extends Task {
  _currentStreak: number
  _longestStreak: number
}

export function useGoals() {
  const api = useApi()
  const { today } = useLocalDate()
  const { notify } = useNotification()

  const tasks = ref<TaskInternal[]>([])
  const loading = ref(true)
  const feedbackMessages = ref<Record<string, string>>({})
  const savingState = ref<Record<string, boolean>>({})

  // --- Computed lists ---

  function withLiveState(list: TaskInternal[]): Task[] {
    return list.map(t => ({
      ...t,
      feedbackMessage: feedbackMessages.value[t.id] ?? null,
      saving: savingState.value[t.id] ?? false,
    }))
  }

  const activeTasks = computed(() =>
    tasks.value.filter(t => !t.checkedIn)
  )

  const recurringTasks = computed(() =>
    withLiveState(activeTasks.value.filter(t => t.type === 'Recurring'))
  )

  const milestoneTasks = computed(() =>
    withLiveState(activeTasks.value.filter(t => t.type === 'OneTime'))
  )

  const completedTasks = computed(() =>
    withLiveState(tasks.value.filter(t => t.checkedIn && t.completedToday === true))
  )

  const skippedTasks = computed(() =>
    withLiveState(tasks.value.filter(t => t.checkedIn && t.completedToday === false))
  )

  const hasTasks = computed(() => tasks.value.length > 0)

  // --- Data loading ---

  async function load() {
    loading.value = true
    try {
      // Load recurring tasks with today's check-in status
      const todayData = await api.get<any>(`/goals/today?date=${today()}`)
      const todayItems = Array.isArray(todayData) ? todayData : (todayData?.goals || todayData?.items || [])

      const recurring: TaskInternal[] = todayItems.map((g: any) => {
        const checkedIn = g.checkIn != null
        const completedToday = g.checkIn?.completed ?? null
        const currentStreak = g.currentStreak ?? 0
        const longestStreak = g.longestStreak ?? 0
        return {
          id: g.id,
          title: g.title,
          type: 'Recurring' as const,
          checkedIn,
          completedToday,
          daysRemaining: null,
          progress: 0,
          feedbackMessage: null,
          saving: false,
          _currentStreak: currentStreak,
          _longestStreak: longestStreak,
        }
      })

      // Generate feedback for tasks already checked in today
      for (const t of recurring) {
        if (t.checkedIn) {
          feedbackMessages.value[t.id] = generateFeedback(
            t.completedToday ? t._currentStreak - 1 : 0,
            t._longestStreak,
            t.completedToday ?? false
          )
        }
      }

      // Load all goals for milestones
      const allData = await api.get<any>(`/goals?date=${today()}`)
      const allItems = Array.isArray(allData) ? allData : (allData?.goals || allData?.items || [])

      const milestones: TaskInternal[] = allItems
        .filter((g: any) => (g.type ?? '') === 'OneTime' && !g.completedAt && !g.completed_at)
        .map((g: any) => {
          const checkIn = g.checkIn ?? null
          return {
            id: g.id,
            title: g.title,
            type: 'OneTime' as const,
            checkedIn: checkIn != null,
            completedToday: checkIn?.completed ?? null,
            daysRemaining: g.daysRemaining ?? null,
            progress: g.progress ?? 0,
            feedbackMessage: null,
            saving: false,
            _currentStreak: 0,
            _longestStreak: 0,
          }
        })
        .sort((a: TaskInternal, b: TaskInternal) => {
          const aD = a.daysRemaining ?? 9999
          const bD = b.daysRemaining ?? 9999
          if (aD <= 0 && bD > 0) return -1
          if (bD <= 0 && aD > 0) return 1
          return aD - bD
        })

      tasks.value = [...recurring, ...milestones]
    } catch {
      notify.error('Failed to load tasks')
      tasks.value = []
    } finally {
      loading.value = false
    }
  }

  // --- Actions ---

  async function checkIn(id: string, completed: boolean) {
    savingState.value[id] = true
    try {
      await api.post(`/goals/${id}/checkin`, { completed, date: today() })
      const task = tasks.value.find(t => t.id === id)
      if (task) {
        feedbackMessages.value[id] = generateFeedback(
          task._currentStreak, task._longestStreak, completed
        )
        task.checkedIn = true
        task.completedToday = completed
        if (completed) task._currentStreak += 1
        else task._currentStreak = 0
      }
    } catch {
      notify.error('Failed to check in')
    } finally {
      savingState.value[id] = false
    }
  }

  async function undoCheckIn(id: string) {
    savingState.value[id] = true
    try {
      await api.delete(`/goals/${id}/checkin?date=${today()}`)
      const task = tasks.value.find(t => t.id === id)
      if (task) {
        task.checkedIn = false
        task.completedToday = null
      }
      delete feedbackMessages.value[id]
    } catch {
      notify.error('Failed to undo check-in')
    } finally {
      savingState.value[id] = false
    }
  }

  async function updateProgress(id: string, value: number) {
    savingState.value[id] = true
    try {
      await api.patch(`/goals/${id}`, { progress: value })
      const task = tasks.value.find(t => t.id === id)
      if (task) task.progress = value
    } catch {
      notify.error('Failed to update progress')
    } finally {
      savingState.value[id] = false
    }
  }

  async function deleteGoal(id: string) {
    try {
      await api.delete(`/goals/${id}`)
      tasks.value = tasks.value.filter(t => t.id !== id)
      delete feedbackMessages.value[id]
      delete savingState.value[id]
    } catch {
      notify.error('Failed to delete task')
    }
  }

  async function createGoal(title: string, type: 'Recurring' | 'OneTime', targetDate?: string) {
    const payload: any = { title, type }
    if (type === 'OneTime' && targetDate) payload.targetDate = targetDate
    await api.post('/goals', payload)
    await load()
  }

  // --- Spiritual feedback ---

  function generateFeedback(currentStreak: number, longestStreak: number, completed: boolean): string {
    const streak = completed ? currentStreak + 1 : 0

    if (completed) {
      if (streak === 1) {
        const fresh = [
          'A single step. That is all it ever takes.',
          'The seed has been planted. Trust the process.',
          'Today you chose yourself. That matters.',
        ]
        return fresh[Math.floor(Math.random() * fresh.length)]
      }
      if (streak === 3) return 'Three days. A pattern is forming. Stay with it.'
      if (streak === 7) return 'One full week. Your discipline is becoming devotion.'
      if (streak === 14) return 'Two weeks of showing up. This is no longer effort — it is who you are becoming.'
      if (streak === 21) return 'Twenty-one days. What began as intention is now dharma. The Gita teaches: the self is its own friend and its own enemy.'
      if (streak === 30) return 'A full month. You have proven something to yourself that no one can take away.'
      if (streak > 30 && streak % 10 === 0) return `${streak} days. Your consistency speaks louder than any intention ever could.`
      if (streak > longestStreak && longestStreak > 0) return `A new personal record — ${streak} days. You have surpassed your past self.`
      const ongoing = [
        `${streak} days and counting. Keep showing up.`,
        'Another day honored. The practice deepens.',
        'Consistency is the quiet form of courage.',
        'You showed up again. That is the whole practice.',
      ]
      return ongoing[Math.floor(Math.random() * ongoing.length)]
    } else {
      if (longestStreak >= 7) {
        return 'A pause is not a failure. Even the river rests in still pools before flowing on.'
      }
      const missed = [
        'Rest is also practice. Tomorrow is a new beginning.',
        'Not today — and that is honest. Honesty is the first discipline.',
        'The path does not disappear because you paused. It waits.',
        'Be gentle with yourself. Even the moon wanes before it grows full again.',
      ]
      return missed[Math.floor(Math.random() * missed.length)]
    }
  }

  return {
    // State
    tasks,
    loading,
    hasTasks,

    // Computed lists
    recurringTasks,
    milestoneTasks,
    completedTasks,
    skippedTasks,

    // Actions
    load,
    checkIn,
    undoCheckIn,
    updateProgress,
    deleteGoal,
    createGoal,
  }
}
