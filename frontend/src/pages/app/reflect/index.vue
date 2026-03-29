<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()
const router = useRouter()

// Action card state
const creating = ref(false)
const error = ref('')

// Unified timeline
const timeline = ref<any[]>([])
const loadingTimeline = ref(true)

// Voice recording state (inline)
const recording = ref(false)
const recordingSeconds = ref(0)
const recordingInterval = ref<ReturnType<typeof setInterval> | null>(null)
const mediaRecorder = ref<MediaRecorder | null>(null)
const audioChunks = ref<Blob[]>([])
const uploading = ref(false)
const uploadSuccess = ref(false)
const uploadError = ref('')
const micDenied = ref(false)

async function startConversation() {
  creating.value = true
  error.value = ''
  try {
    const conv = await api.post<any>('/conversations', { title: 'New Conversation' })
    router.push(`/app/reflect/chat/${conv.id}`)
  } catch {
    error.value = 'Could not create conversation.'
  } finally {
    creating.value = false
  }
}

async function loadTimeline() {
  loadingTimeline.value = true
  try {
    const [convData, journalData, voiceData] = await Promise.all([
      api.get<any>('/conversations').catch(() => []),
      api.get<any>('/journals').catch(() => []),
      api.get<any>('/voice/entries').catch(() => []),
    ])

    const conversations = (Array.isArray(convData) ? convData : (convData?.conversations || convData?.items || []))
      .map((c: any) => ({
        id: c.id,
        type: 'conversation' as const,
        title: c.title || 'Conversation',
        preview: c.last_message || c.lastMessage || '',
        date: c.created_at || c.createdAt,
        route: `/app/reflect/chat/${c.id}`,
      }))

    const journals = (Array.isArray(journalData) ? journalData : (journalData?.journals || journalData?.items || []))
      .map((j: any) => ({
        id: j.id,
        type: 'journal' as const,
        title: j.title || 'Untitled',
        preview: j.content?.slice(0, 100) || '',
        date: j.created_at || j.createdAt,
        route: `/app/reflect/journal/${j.id}`,
      }))

    const voices = (Array.isArray(voiceData) ? voiceData : (voiceData?.entries || voiceData?.items || []))
      .map((v: any) => ({
        id: v.id,
        type: 'voice' as const,
        title: v.transcript?.slice(0, 60) || 'Voice note',
        preview: v.duration_seconds ? formatTime(v.duration_seconds) + (v.status ? ' -- ' + v.status : '') : (v.status || ''),
        date: v.created_at || v.createdAt,
        route: `/app/reflect/voice/${v.id}`,
      }))

    timeline.value = [...conversations, ...journals, ...voices]
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
  } catch {
    // Silent fail — individual sections may have loaded
  } finally {
    loadingTimeline.value = false
  }
}

// Voice recording (reused from voice/index.vue)
async function startRecording() {
  uploadError.value = ''
  uploadSuccess.value = false
  audioChunks.value = []
  micDenied.value = false

  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    const recorder = new MediaRecorder(stream)
    mediaRecorder.value = recorder

    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) audioChunks.value.push(e.data)
    }

    recorder.onstop = async () => {
      stream.getTracks().forEach(t => t.stop())
      await processRecording()
    }

    recorder.start(1000)
    recording.value = true
    recordingSeconds.value = 0
    recordingInterval.value = setInterval(() => recordingSeconds.value++, 1000)
  } catch (e: any) {
    if (e.name === 'NotAllowedError') {
      micDenied.value = true
    } else {
      uploadError.value = 'Could not access microphone.'
    }
  }
}

function stopRecording() {
  if (mediaRecorder.value && recording.value) {
    mediaRecorder.value.stop()
    recording.value = false
    if (recordingInterval.value) {
      clearInterval(recordingInterval.value)
      recordingInterval.value = null
    }
  }
}

async function processRecording() {
  if (audioChunks.value.length === 0) return
  uploading.value = true
  uploadError.value = ''

  try {
    const blob = new Blob(audioChunks.value, { type: 'audio/webm' })

    const { upload_url: uploadUrl, key } = await api.post<any>('/voice/upload-url', {
      content_type: 'audio/webm',
      file_size: blob.size,
    })

    const uploadRes = await fetch(uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'audio/webm' },
      body: blob,
    })
    if (!uploadRes.ok) throw new Error('Upload failed')

    await api.post('/voice/entries', {
      key,
      duration_seconds: recordingSeconds.value,
    })

    uploadSuccess.value = true
    audioChunks.value = []
    await loadTimeline()
  } catch {
    uploadError.value = 'Could not upload recording. Please try again.'
  } finally {
    uploading.value = false
  }
}

