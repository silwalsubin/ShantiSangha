/**
 * Shared type definitions for the frontend.
 *
 * All interfaces used across multiple components or pages live here.
 * Page-specific types that are only used in one file can stay local,
 * but anything shared should be defined and exported from this file.
 */

// --- Reminders (date-based, one-time or yearly) ---

export type ReminderRecurrence = 'none' | 'yearly'

export interface Reminder {
  id: string
  label: string
  date: string
  recurrence: ReminderRecurrence
  remindersEnabled: boolean
  connectionId: string | null
  completedAt: string | null
  createdAt: string
  daysRemaining: number
}

export interface ReminderTask {
  id: string
  label: string
  date: string
  recurrence: ReminderRecurrence
  daysRemaining: number
  completed: boolean
  saving: boolean
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

// --- Timeline (Reflect page) ---

export interface TimelineItem {
  id: string
  type: 'conversation' | 'journal' | 'voice'
  title: string
  preview: string
  date: string
  route: string
}
