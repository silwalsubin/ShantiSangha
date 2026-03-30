/**
 * Shared type definitions for the frontend.
 *
 * All interfaces used across multiple components or pages live here.
 * Page-specific types that are only used in one file can stay local,
 * but anything shared should be defined and exported from this file.
 */

// --- Tasks & Goals ---

export interface Task {
  id: string
  title: string
  type: 'Recurring' | 'OneTime'
  checkedIn: boolean
  completedToday: boolean | null
  daysRemaining: number | null
  progress: number
  feedbackMessage: string | null
  saving: boolean
}

export interface Goal {
  id: string
  title: string
  type: 'Recurring' | 'OneTime'
  deeperWhy: string | null
  currentStreak: number
  longestStreak: number
  frequency: string | null
  frequencyTarget: number | null
  targetDate: string | null
  completedAt: string | null
  daysRemaining: number | null
  progress: number
  noteCount: number
  createdAt: string
}

export interface CheckIn {
  id: string
  date: string
  completed: boolean
  note: string | null
  createdAt: string
}

// --- Conversations & Chat ---

export interface Conversation {
  id: string
  title: string
  lastMessage: string | null
  createdAt: string
  updatedAt: string
}

export interface Message {
  id?: string
  role: 'user' | 'assistant'
  content: string
  createdAt?: string
}

// --- Journal ---

export interface JournalEntry {
  id: string
  title: string
  content: string
  summary: string | null
  createdAt: string
  updatedAt: string
}

// --- Voice ---

export interface VoiceEntry {
  id: string
  title: string | null
  status: 'pending' | 'transcribing' | 'completed' | 'failed'
  transcript: string | null
  duration: number | null
  createdAt: string
}

// --- Insights ---

export interface Insight {
  id: string
  content: string
  source: 'conversation' | 'journal'
  sourceId: string
  createdAt: string
}

// --- Timeline (Reflect page) ---

export interface TimelineItem {
  id: string
  type: 'conversation' | 'journal' | 'voice'
  title: string
  preview: string
  date: string
  route: string
}