function formatTime(s: number) {
  const m = Math.floor(s / 60)
  const sec = s % 60
  return `${m}:${sec.toString().padStart(2, '0')}`
}

function relativeTime(d: string) {
  if (!d) return ''
  const now = Date.now()
  const then = new Date(d).getTime()
  const diff = now - then
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'Just now'
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days === 1) return 'Yesterday'
  if (days < 7) return `${days}d ago`
  return new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

function typeIcon(type: string) {
  if (type === 'conversation') return 'dialogue'
  if (type === 'journal') return 'scroll'
  return 'shankha'
}

function typeLabel(type: string) {
  if (type === 'conversation') return 'Conversation'
  if (type === 'journal') return 'Journal'
  return 'Voice'
}

onBeforeUnmount(() => {
  if (recordingInterval.value) clearInterval(recordingInterval.value)
  if (mediaRecorder.value && recording.value) {
    mediaRecorder.value.stop()
  }
})

onMounted(loadTimeline)
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 py-5 sm:px-6">

    <!-- Header -->
    <div class="mb-6">
      <p class="text-[13px] sm:text-sm text-[#6b5740]">How would you like to reflect today?</p>
    </div>

    <!-- Error -->
    <p v-if="error" class="mb-4 rounded-2xl border border-[rgba(220,50,50,0.12)] bg-[rgba(220,50,50,0.06)] px-4 py-3 text-[13px] text-red-700">{{ error }}</p>

    <!-- Action Cards -->
    <div class="space-y-3">

      <!-- Talk -->
      <button
        @click="startConversation"
        :disabled="creating"
        class="flex w-full min-h-[68px] items-center gap-4 rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-4 py-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] transition duration-200 hover:border-[rgba(139,90,43,0.25)] hover:shadow-[0_4px_20px_rgba(82,54,29,0.1)] active:scale-[0.99] disabled:opacity-60 sm:px-5"
      >
        <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white shadow-[0_2px_8px_rgba(139,90,43,0.25)]">
          <SacredIcons name="dialogue" :size="20" />
        </div>
        <div class="min-w-0 flex-1 text-left">
          <p class="font-serif text-[16px] font-bold text-[#2b1e10]">{{ creating ? 'Starting...' : 'Talk' }}</p>
          <p class="text-[13px] text-[#6b5740]">Have a conversation with your companion</p>
        </div>
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0 text-[#b5996f]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 5l7 7-7 7" />
        </svg>
      </button>

      <!-- Write -->
      <RouterLink
        to="/app/reflect/journal/new"
        class="flex min-h-[68px] items-center gap-4 rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-4 py-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] transition duration-200 hover:border-[rgba(139,90,43,0.25)] hover:shadow-[0_4px_20px_rgba(82,54,29,0.1)] active:scale-[0.99] sm:px-5"
      >
        <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white shadow-[0_2px_8px_rgba(139,90,43,0.25)]">
          <SacredIcons name="scroll" :size="20" />
        </div>
        <div class="min-w-0 flex-1 text-left">
          <p class="font-serif text-[16px] font-bold text-[#2b1e10]">Write</p>
          <p class="text-[13px] text-[#6b5740]">Journal your thoughts</p>
        </div>
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0 text-[#b5996f]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 5l7 7-7 7" />
        </svg>
      </RouterLink>

      <!-- Speak (inline recorder) -->
      <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-4 py-4 shadow-[0_4px_24px_rgba(82,54,29,0.06)] backdrop-blur-[20px] sm:px-5">
        <div class="flex items-center gap-4">
          <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white shadow-[0_2px_8px_rgba(139,90,43,0.25)]">
            <SacredIcons name="shankha" :size="20" />
          </div>
          <div class="min-w-0 flex-1">
            <p class="font-serif text-[16px] font-bold text-[#2b1e10]">Speak</p>
            <p class="text-[13px] text-[#6b5740]">Record a voice note</p>
          </div>
        </div>

        <!-- Mic denied -->
        <div v-if="micDenied" class="mt-3 rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2.5 text-[13px] text-red-700">
          Microphone access was denied. Please allow microphone access in your browser settings.
        </div>

        <!-- Recording controls -->
        <div class="mt-4 flex flex-col items-center gap-3">
          <!-- Waveform -->
          <div class="flex h-10 items-center gap-1">
            <template v-if="recording">
              <span
                v-for="i in 12"
                :key="i"
                class="w-1.5 rounded-full bg-gradient-to-t from-[#8b5a1b] to-[#c4873b] animate-pulse"
                :style="{
                  height: `${16 + Math.sin(i * 0.8) * 14 + Math.random() * 8}px`,
                  animationDelay: `${i * 80}ms`,
                }"
              />
            </template>
            <template v-else-if="uploading">
              <span class="text-[13px] text-[#6b5740]">Processing...</span>
            </template>
          </div>

          <p v-if="recording" class="font-mono text-2xl font-bold text-[#c4873b]">{{ formatTime(recordingSeconds) }}</p>

          <div class="flex gap-3">
            <button
              v-if="!recording && !uploading"
              @click="startRecording"
              class="flex min-h-[44px] items-center gap-2 rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-5 py-2.5 text-[13px] font-semibold text-white shadow-[0_2px_8px_rgba(139,90,27,0.2)] transition duration-200 hover:-translate-y-0.5"
            >
              <span class="h-2.5 w-2.5 rounded-full bg-white" />
              Record
            </button>
            <button
              v-if="recording"
              @click="stopRecording"
              class="flex min-h-[44px] items-center gap-2 rounded-full bg-red-600 px-5 py-2.5 text-[13px] font-semibold text-white transition duration-200 hover:-translate-y-0.5"
            >
              <span class="h-2.5 w-2.5 rounded bg-white" />
              Stop
            </button>
            <div v-if="uploading" class="flex items-center gap-2 rounded-full bg-[rgba(139,90,43,0.08)] px-5 py-2.5 text-[13px] text-[#6b5740]">
              <span class="h-4 w-4 animate-spin rounded-full border-2 border-[#c4873b] border-t-transparent" />
              Uploading...
            </div>
          </div>

          <p v-if="uploadError" class="rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-[13px] text-red-700">{{ uploadError }}</p>
          <p v-if="uploadSuccess" class="rounded-xl bg-[rgba(90,160,90,0.12)] px-4 py-2 text-[13px] text-green-700">Voice note uploaded and queued for transcription!</p>
        </div>
      </div>
    </div>

    <!-- Recent reflections divider -->
    <div class="my-6 flex items-center gap-3">
      <div class="h-px flex-1 border-t border-dashed border-[rgba(139,90,43,0.12)]" />
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Recent reflections</p>
      <div class="h-px flex-1 border-t border-dashed border-[rgba(139,90,43,0.12)]" />
    </div>

    <!-- Loading skeletons -->
    <div v-if="loadingTimeline" class="space-y-3">
      <div v-for="i in 4" :key="i" class="h-[64px] animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
    </div>

    <!-- Empty state -->
    <div v-else-if="timeline.length === 0" class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-5 py-10 text-center backdrop-blur-[20px]">
      <SacredIcons name="dharma" :size="32" class="mx-auto mb-3 text-[#b5996f]" />
      <p class="font-serif text-lg font-bold text-[#2b1e10]">No reflections yet</p>
      <p class="mt-2 text-[13px] text-[#6b5740]">Choose a way to reflect above and begin your practice.</p>
    </div>

    <!-- Timeline list -->
    <ul v-else class="space-y-2.5">
      <li v-for="item in timeline" :key="`${item.type}-${item.id}`">
        <RouterLink
          :to="item.route"
          class="group flex min-h-[56px] items-center gap-3.5 rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] px-4 py-3.5 shadow-[0_2px_12px_rgba(82,54,29,0.05)] backdrop-blur-[20px] transition duration-200 hover:border-[rgba(139,90,43,0.25)] hover:shadow-[0_4px_20px_rgba(82,54,29,0.1)] active:scale-[0.99] sm:px-5"
        >
          <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[rgba(196,135,59,0.1)] text-[#c4873b]">
            <SacredIcons :name="typeIcon(item.type)" :size="16" />
          </div>
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <p class="truncate text-[14px] font-medium text-[#2b1e10]">{{ item.title }}</p>
              <span class="shrink-0 text-[10px] uppercase tracking-[0.1em] text-[#b5996f]">{{ typeLabel(item.type) }}</span>
            </div>
            <p v-if="item.preview" class="mt-0.5 truncate text-[13px] text-[#6b5740]">{{ item.preview }}</p>
          </div>
          <span class="shrink-0 text-[11px] text-[#9a8568]">{{ relativeTime(item.date) }}</span>
        </RouterLink>
      </li>
    </ul>

    <!-- Footer wisdom -->
    <p v-if="!loadingTimeline && timeline.length > 0" class="mt-8 text-center text-xs italic leading-relaxed text-[#b5996f]">
      "The mind is restless, turbulent, strong and unyielding -- but it is controlled by practice and detachment." -- Bhagavad Gita 6.35
    </p>
  </div>
</template>
