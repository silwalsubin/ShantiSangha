<script setup lang="ts">
import { ref, computed, onMounted, watch, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const route = useRoute()
const api = useApi()
const id = computed(() => route.params.id as string)

interface Message {
  id?: string
  role: 'user' | 'assistant'
  content: string
  created_at?: string
}

const conversation = ref<any>(null)
const messages = ref<Message[]>([])
const loading = ref(true)
const error = ref('')
const inputText = ref('')
const sending = ref(false)
const streaming = ref(false)
const messagesEnd = ref<HTMLElement | null>(null)

async function loadConversation() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get<any>(`/conversations/${id.value}`)
    conversation.value = data
    messages.value = data.messages || []
  } catch {
    error.value = 'Could not load conversation.'
  } finally {
    loading.value = false
    nextTick(scrollToBottom)
  }
}

function scrollToBottom() {
  messagesEnd.value?.scrollIntoView({ behavior: 'smooth' })
}

async function sendMessage() {
  const text = inputText.value.trim()
  if (!text || sending.value) return

  inputText.value = ''
  sending.value = true
  streaming.value = true
  error.value = ''

  // Add user message immediately
  messages.value.push({ role: 'user', content: text })
  nextTick(scrollToBottom)

  try {
    const token = await api.getToken()
    const response = await fetch(`${api.base}/conversations/${id.value}/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({ content: text }),
    })

    if (!response.ok) throw new Error(`API error ${response.status}`)

    const reader = response.body!.getReader()
    const decoder = new TextDecoder()

    // Push placeholder assistant message
    messages.value.push({ role: 'assistant', content: '' })
    nextTick(scrollToBottom)

    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      messages.value[messages.value.length - 1].content += decoder.decode(value)
      nextTick(scrollToBottom)
    }
  } catch (e: any) {
    error.value = 'Could not send message. Please try again.'
    // Remove the placeholder if it's empty
    if (messages.value[messages.value.length - 1]?.role === 'assistant' &&
        messages.value[messages.value.length - 1]?.content === '') {
      messages.value.pop()
    }
  } finally {
    sending.value = false
    streaming.value = false
  }
}

function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    sendMessage()
  }
}

onMounted(loadConversation)
watch(id, loadConversation)
</script>

<template>
  <div class="flex h-[100dvh] max-h-[100dvh] flex-col sm:mx-auto sm:h-[calc(100vh-4rem)] sm:max-h-[calc(100vh-4rem)] sm:max-w-2xl sm:py-2">

    <!-- Header -->
    <div class="flex shrink-0 items-center gap-2.5 border-b border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.95)] px-4 py-3 backdrop-blur-[20px] sm:rounded-t-2xl sm:border sm:border-b-0 sm:border-[rgba(139,90,43,0.12)]">
      <RouterLink
        to="/app/chat"
        class="flex h-[44px] w-[44px] items-center justify-center rounded-xl text-[#6b5740] transition duration-200 hover:bg-[rgba(139,90,43,0.08)] active:scale-95"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 19l-7-7 7-7" />
        </svg>
      </RouterLink>
      <SacredIcons name="dialogue" :size="18" class="shrink-0 text-[#c4873b]" />
      <div class="min-w-0 flex-1">
        <h1 class="truncate font-serif text-[16px] font-bold tracking-wide text-[#2b1e10]">{{ conversation?.title || 'Conversation' }}</h1>
      </div>
    </div>

    <!-- Error -->
    <p v-if="error" class="mx-4 mt-2 rounded-2xl border border-[rgba(220,50,50,0.12)] bg-[rgba(220,50,50,0.06)] px-4 py-2 text-[13px] text-red-700">{{ error }}</p>

    <!-- Messages area -->
    <div class="flex-1 overflow-y-auto bg-[rgba(250,245,237,0.5)] px-3 py-4 sm:border-x sm:border-[rgba(139,90,43,0.12)] sm:px-4">

      <!-- Loading -->
      <div v-if="loading" class="space-y-4 px-1">
        <div v-for="i in 4" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" :class="i % 2 === 0 ? 'ml-10' : 'mr-10'" />
      </div>

      <!-- Empty state -->
      <div v-else-if="messages.length === 0" class="flex h-full flex-col items-center justify-center px-6 text-center">
        <SacredIcons name="dialogue" :size="36" class="mb-4 text-[#b5996f]" />
        <p class="font-serif text-lg font-bold text-[#2b1e10]">Begin your conversation</p>
        <p class="mt-2 text-[13px] leading-relaxed text-[#6b5740]">Share what is on your mind. I am here to listen and support you.</p>
      </div>

      <!-- Messages -->
      <div v-else class="space-y-3 pb-2">
        <div
          v-for="(msg, i) in messages"
          :key="i"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[85%] rounded-2xl px-4 py-3 text-[14px] leading-relaxed sm:max-w-[75%]"
            :class="msg.role === 'user'
              ? 'rounded-br-md bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)]'
              : 'rounded-bl-md border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.95)] text-[#2b1e10] shadow-[0_1px_4px_rgba(82,54,29,0.06)]'"
          >
            <span v-if="msg.role === 'assistant' && streaming && i === messages.length - 1 && msg.content === ''" class="inline-flex gap-1.5 py-1">
              <span class="h-2 w-2 animate-bounce rounded-full bg-[#c4873b]" style="animation-delay:0ms" />
              <span class="h-2 w-2 animate-bounce rounded-full bg-[#c4873b]" style="animation-delay:150ms" />
              <span class="h-2 w-2 animate-bounce rounded-full bg-[#c4873b]" style="animation-delay:300ms" />
            </span>
            <span v-else class="whitespace-pre-wrap">{{ msg.content }}</span>
            <span v-if="msg.role === 'assistant' && streaming && i === messages.length - 1 && msg.content !== ''" class="ml-1 inline-block h-4 w-0.5 animate-pulse bg-[#c4873b] align-middle" />
          </div>
        </div>
        <div ref="messagesEnd" />
      </div>
    </div>

    <!-- Input area (sticky bottom with safe-area) -->
    <div class="shrink-0 border-t border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.95)] px-3 pb-[env(safe-area-inset-bottom,8px)] pt-3 backdrop-blur-[20px] sm:rounded-b-2xl sm:border sm:border-t-0 sm:border-[rgba(139,90,43,0.12)] sm:px-4 sm:pb-3">
      <div class="flex items-end gap-2">
        <textarea
          v-model="inputText"
          @keydown="handleKeydown"
          placeholder="Share what is on your mind..."
          rows="2"
          :disabled="sending"
          class="min-h-[44px] flex-1 resize-none rounded-2xl border border-[rgba(139,90,43,0.15)] bg-[rgba(250,245,237,0.9)] px-4 py-3 text-[14px] text-[#2b1e10] placeholder-[#9a8568] outline-none transition duration-200 focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b] disabled:opacity-60"
        />
        <button
          @click="sendMessage"
          :disabled="sending || !inputText.trim()"
          class="flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-2xl bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 hover:-translate-y-0.5 disabled:opacity-50"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
          </svg>
        </button>
      </div>
      <p class="mt-2 text-center text-[10px] uppercase tracking-[0.2em] text-[#a38d6d]">Enter to send -- Shift+Enter for new line</p>
    </div>

  </div>
</template>
