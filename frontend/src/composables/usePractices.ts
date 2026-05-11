/**
 * Practice (recurring) management composable.
 *
 * Loads today's practices and exposes check-in / undo / create / delete
 * actions. Generates streak-based spiritual feedback messages.
 */

import { ref, computed } from 'vue'
import { useApi } from '@/composables/useApi'
import { useLocalDate } from '@/composables/useLocalDate'
import { useNotification } from '@/composables/useNotification'
import type { PracticeTask } from '@/types'

interface PracticeInternal extends PracticeTask {
  _currentStreak: number
  _longestStreak: number
}

export function usePractices() {
  const api = useApi()
  const { today } = useLocalDate()
  const { notify } = useNotification()

  const practices = ref<PracticeInternal[]>([])
  const loading = ref(true)
  const feedbackMessages = ref<Record<string, string>>({})
  const savingState = ref<Record<string, boolean>>({})

  function withLiveState(list: PracticeInternal[]): PracticeTask[] {
    return list.map(p => ({
      ...p,
      feedbackMessage: feedbackMessages.value[p.id] ?? null,
      saving: savingState.value[p.id] ?? false,
    }))
  }

  const activePractices = computed(() => practices.value.filter(p => !p.checkedIn))
  const pendingPractices = computed(() => withLiveState(activePractices.value))
  const completedPractices = computed(() =>
    withLiveState(practices.value.filter(p => p.checkedIn && p.completedToday === true))
  )
  const skippedPractices = computed(() =>
    withLiveState(practices.value.filter(p => p.checkedIn && p.completedToday === false))
  )
  const hasPractices = computed(() => practices.value.length > 0)

  async function loadPractices() {
    loading.value = true
    try {
      const data = await api.get<any>(`/practices?date=${today()}`)
      const items = Array.isArray(data) ? data : (data?.practices || data?.items || [])
      practices.value = items.map((p: any) => {
        const checkIn = p.checkIn ?? null
        const checkedIn = checkIn != null
        const completedToday = checkIn?.completed ?? null
        return {
          id: p.id,
          title: p.title,
          checkedIn,
          completedToday,
          feedbackMessage: null,
          saving: false,
          _currentStreak: p.currentStreak ?? 0,
          _longestStreak: p.longestStreak ?? 0,
        }
      })
      for (const p of practices.value) {
        if (p.checkedIn) {
          feedbackMessages.value[p.id] = generateFeedback(
            p.completedToday ? p._currentStreak - 1 : 0,
            p._longestStreak,
            p.completedToday ?? false,
          )
        }
      }
    } catch {
      notify.error('Failed to load practices')
      practices.value = []
    } finally {
      loading.value = false
    }
  }

  async function checkIn(id: string, completed: boolean) {
    savingState.value[id] = true
    try {
      await api.post(`/practices/${id}/checkin`, { completed, date: today() })
      const p = practices.value.find(x => x.id === id)
      if (p) {
        feedbackMessages.value[id] = generateFeedback(
          p._currentStreak, p._longestStreak, completed,
        )
        p.checkedIn = true
        p.completedToday = completed
        if (completed) p._currentStreak += 1
        else p._currentStreak = 0
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
      await api.delete(`/practices/${id}/checkin?date=${today()}`)
      const p = practices.value.find(x => x.id === id)
      if (p) {
        p.checkedIn = false
        p.completedToday = null
      }
      delete feedbackMessages.value[id]
    } catch {
      notify.error('Failed to undo check-in')
    } finally {
      savingState.value[id] = false
    }
  }

  async function deletePractice(id: string) {
    try {
      await api.delete(`/practices/${id}`)
      practices.value = practices.value.filter(p => p.id !== id)
      delete feedbackMessages.value[id]
      delete savingState.value[id]
    } catch {
      notify.error('Failed to delete practice')
    }
  }

  async function createPractice(title: string) {
    await api.post('/practices', { title })
    await loadPractices()
  }

  async function updatePractice(id: string, body: { title?: string; deeperWhy?: string; archived?: boolean }) {
    await api.patch(`/practices/${id}`, body)
  }

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
    practices,
    loading,
    hasPractices,
    pendingPractices,
    completedPractices,
    skippedPractices,
    loadPractices,
    checkIn,
    undoCheckIn,
    deletePractice,
    createPractice,
    updatePractice,
  }
}
