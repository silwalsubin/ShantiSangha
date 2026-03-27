<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'app' })

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
  <div class="mx-auto flex h-[calc(100vh-10rem)] max-w-2xl flex-col lg:h-[calc(100vh-6rem)]">
    <!-- Header -->
    <div class="mb-4 flex items-center gap-3">
      <NuxtLink to="/app/chat" class="rounded-xl p-1.5 text-[#6c5c4d] transition hover:bg-[rgba(138,91,63,0.08)]">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
        </svg>
      </NuxtLink>
      <div>
        <h1 class="font-serif text-xl text-[#2b221a]">{{ conversation?.title || 'Conversation' }}</h1>
      </div>
    </div>

    <p v-if="error" class="mb-3 rounded-2xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-sm text-red-700">{{ error }}</p>

    <!-- Messages -->
    <div class="flex-1 overflow-y-auto rounded-3xl border border-[rgba(101,76,52,0.12)] bg-[rgba(255,250,243,0.72)] p-4 backdrop-blur-[14px]">
      <div v-if="loading" class="space-y-4 p-2">
        <div v-for="i in 4" :key="i" class="h-12 animate-pulse rounded-2xl bg-[rgba(138,91,63,0.08)]" :class="i % 2 === 0 ? 'ml-12' : 'mr-12'" />
      </div>

      <div v-else-if="messages.length === 0" class="flex h-full flex-col items-center justify-center text-center">
        <p class="font-serif text-xl text-[#2b221a]">Begin your conversation</p>
        <p class="mt-2 text-sm text-[#6c5c4d]">Share what's on your mind. I'm here to listen and support you.</p>
      </div>

      <div v-else class="space-y-4 pb-2">
        <div
          v-for="(msg, i) in messages"
          :key="i"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[80%] rounded-2xl px-4 py-3 text-sm leading-relaxed"
            :class="msg.role === 'user'
              ? 'rounded-br-md bg-[#2b221a] text-[#fff8f1]'
              : 'rounded-bl-md border border-[rgba(101,76,52,0.12)] bg-[rgba(255,248,239,0.95)] text-[#2b221a]'"
          >
            <span v-if="msg.role === 'assistant' && streaming && i === messages.length - 1 && msg.content === ''" class="inline-flex gap-1">
              <span class="h-2 w-2 animate-bounce rounded-full bg-[#c99262]" style="animation-delay:0ms" />
              <span class="h-2 w-2 animate-bounce rounded-full bg-[#c99262]" style="animation-delay:150ms" />
              <span class="h-2 w-2 animate-bounce rounded-full bg-[#c99262]" style="animation-delay:300ms" />
            </span>
            <span v-else>{{ msg.content }}</span>
            <span v-if="msg.role === 'assistant' && streaming && i === messages.length - 1 && msg.content !== ''" class="ml-1 inline-block h-4 w-0.5 animate-pulse bg-[#c99262] align-middle" />
          </div>
        </div>
        <div ref="messagesEnd" />
      </div>
    </div>

    <!-- Input -->
    <div class="mt-3 flex gap-2">
      <textarea
        v-model="inputText"
        @keydown="handleKeydown"
        placeholder="Share what's on your mind…"
        rows="2"
        :disabled="sending"
        class="flex-1 resize-none rounded-2xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.9)] px-4 py-3 text-sm text-[#2b221a] placeholder-[#b89c87] outline-none transition focus:border-[#c99262] focus:ring-1 focus:ring-[#c99262] disabled:opacity-60"
      />
      <button
        @click="sendMessage"
        :disabled="sending || !inputText.trim()"
        class="self-end rounded-2xl bg-[#2b221a] px-4 py-3 text-[#fff8f1] transition hover:-translate-y-0.5 disabled:opacity-50"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
        </svg>
      </button>
    </div>
    <p class="mt-1.5 text-center text-xs text-[#b89c87]">Press Enter to send · Shift+Enter for new line</p>
  </div>
</template>
