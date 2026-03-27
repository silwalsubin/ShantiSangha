<script setup lang="ts">
definePageMeta({ middleware: 'auth', layout: 'app' })

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
    Transcribing: 'bg-[rgba(201,146,98,0.14)] text-[#8a5b3f]',
    Pending: 'bg-[rgba(138,91,63,0.1)] text-[#6c5c4d]',
    Failed: 'bg-[rgba(220,50,50,0.1)] text-red-600',
  }
  return map[status] || 'bg-[rgba(138,91,63,0.1)] text-[#6c5c4d]'
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
  <div class="mx-auto max-w-2xl space-y-6">
    <div>
      <h1 class="font-serif text-2xl text-[#2b221a]">Voice Notes</h1>
      <p class="mt-1 text-sm text-[#6c5c4d]">Speak your thoughts aloud and have them transcribed.</p>
    </div>

    <!-- Record section -->
    <div class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.82)] p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[14px]">
      <p class="text-xs font-bold uppercase tracking-widest text-[#8a5b3f]">Record a Voice Note</p>

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
              class="w-1.5 rounded-full bg-gradient-to-t from-[#8a5b3f] to-[#c99262] animate-pulse"
              :style="{
                height: `${16 + Math.sin(i * 0.8) * 14 + Math.random() * 8}px`,
                animationDelay: `${i * 80}ms`,
              }"
            />
          </template>
          <template v-else-if="uploading">
            <span class="text-sm text-[#6c5c4d]">Processing…</span>
          </template>
          <template v-else>
            <div class="flex gap-1">
              <span v-for="i in 12" :key="i" class="h-2 w-1.5 rounded-full bg-[rgba(138,91,63,0.2)]" />
            </div>
          </template>
        </div>

        <p v-if="recording" class="font-mono text-3xl font-bold text-[#8a5b3f]">{{ formatTime(recordingSeconds) }}</p>

        <div class="flex gap-3">
          <button
            v-if="!recording && !uploading"
            @click="startRecording"
            class="flex items-center gap-2 rounded-full bg-[#8a5b3f] px-6 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5 hover:bg-[#7a4c32]"
          >
            <span class="h-2.5 w-2.5 rounded-full bg-white" />
            Record
          </button>
          <button
            v-if="recording"
            @click="stopRecording"
            class="flex items-center gap-2 rounded-full bg-red-600 px-6 py-3 text-sm font-semibold text-white transition hover:-translate-y-0.5"
          >
            <span class="h-2.5 w-2.5 rounded bg-white" />
            Stop
          </button>
          <div v-if="uploading" class="flex items-center gap-2 rounded-full bg-[rgba(138,91,63,0.08)] px-6 py-3 text-sm text-[#6c5c4d]">
            <span class="h-4 w-4 animate-spin rounded-full border-2 border-[#c99262] border-t-transparent" />
            Uploading…
          </div>
        </div>

        <p v-if="uploadError" class="rounded-xl bg-[rgba(220,50,50,0.08)] px-4 py-2 text-sm text-red-700">{{ uploadError }}</p>
        <p v-if="uploadSuccess" class="rounded-xl bg-[rgba(90,160,90,0.12)] px-4 py-2 text-sm text-green-700">Voice note uploaded and queued for transcription!</p>
      </div>
    </div>

    <!-- Entries list -->
    <div class="rounded-3xl border border-[rgba(101,76,52,0.14)] bg-[rgba(255,250,243,0.82)] p-6 shadow-[0_8px_40px_rgba(82,54,29,0.08)] backdrop-blur-[14px]">
      <div class="flex items-center justify-between">
        <p class="text-xs font-bold uppercase tracking-widest text-[#8a5b3f]">Your Voice Notes</p>
        <button @click="loadEntries" class="text-xs text-[#8a5b3f] hover:underline">Refresh</button>
      </div>

      <p v-if="error" class="mt-3 text-sm text-red-700">{{ error }}</p>

      <div v-if="loading" class="mt-4 space-y-3">
        <div v-for="i in 3" :key="i" class="h-16 animate-pulse rounded-2xl bg-[rgba(138,91,63,0.08)]" />
      </div>

      <div v-else-if="entries.length === 0" class="mt-6 text-center">
        <p class="font-serif text-lg text-[#2b221a]">No voice notes yet</p>
        <p class="mt-1 text-sm text-[#6c5c4d]">Record your first note above.</p>
      </div>

      <ul v-else class="mt-4 space-y-3">
        <li
          v-for="entry in entries"
          :key="entry.id"
          class="rounded-2xl border border-[rgba(101,76,52,0.1)] bg-[rgba(255,248,239,0.7)] p-4"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="rounded-full px-2.5 py-0.5 text-xs font-medium" :class="statusColor(entry.status)">
                  {{ entry.status || 'Pending' }}
                </span>
                <span class="text-xs text-[#b89c87]">{{ entry.created_at ? formatDate(entry.created_at) : '' }}</span>
                <span v-if="entry.duration_seconds" class="text-xs text-[#b89c87]">· {{ formatTime(entry.duration_seconds) }}</span>
              </div>
              <p v-if="entry.transcript" class="mt-2 text-sm leading-relaxed text-[#2b221a]">{{ entry.transcript }}</p>
              <p v-else-if="entry.status === 'Transcribing'" class="mt-2 text-sm italic text-[#b89c87]">Transcription in progress…</p>
              <p v-else-if="entry.status === 'Pending'" class="mt-2 text-sm italic text-[#b89c87]">Waiting to be transcribed.</p>
              <p v-else-if="entry.status === 'Failed'" class="mt-2 text-sm text-red-500">Transcription failed.</p>
            </div>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
