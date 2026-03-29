<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useApi } from '@/composables/useApi'
import SacredIcons from '@/components/icons/SacredIcons.vue'

const api = useApi()

const entries = ref<any[]>([])
const loading = ref(true)
const error = ref('')

// Recording state
const recording = ref(false)
const recordingSeconds = ref(0)
const recordingInterval = ref<ReturnType<typeof setInterval> | null>(null)
const mediaRecorder = ref<MediaRecorder | null>(null)
const audioChunks = ref<Blob[]>([])
const uploading = ref(false)
const uploadSuccess = ref(false)
const uploadError = ref('')
const micDenied = ref(false)

async function loadEntries() {
  loading.value = true
  error.value = ''
  try {
    const data = await api.get<any>('/voice/entries')
    entries.value = Array.isArray(data) ? data : (data?.entries || data?.items || [])
  } catch {
    error.value = 'Could not load voice entries.'
  } finally {
    loading.value = false
  }
}

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

    // Get presigned URL
    const { upload_url: uploadUrl, key } = await api.post<any>('/voice/upload-url', {
      content_type: 'audio/webm',
      file_size: blob.size,
    })

    // Upload to S3
    const uploadRes = await fetch(uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'audio/webm' },
      body: blob,
    })
    if (!uploadRes.ok) throw new Error('Upload failed')

    // Register entry
    await api.post('/voice/entries', {
      key,
      duration_seconds: recordingSeconds.value,
    })

    uploadSuccess.value = true
    audioChunks.value = []
    await loadEntries()
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

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })
}

function statusColor(status: string) {
  const map: Record<string, string> = {
    Completed: 'bg-[rgba(90,160,90,0.12)] text-green-700',
    Transcribing: 'bg-[rgba(196,135,59,0.14)] text-[#8b5a1b]',
    Pending: 'bg-[rgba(139,90,43,0.1)] text-[#6b5740]',
    Failed: 'bg-[rgba(220,50,50,0.1)] text-red-600',
  }
  return map[status] || 'bg-[rgba(139,90,43,0.1)] text-[#6b5740]'
}

onBeforeUnmount(() => {
  if (recordingInterval.value) clearInterval(recordingInterval.value)
  if (mediaRecorder.value && recording.value) {
    mediaRecorder.value.stop()
  }
})

onMounted(loadEntries)
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5 p-4 sm:p-6">
    <!-- Header -->
    <div class="flex items-center gap-3">
      <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white">
        <SacredIcons name="shankha" :size="20" />
      </div>
      <div>
        <h1 class="font-serif text-xl font-bold tracking-wide text-[#2b1e10] sm:text-2xl">Voice Notes</h1>
        <p class="mt-0.5 text-sm text-[#6b5740]">Speak your thoughts aloud and have them transcribed.</p>
      </div>
    </div>

    <!-- Record section -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px] sm:p-6">
      <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Record a Voice Note</p>

      <div v-if="micDenied" class="mt-4 rounded-2xl bg-[rgba(220,50,50,0.08)] px-4 py-3 text-sm text-red-700">
        Microphone access was denied. Please allow microphone access in your browser settings.
      </div>

      <div class="mt-5 flex flex-col items-center gap-4">
        <!-- Waveform / idle indicator -->
        <div class="flex h-12 items-center gap-1">
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
            <span class="text-sm text-[#6b5740]">Processing...</span>
          </template>
          <template v-else>
            <div class="flex gap-1">
              <span v-for="i in 12" :key="i" class="h-2 w-1.5 rounded-full bg-[rgba(139,90,43,0.2)]" />
            </div>
          </template>
        </div>

        <p v-if="recording" class="font-mono text-3xl font-bold text-[#c4873b]">{{ formatTime(recordingSeconds) }}</p>

        <div class="flex gap-3">
          <button
            v-if="!recording && !uploading"
            @click="startRecording"
            class="flex min-h-[44px] items-center gap-2 rounded-full bg-gradient-to-r from-[#c4873b] to-[#8b5a1b] px-6 py-3 text-sm font-semibold text-white shadow-[0_4px_16px_rgba(139,90,43,0.25)] transition duration-200 hover:-translate-y-0.5"
          >
            <span class="h-2.5 w-2.5 rounded-full bg-white" />
            Record
          </button>
          <button
            v-if="recording"
            @click="stopRecording"
            class="flex min-h-[44px] items-center gap-2 rounded-full bg-red-600 px-6 py-3 text-sm font-semibold text-white transition duration-200 hover:-translate-y-0.5"
          >
            <span class="h-2.5 w-2.5 rounded bg-white" />
            Stop
          </button>
          <div v-if="uploading" class="flex items-center gap-2 rounded-full bg-[rgba(139,90,43,0.08)] px-6 py-3 text-sm text-[#6b5740]">
            <span class="h-4 w-4 animate-spin rounded-full border-2 border-[#c4873b] border-t-transparent" />
            Uploading...
          </div>
        </div>

        <p v-if="uploadError" class="rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-sm text-red-700">{{ uploadError }}</p>
        <p v-if="uploadSuccess" class="rounded-xl bg-[rgba(90,160,90,0.12)] px-4 py-2 text-sm text-green-700">Voice note uploaded and queued for transcription!</p>
      </div>
    </div>

    <!-- Entries list -->
    <div class="rounded-2xl border border-[rgba(139,90,43,0.12)] bg-[rgba(250,245,237,0.88)] p-4 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[20px] sm:p-6">
      <div class="flex items-center justify-between">
        <p class="text-[9px] font-bold uppercase tracking-[0.2em] text-[#a38d6d]">Your Voice Notes</p>
        <button @click="loadEntries" class="min-h-[44px] px-2 text-xs text-[#c4873b] transition duration-200 hover:underline">Refresh</button>
      </div>

      <p v-if="error" class="mt-3 text-sm text-red-700">{{ error }}</p>

      <div v-if="loading" class="mt-4 space-y-3">
        <div v-for="i in 3" :key="i" class="h-16 animate-pulse rounded-2xl bg-[rgba(139,90,43,0.06)]" />
      </div>

      <div v-else-if="entries.length === 0" class="mt-6 text-center">
        <p class="font-serif text-lg text-[#2b1e10]">No voice notes yet</p>
        <p class="mt-1 text-sm text-[#6b5740]">Record your first note above.</p>
      </div>

      <ul v-else class="mt-4 space-y-3">
        <li
          v-for="entry in entries"
          :key="entry.id"
          class="rounded-2xl border border-[rgba(139,90,43,0.1)] bg-[rgba(250,245,237,0.7)] p-4"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="rounded-full px-2.5 py-0.5 text-[10px] font-medium uppercase tracking-[0.1em]" :class="statusColor(entry.status)">
                  {{ entry.status || 'Pending' }}
                </span>
                <span class="text-xs text-[#b5996f]">{{ entry.created_at ? formatDate(entry.created_at) : '' }}</span>
                <span v-if="entry.duration_seconds" class="text-xs text-[#b5996f]">| {{ formatTime(entry.duration_seconds) }}</span>
              </div>
              <p v-if="entry.transcript" class="mt-2 text-sm leading-relaxed text-[#2b1e10]">{{ entry.transcript }}</p>
              <p v-else-if="entry.status === 'Transcribing'" class="mt-2 text-sm italic text-[#9a8568]">Transcription in progress...</p>
              <p v-else-if="entry.status === 'Pending'" class="mt-2 text-sm italic text-[#9a8568]">Waiting to be transcribed.</p>
              <p v-else-if="entry.status === 'Failed'" class="mt-2 text-sm text-red-500">Transcription failed.</p>
            </div>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
